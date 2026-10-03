#!/usr/bin/env bash
# Take an etcd snapshot using the kubeadm-generated certs. Keeps the last 24.
set -euo pipefail
DIR=/var/lib/etcd-backup
mkdir -p "$DIR"
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save "$DIR/etcd-$(date +%Y%m%d-%H%M%S).db"
ls -1t "$DIR"/etcd-*.db | tail -n +25 | xargs -r rm -f
