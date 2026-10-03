# k8s-blind-failure-lab

A three-node Kubernetes cluster built with `kubeadm` (no managed service — the control plane is
the point), plus a chaos script that injects one of seven named failures at random. You diagnose
each one blind, fix it, and log it. The log is the deliverable: CKA prep and interview evidence
of debugging, not a claim about it.

```
cp  192.168.56.10   control plane: kube-apiserver, etcd, controller-manager, scheduler
w1  192.168.56.11   worker
w2  192.168.56.12   worker
```

Stack: Ubuntu 22.04 · containerd · kubeadm/kubelet/kubectl 1.31 · Flannel CNI · Vagrant + VirtualBox.

## Failures in the deck

| Failure | Lands on | What breaks | Variants |
|---|---|---|---|
| `expired-certs` | cp | every kubeadm cert is renewed with the clock wound back, so all are expired | — |
| `corrupt-etcd` | cp | etcd's bbolt db is overwritten; hourly snapshots exist in `/var/lib/etcd-backup` | — |
| `delete-cni` | w1/w2 | `/etc/cni/net.d` emptied, kubelet restarted | — |
| `full-disk` | w1/w2 | root filesystem filled to ~20 MiB free | — |
| `bad-kubelet-config` | any | `/var/lib/kubelet/config.yaml` altered | cgroup driver mismatch · unparseable YAML · wrong port · dead clusterDNS |
| `break-dns` | cluster | CoreDNS / kube-dns Service tampered | forward to blackhole · wrong zone · Service selector · scaled to 0 |
| `exhaust-node` | w1/w2 | node resources consumed | out-of-band CPU+RAM burner with an innocent unit name · deployment that books all allocatable CPU |

Variants are picked at random, so the same failure name does not always present the same way.

---

## Implementation steps

### Phase 0 — Prerequisites (30 min)

- Host with ≥ 8 GB RAM free and ~25 GB disk (cp 2.5 GB + 2 × 2 GB workers).
- [Vagrant](https://developer.hashicorp.com/vagrant/install) and [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
  (or `vagrant-libvirt` on Linux). Apple Silicon: VirtualBox is unreliable; use the cloud-VM path below.
- `kubectl` on the host (optional; you can always `vagrant ssh cp`).

**Cheap cloud VMs instead of Vagrant:** three small Ubuntu 22.04 instances with private networking
(Hetzner CX22-class or similar, ~$4–5/mo each). Edit the IPs in `provision/common.sh` and the
Vagrantfile's `NODES` map to match, copy the repo to `/vagrant` on each box, then run
`provision/common.sh` on all three, `provision/control-plane.sh` on cp, `provision/worker.sh` on
workers — with the same `NODE_IP`/`NODE_NAME`/`POD_CIDR` env vars the Vagrantfile passes.
`chaos/inject.sh` uses `vagrant ssh <node> -c`; replace that one line with `ssh root@<node>`.

### Phase 1 — Build the control plane by hand, once (2–3 h)

The provisioning scripts automate this, but do it manually the first time: the CKA exam and every
one of the failures below assume you know what `kubeadm init` actually laid down.

```bash
vagrant up cp --no-provision
vagrant ssh cp
```
Then, step by step, following `provision/common.sh` and `provision/control-plane.sh` as a guide:

1. Disable swap, load `overlay` + `br_netfilter`, set the three sysctls. Know *why* each exists.
2. Install containerd, generate its default config, set `SystemdCgroup = true`. Note the cgroup
   driver; one failure variant turns exactly this against you.
3. Install kubeadm/kubelet/kubectl from `pkgs.k8s.io`, hold the packages, set `--node-ip` in
   `/etc/default/kubelet` (Vagrant's first NIC is NAT; the cluster must use `eth1`).
4. `kubeadm init --apiserver-advertise-address=192.168.56.10 --pod-network-cidr=10.244.0.0/16`.
5. Read what it created before touching anything else:
   - `/etc/kubernetes/manifests/` — four static pods; the kubelet runs them, not the scheduler
   - `/etc/kubernetes/pki/` — the CA, every server/client cert; `kubeadm certs check-expiration`
   - `/etc/kubernetes/*.conf` — kubeconfigs for admin, controller-manager, scheduler, kubelet
   - `/var/lib/kubelet/config.yaml` — the kubelet's config, including `cgroupDriver` and `clusterDNS`
   - `/var/lib/etcd/` — the database
6. Apply Flannel with `--iface=eth1`. Watch `kubectl get nodes` go Ready.
7. `kubeadm token create --print-join-command`.

Then throw it away and let automation do it: `vagrant destroy -f cp && make up`.
If `make up` and your manual build disagree somewhere, you learned something.

### Phase 2 — Join workers, verify, record a baseline (30 min)

```bash
make up            # or vagrant up w1 w2 if cp is already built
make kubeconfig    # export KUBECONFIG=... for host kubectl
make verify        # nodes Ready, /readyz clean, internal+external DNS, scheduling
```
Save a passing `make verify` output somewhere. During a failure you compare against it.
Also look at `/var/lib/etcd-backup` on cp — there is an hourly etcd snapshot cron. You put that
backup there; in the corrupt-etcd failure you are the one who has to remember it exists.

### Phase 3 — Learn the tools that work when kubectl doesn't (1 h)

Spend an hour on cp with the API server deliberately stopped
(`sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/`) and get comfortable with:

- `crictl pods`, `crictl ps -a`, `crictl logs` — see and read control-plane containers without the API
- `journalctl -u kubelet -f` — the kubelet is the only thing left standing and it talks a lot
- `etcdctl endpoint health` / `etcdctl snapshot save` / `etcdutl snapshot restore` with the certs in
  `/etc/kubernetes/pki/etcd/` (`scripts/etcd-snapshot.sh` has the exact flags)
- `kubeadm certs check-expiration` / `kubeadm certs renew all`
- `openssl x509 -in <crt> -noout -dates -subject`

Put the manifest back and confirm `make verify` passes. This hour is what makes Phase 4 possible.

### Phase 4 — The loop (ongoing; 7 failures × ≥ 3 reps each)

```bash
make inject          # or: make inject ONLY=break-dns   (first pass through each type)
make log             # creates logs/entries/NNN-<id>.md from the template; write as you go
# ... diagnose, following docs/triage-checklist.md top-down ...
make reveal          # ONLY after the root cause is written down
make verify          # prove the fix
```
Rules that make the log worth something:

1. **Write the root cause before you reveal.** A wrong hypothesis, recorded, is a better entry than
   a right one you only "knew".
2. **Timer starts at inject.** Record time-to-root-cause and time-to-fix separately. They differ,
   and interviewers care about the first one.
3. **Log the dead ends.** "Checked DNS first because pods were failing, but `nslookup` from a pod
   worked, so I moved to the node" is the sentence that proves you debug systematically.
4. **Use the undo script only as a last resort**, and mark the entry `Solo? = no`. Then re-run that
   failure type the next day.
5. **Don't read `.chaos/` or `chaos/failures/*.sh` during a run.** The scripts are open source so
   you can audit them; read them *after* a reveal, not during.

Suggested order for the first pass, easiest to hardest:
`delete-cni → full-disk → exhaust-node → break-dns → bad-kubelet-config → expired-certs → corrupt-etcd`.
After the first pass, random only.

### Phase 5 — Turn the log into an asset (1 h, after ~20 entries)

- Fill the **Running stats** table in `logs/LOG.md`: attempts, median time-to-RC, best.
- Write a 10-line `docs/lessons.md`: the three things you now check first, the failure that fooled
  you longest and why, what you'd automate on a real cluster (cert expiry alerting, snapshot
  verification, disk alerts).
- Pin the repo. In interviews, open `logs/LOG.md` and walk one entry end to end.

---

## CKA domain mapping

| Failure | Domain | Weight |
|---|---|---|
| expired-certs, corrupt-etcd, bad-kubelet-config | Cluster Architecture, Installation & Configuration (kubeadm, etcd backup/restore, certs) | 25% |
| delete-cni, break-dns | Services & Networking (CNI, CoreDNS) | 20% |
| exhaust-node, full-disk | Workloads & Scheduling (requests, pressure, eviction) | 15% |
| all | Troubleshooting (cluster components, nodes, networking, kubelet logs) | 30% |

Troubleshooting is 30% of the exam. This lab is nothing but that domain, with the others as the
raw material.

## Repository layout

```
Vagrantfile                 3 VMs, provisioner wiring
provision/
  common.sh                 OS prep, containerd, kubeadm/kubelet/kubectl, crictl, etcdctl (all nodes)
  control-plane.sh          kubeadm init, Flannel, kubeconfigs, join script, etcd snapshot cron
  worker.sh                 kubeadm join
chaos/
  inject.sh                 pick a failure + node at random, run it, seal the answer in .chaos/
  reveal.sh                 unseal, show elapsed time and the undo script path
  failures/*.sh             one script per failure; each writes its own undo script
docs/triage-checklist.md    top-down diagnosis order, per-layer commands
logs/LOG.md                 one row per failure — the artifact
logs/entries/TEMPLATE.md    symptom · checked · root cause · fix · time
scripts/
  verify.sh                 health baseline (nodes, /readyz, certs, DNS, scheduling)
  etcd-snapshot.sh          installed on cp as /usr/local/sbin/etcd-snapshot (hourly cron)
  new-log-entry.sh          numbered entry from template
Makefile                    up · verify · inject · reveal · log · snapshot · down
```

`.cluster/` (join token, admin.conf) and `.chaos/` (sealed answers, undo scripts) are generated and
git-ignored.

## Resetting

Fixing is the job, but if a VM is beyond saving: `vagrant destroy -f w1 && vagrant up w1`
rejoins a worker in a few minutes. For cp, `make down && make up` rebuilds everything; the log
survives because it lives in the repo, not the cluster.

## Notes on how the failures are built (read after your first reveal of each)

- **expired-certs** sets the guest clock back 400 days, runs `kubeadm certs renew all`, restores
  the clock, and recreates the static pods. Nothing is forged; the certs are real kubeadm certs that
  happen to be dated in the past. VirtualBox time sync is disabled in the Vagrantfile so the guest
  keeps the clock change long enough for this to work.
- **corrupt-etcd** stops etcd via the manifest, overwrites 2 MiB of `member/snap/db`, and starts it
  again. A snapshot is guaranteed to exist first — the point is the restore, not data loss.
- **break-dns** and **exhaust-node (requests)** act through the API with `kubectl`, which is why
  workers have a kubeconfig. Treat a worker's `/root/.kube/config` as something you would never
  do in production.
