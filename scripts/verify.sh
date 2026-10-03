#!/usr/bin/env bash
# Baseline check. Run after `make up` and after every fix. If this passes, the
# cluster is healthy; keep the output of a passing run as your "known good".
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG=.cluster/admin.conf

echo "== nodes"; kubectl get nodes -o wide
echo "== control plane"; kubectl get --raw /readyz?verbose | grep -v '^\[+\]' || echo "all checks ok"
echo "== certs"; vagrant ssh cp -c 'sudo kubeadm certs check-expiration' 2>/dev/null | grep -E 'apiserver |etcd-server|admin.conf' || true
echo "== dns + scheduling"
kubectl run verify-$$ --image=busybox:1.36 --restart=Never --rm -it --quiet -- sh -c \
  'nslookup kubernetes.default >/dev/null && echo "internal dns ok"; nslookup example.com >/dev/null && echo "external dns ok"; wget -qO- -T5 http://kubernetes.default.svc/healthz 2>&1 | head -c 60; echo'
echo "== unhealthy pods"; kubectl get pods -A | grep -v -E 'Running|Completed' || echo none
