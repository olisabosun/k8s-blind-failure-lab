#!/usr/bin/env bash
# FAILURE: expired certificates (control plane).
# kubeadm certs are 1-year. We wind the clock back ~400 days, renew every cert
# (so they are all already expired "today"), restore the clock, and bounce the
# static pods. Symptom: x509: certificate has expired or is not yet valid.
source "$(dirname "$0")/_lib.sh"
undo_init "expired-certs"

cp -a /etc/kubernetes/pki "$HIDE/pki"
for f in admin.conf controller-manager.conf scheduler.conf kubelet.conf super-admin.conf; do
  [[ -f /etc/kubernetes/$f ]] && cp -a "/etc/kubernetes/$f" "$HIDE/"
done

now="$(date -u +%FT%TZ)"
timedatectl set-ntp false
date -s "$(date -u -d "$now - 400 days" +%FT%TZ)" >/dev/null
kubeadm certs renew all >/dev/null
date -s "$now" >/dev/null
timedatectl set-ntp true

restart_static_pods
# Restart kubelet so it picks up the (now expired) kubelet.conf client cert.
systemctl restart kubelet

undo_add 'cp -a '"$HIDE"'/pki/. /etc/kubernetes/pki/'
undo_add 'cp -a '"$HIDE"'/*.conf /etc/kubernetes/'
undo_add 'cp /etc/kubernetes/admin.conf /root/.kube/config; cp /etc/kubernetes/admin.conf /home/vagrant/.kube/config; cp /etc/kubernetes/admin.conf /vagrant/.cluster/admin.conf'
undo_add 'for p in kube-apiserver kube-controller-manager kube-scheduler etcd; do crictl pods --name $p -q | xargs -r crictl rmp -f; done'
undo_add 'systemctl restart kubelet'
