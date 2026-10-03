#!/usr/bin/env bash
# FAILURE: exhausted node (worker). One random variant:
#   burn      - a transient systemd unit with an innocent name eats CPU and RAM
#               outside Kubernetes' view (node slow, MemoryPressure, kubelet lagging)
#   requests  - a deployment pinned to this node books all allocatable CPU
#               (node healthy, everything else Pending)
source "$(dirname "$0")/_lib.sh"
variant="${VARIANT:-$(pick burn requests)}"
undo_init "exhaust-node ($variant)"
node="$(hostname)"

case "$variant" in
  burn)
    systemd-run --unit=fscache-warm --quiet \
      stress-ng --cpu "$(nproc)" --vm 1 --vm-bytes 75% --vm-keep --timeout 0
    undo_add 'systemctl stop fscache-warm.service || true' ;;
  requests)
    alloc_m=$(kubectl get node "$node" -o jsonpath='{.status.allocatable.cpu}' | sed 's/m$//')
    [[ "$alloc_m" =~ ^[0-9]+$ ]] && [[ ${#alloc_m} -le 2 ]] && alloc_m=$((alloc_m*1000))
    replicas=$(( alloc_m / 200 ))
    kubectl -n kube-system create deploy metrics-shim --image=registry.k8s.io/pause:3.10 --replicas=0 >/dev/null
    kubectl -n kube-system patch deploy metrics-shim -p \
      "{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$node\"},\"tolerations\":[{\"operator\":\"Exists\"}],\"containers\":[{\"name\":\"pause\",\"image\":\"registry.k8s.io/pause:3.10\",\"resources\":{\"requests\":{\"cpu\":\"200m\"}}}]}}}}" >/dev/null
    kubectl -n kube-system scale deploy metrics-shim --replicas="$replicas" >/dev/null
    undo_add 'export KUBECONFIG=/etc/kubernetes/admin.conf; [[ -f $KUBECONFIG ]] || export KUBECONFIG=/vagrant/.cluster/admin.conf'
    undo_add 'kubectl -n kube-system delete deploy metrics-shim --ignore-not-found' ;;
esac
