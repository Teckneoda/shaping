#!/usr/bin/env bash
# List active Shaping Projects with the signal needed to judge what is "old".
# Tab-separated columns: <num>\t<folder>\t<last-activity date>\t<status hint>
#
# Usage:
#   list-projects.sh            # active projects only
#   list-projects.sh --all      # include _archived/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="$ROOT_DIR/Shaping Projects"

include_archived=0
[[ "${1:-}" == "--all" ]] && include_archived=1

for d in "$PROJECTS_DIR"/*/; do
  folder="$(basename "${d%/}")"
  [[ "$folder" == "_archived" ]] && continue
  num="$(printf '%s' "$folder" | grep -oE '^[0-9]+' || echo '?')"

  # Last commit touching this folder (falls back to '-' if untracked).
  last="$(git -C "$ROOT_DIR" log -1 --format='%ad' --date=short -- "Shaping Projects/$folder" 2>/dev/null || true)"
  [[ -n "$last" ]] || last='-'

  # Status hint: first non-empty, non-heading content line of planning-state.md.
  ps="$d/planning-state.md"
  hint='(no planning-state.md)'
  if [[ -f "$ps" ]]; then
    line="$(grep -vE '^\s*(#|$)' "$ps" 2>/dev/null | head -1 || true)"
    [[ -n "$line" ]] && hint="${line:0:80}"
  fi

  printf '%s\t%s\t%s\t%s\n' "$num" "$folder" "$last" "$hint"
done | sort -n

if [[ "$include_archived" -eq 1 && -d "$PROJECTS_DIR/_archived" ]]; then
  for d in "$PROJECTS_DIR/_archived"/*/; do
    [[ -d "$d" ]] || continue
    folder="$(basename "${d%/}")"
    num="$(printf '%s' "$folder" | grep -oE '^[0-9]+' || echo '?')"
    printf '%s\t%s\t%s\t%s\n' "$num" "$folder" "archived" "(archived)"
  done | sort -n
fi
