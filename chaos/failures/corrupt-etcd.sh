#!/usr/bin/env bash
# FAILURE: corrupted etcd data (control plane).
# Guarantees a usable snapshot exists in /var/lib/etcd-backup (cron would have
# made one anyway), stops etcd, overwrites part of the bbolt db, starts etcd.
# Symptom: API server flapping / "etcdserver: ... " / connection refused on 6443.
source "$(dirname "$0")/_lib.sh"
undo_init "corrupt-etcd"

ls /var/lib/etcd-backup/etcd-*.db >/dev/null 2>&1 || /usr/local/sbin/etcd-snapshot

mv /etc/kubernetes/manifests/etcd.yaml "$HIDE/etcd.yaml"
for _ in $(seq 1 30); do crictl pods --name etcd -q | grep -q . || break; sleep 2; done
cp -a /var/lib/etcd "$HIDE/etcd-data"

# Clobber 2 MiB in the middle of the db file. Keep the header so etcd tries to
# open it and fails in an interesting way rather than refusing outright.
dd if=/dev/urandom of=/var/lib/etcd/member/snap/db bs=1M count=2 seek=1 conv=notrunc status=none
rm -f /var/lib/etcd/member/wal/*.wal.tmp 2>/dev/null || true

mv "$HIDE/etcd.yaml" /etc/kubernetes/manifests/etcd.yaml

undo_add 'mv /etc/kubernetes/manifests/etcd.yaml /tmp/etcd.yaml.undo; sleep 10'
undo_add 'rm -rf /var/lib/etcd && cp -a '"$HIDE"'/etcd-data /var/lib/etcd'
undo_add 'mv /tmp/etcd.yaml.undo /etc/kubernetes/manifests/etcd.yaml'
