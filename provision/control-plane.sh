#!/usr/bin/env bash
# Runs on cp only. kubeadm init, Flannel CNI, kubeconfigs, join script, etcd backup cron.
set -euxo pipefail
: "${NODE_IP:?}" "${POD_CIDR:?}" "${K8S_VERSION:=1.31}"

mkdir -p /vagrant/.cluster

kubeadm init \
  --apiserver-advertise-address="${NODE_IP}" \
  --apiserver-cert-extra-sans="${NODE_IP},cp" \
  --pod-network-cidr="${POD_CIDR}" \
  --node-name cp \
  --kubernetes-version "stable-${K8S_VERSION}" \
  | tee /vagrant/.cluster/kubeadm-init.log

# kubeconfig for root, vagrant user, and the host (via synced folder)
for home in /root /home/vagrant; do
  mkdir -p "$home/.kube" && cp /etc/kubernetes/admin.conf "$home/.kube/config"
done
chown -R vagrant:vagrant /home/vagrant/.kube
cp /etc/kubernetes/admin.conf /vagrant/.cluster/admin.conf
export KUBECONFIG=/etc/kubernetes/admin.conf

# --- CNI: Flannel, pinned to the private interface ------------------------
curl -fsSL https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml \
  -o /vagrant/.cluster/kube-flannel.yml
# Vagrant boxes have NAT on eth0; flannel must use eth1.
sed -i 's/- --kube-subnet-mgr/- --kube-subnet-mgr\n        - --iface=eth1/' /vagrant/.cluster/kube-flannel.yml
kubectl apply -f /vagrant/.cluster/kube-flannel.yml

# --- join script for workers -----------------------------------------------
kubeadm token create --print-join-command > /vagrant/.cluster/join.sh
chmod +x /vagrant/.cluster/join.sh

# --- etcd backups: the "ops already had backups" assumption ----------------
# Hourly snapshots to /var/lib/etcd-backup. Finding and using these is part of
# recovering from the corrupt-etcd failure.
install -m 755 /vagrant/scripts/etcd-snapshot.sh /usr/local/sbin/etcd-snapshot
cat > /etc/cron.d/etcd-snapshot <<CRON
0 * * * * root /usr/local/sbin/etcd-snapshot >> /var/log/etcd-snapshot.log 2>&1
CRON

# Wait for the control plane to settle, then take the first snapshot.
until kubectl get nodes cp -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q True; do sleep 5; done
/usr/local/sbin/etcd-snapshot

kubectl get nodes -o wide
