# Shared helpers for failure scripts. Sourced, not executed. Runs as root on the target.
set -euo pipefail
: "${CHAOS_ID:=manual-$(date +%s)}"
HIDE=/root/.chaos/${CHAOS_ID}            # backups of whatever we break
UNDO=/vagrant/.chaos/undo-${CHAOS_ID}.sh # restore script, revealed later
mkdir -p "$HIDE" /vagrant/.chaos
export KUBECONFIG=/etc/kubernetes/admin.conf
[[ -f $KUBECONFIG ]] || export KUBECONFIG=/vagrant/.cluster/admin.conf

undo_init() {  # $1 = description
  { echo '#!/usr/bin/env bash'; echo 'set -euxo pipefail'; echo "# undo: $1 on $(hostname)"; } > "$UNDO"
  chmod 700 "$UNDO"
}
undo_add() { echo "$*" >> "$UNDO"; }

pick() {  # pick a random word from args
  local a=("$@"); echo "${a[RANDOM % ${#a[@]}]}"
}

restart_static_pods() {
  # Force kubelet to recreate control-plane static pods (certs/config changed on disk).
  for p in kube-apiserver kube-controller-manager kube-scheduler etcd; do
    crictl pods --name "$p" -q | xargs -r crictl rmp -f >/dev/null 2>&1 || true
  done
}
