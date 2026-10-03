# Blind triage checklist

The order matters. Each layer assumes the one above it is working, so start at the top
and stop descending as soon as something is wrong. Write down what each step told you.

## 0. Can I even talk to the cluster?

```bash
kubectl get nodes -o wide                  # works? → API server, etcd, your kubeconfig are OK
kubectl get --raw /readyz?verbose          # which health checks fail?
```
If `kubectl` fails: read the **error text**. Connection refused ≠ TLS error ≠ timeout.

| Error contains | Think | Look at |
|---|---|---|
| `certificate has expired` / `x509` | expired-certs | `kubeadm certs check-expiration`, `openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates` |
| `connection refused` on :6443 | apiserver not running → why? usually etcd | `crictl ps -a`, `crictl logs <apiserver>`, `crictl logs <etcd>` |
| `Unauthorized` | kubeconfig/cert mismatch | which kubeconfig? `kubectl config view` |
| hangs/timeouts | apiserver up but etcd slow, or node network | `crictl logs etcd`, `etcdctl endpoint health` |

**When the API is gone, the kubelet and containerd are still there.** `crictl`, `journalctl -u kubelet`,
and `/etc/kubernetes/manifests/` are your interface to the control plane.

## 1. Node layer

```bash
kubectl get nodes
kubectl describe node <n>      # Conditions: Ready, MemoryPressure, DiskPressure, PIDPressure; Events
```
On the node:
```bash
systemctl status kubelet; journalctl -u kubelet -n 100 --no-pager   # parse errors, cgroup errors, CNI errors
systemctl status containerd
df -h /; du -xh / --max-depth=3 2>/dev/null | sort -h | tail -20      # full-disk
free -m; top -bn1 | head -20; ps aux --sort=-%cpu | head             # exhaust-node (burn)
ls -la /etc/cni/net.d/                                               # delete-cni
cat /var/lib/kubelet/config.yaml                                     # bad-kubelet-config
systemctl list-units --type=service --state=running | grep -v -e kube -e containerd -e systemd  # anything that shouldn't be there?
```

## 2. Control-plane components (on cp)

```bash
ls /etc/kubernetes/manifests/
crictl pods; crictl ps -a
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1)
crictl logs $(crictl ps -a --name etcd -q | head -1)
kubeadm certs check-expiration
```
etcd recovery, when the data is genuinely gone:
```bash
ls -la /var/lib/etcd-backup/                                  # ops keeps hourly snapshots
mv /etc/kubernetes/manifests/etcd.yaml /tmp/  && sleep 10     # stop etcd
mv /var/lib/etcd /var/lib/etcd.broken
etcdutl snapshot restore /var/lib/etcd-backup/<latest>.db --data-dir /var/lib/etcd
mv /tmp/etcd.yaml /etc/kubernetes/manifests/                  # start etcd
```

## 3. Workloads and scheduling

```bash
kubectl get pods -A -o wide | grep -v Running
kubectl describe pod <p>                       # Events: FailedScheduling (requests), FailedCreatePodSandBox (CNI), Evicted
kubectl get events -A --sort-by=.lastTimestamp | tail -30
kubectl describe node <n> | sed -n '/Allocated resources/,/Events/p'   # exhaust-node (requests)
```

## 4. Networking and DNS

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
kubectl -n kube-system get endpoints kube-dns          # empty → selector or no coredns pods
kubectl -n kube-system get cm coredns -o yaml          # Corefile sanity: zone name, forward target
kubectl run dnstest --rm -it --image=busybox:1.36 --restart=Never -- sh -c \
  'nslookup kubernetes.default; nslookup example.com'  # internal vs external tells variants apart
kubectl -n kube-system logs deploy/coredns
```

## 5. Before you reveal

Write the root cause in the log entry. One sentence. Then `chaos/reveal.sh`.
If you were wrong, the log entry says so and why. That is still a good entry.
