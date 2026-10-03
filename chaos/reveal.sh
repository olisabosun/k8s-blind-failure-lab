#!/usr/bin/env bash
# Unseal the active failure, show elapsed time and the undo script.
# Rule: run this only AFTER a root-cause hypothesis is written in your log.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f .chaos/current ]] || { echo "No active failure. Run chaos/inject.sh first." >&2; exit 1; }
read -r id started < .chaos/current
ended="$(date -u +%FT%TZ)"
elapsed=$(( $(date -d "$ended" +%s) - $(date -d "$started" +%s) ))

echo "=== Sealed answer for $id ==="
base64 -d ".chaos/${id}.answer"
echo "ended=${ended}"
printf 'elapsed=%dm %ds\n' $((elapsed/60)) $((elapsed%60))
echo
echo "Undo script (only if you could not recover it yourself; note that in the log):"
echo "  vagrant ssh <target> -c 'sudo bash /vagrant/.chaos/undo-${id}.sh'"
echo
echo "Now finish the log entry: symptom, what you checked, root cause, fix, time taken."
mv .chaos/current ".chaos/${id}.done"
