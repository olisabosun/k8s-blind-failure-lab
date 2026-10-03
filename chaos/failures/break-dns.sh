#!/usr/bin/env bash
# FAILURE: broken cluster DNS (applied from cp, affects everyone). One random variant:
#   forward  - Corefile forwards external queries to a blackhole (internal OK, external dead)
#   zone     - Corefile serves the wrong zone (cluster.local lookups go NXDOMAIN)
#   selector - kube-dns Service selector matches nothing (endpoints empty, all DNS dead)
#   scale    - coredns scaled to zero
source "$(dirname "$0")/_lib.sh"
variant="${VARIANT:-$(pick forward zone selector scale)}"
undo_init "break-dns ($variant)"

kubectl -n kube-system get cm coredns -o json | jq 'del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp)' > "$HIDE/coredns-cm.json"
kubectl -n kube-system get svc kube-dns -o json | jq 'del(.metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp)' > "$HIDE/kube-dns-svc.json"

case "$variant" in
  forward)
    kubectl -n kube-system get cm coredns -o json \
      | jq '.data.Corefile |= sub("forward \\. /etc/resolv\\.conf"; "forward . 192.0.2.53")' \
      | kubectl apply -f - >/dev/null
    kubectl -n kube-system rollout restart deploy/coredns >/dev/null ;;
  zone)
    kubectl -n kube-system get cm coredns -o json \
      | jq '.data.Corefile |= sub("kubernetes cluster\\.local"; "kubernetes cluster.lokal")' \
      | kubectl apply -f - >/dev/null
    kubectl -n kube-system rollout restart deploy/coredns >/dev/null ;;
  selector)
    kubectl -n kube-system patch svc kube-dns -p '{"spec":{"selector":{"k8s-app":"kube-dnss"}}}' >/dev/null ;;
  scale)
    kubectl -n kube-system scale deploy/coredns --replicas=0 >/dev/null ;;
esac

undo_add 'export KUBECONFIG=/etc/kubernetes/admin.conf'
undo_add 'kubectl apply -f '"$HIDE"'/coredns-cm.json'
undo_add 'kubectl apply -f '"$HIDE"'/kube-dns-svc.json'
undo_add 'kubectl -n kube-system scale deploy/coredns --replicas=2'
undo_add 'kubectl -n kube-system rollout restart deploy/coredns'
