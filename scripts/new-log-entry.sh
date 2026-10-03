#!/usr/bin/env bash
# Create the next numbered log entry from the template and open it in $EDITOR.
#   scripts/new-log-entry.sh            (uses the active chaos id if one exists)
#   scripts/new-log-entry.sh my-slug
set -euo pipefail
cd "$(dirname "$0")/.."
n=$(ls logs/entries/[0-9]*.md 2>/dev/null | wc -l)
num=$(printf '%03d' $((n+1)))
slug="${1:-}"
if [[ -z "$slug" && -f .chaos/current ]]; then slug="$(cut -d' ' -f1 .chaos/current)"; fi
slug="${slug:-untitled}"
f="logs/entries/${num}-${slug}.md"
sed "s/{{NUM}}/$num/; s/{{DATE}}/$(date -u +%F)/" logs/entries/TEMPLATE.md > "$f"
echo "Created $f  (add a row to logs/LOG.md when done)"
[[ -n "${EDITOR:-}" ]] && exec "$EDITOR" "$f" || true
