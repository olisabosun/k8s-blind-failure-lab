#!/usr/bin/env bash
# Inject one named failure at random into the running cluster, from the HOST.
# The failure type and target node are sealed in .chaos/ until you run reveal.sh.
#
#   chaos/inject.sh                 random failure, random eligible node
#   chaos/inject.sh --only break-dns
#   chaos/inject.sh --seed 42       reproducible pick
#   chaos/inject.sh --list
set -euo pipefail
cd "$(dirname "$0")/.."

FAILURES=(expired-certs corrupt-etcd delete-cni full-disk bad-kubelet-config break-dns exhaust-node)
# Where each failure may land. cp-only ones touch the control plane itself.
declare -A TARGETS=(
  [expired-certs]="cp"
  [corrupt-etcd]="cp"
  [break-dns]="cp"
  [delete-cni]="w1 w2"
  [full-disk]="w1 w2"
  [exhaust-node]="w1 w2"
  [bad-kubelet-config]="cp w1 w2"
)

only=""; seed=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) printf '%s\n' "${FAILURES[@]}"; exit 0 ;;
    --only) only="$2"; shift 2 ;;
    --seed) seed="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -f .chaos/current ]]; then
  echo "A failure is already active ($(cut -d' ' -f1 .chaos/current)). Run chaos/reveal.sh first." >&2
  exit 1
fi

[[ -n "$seed" ]] && RANDOM=$seed
if [[ -n "$only" ]]; then
  failure="$only"
  [[ -n "${TARGETS[$failure]:-}" ]] || { echo "unknown failure: $only (see --list)" >&2; exit 2; }
else
  failure="${FAILURES[RANDOM % ${#FAILURES[@]}]}"
fi
read -ra eligible <<< "${TARGETS[$failure]}"
target="${eligible[RANDOM % ${#eligible[@]}]}"

id="$(date +%Y%m%d-%H%M%S)"
mkdir -p .chaos
started="$(date -u +%FT%TZ)"

# Run the failure script on the target as root. Output is captured, not shown:
# the injection log is a spoiler.
if ! vagrant ssh "$target" -c "sudo CHAOS_ID=$id bash /vagrant/chaos/failures/${failure}.sh" \
     > ".chaos/${id}.inject.log" 2>&1; then
  echo "Injection failed. See .chaos/${id}.inject.log" >&2
  exit 1
fi

# Sealed answer: base64 so a stray `cat` does not spoil it.
printf 'failure=%s\ntarget=%s\nstarted=%s\nundo=/vagrant/.chaos/undo-%s.sh\n' \
  "$failure" "$target" "$started" "$id" | base64 -w0 > ".chaos/${id}.answer"
echo "$id $started" > .chaos/current

cat <<MSG

Failure injected. id=${id}  started=${started}
Something in the cluster is now broken. You do not know what, or where.

  1. Start from the symptom:  kubectl get nodes; kubectl get pods -A   (and see docs/triage-checklist.md)
  2. Work the problem. Write as you go: scripts/new-log-entry.sh
  3. When you have a root cause written down and the fix applied:  chaos/reveal.sh

MSG
