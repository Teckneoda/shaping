#!/usr/bin/env bash
# Extract the real user-typed prompts from recent Claude Code session transcripts,
# so a skill can cluster them into recurring tasks. Read-only.
#
# Output: tab-separated, one prompt per line:
#   <date>\t<project-dir>\t<session-id>\t<prompt first line, truncated>
# Newest first. System/tool/harness noise is filtered out.
#
# Usage:
#   extract-prompts.sh                 # last 30 days, all projects
#   extract-prompts.sh --days 14       # last 14 days
#   extract-prompts.sh --limit 200     # cap at 200 most-recent prompts
#   extract-prompts.sh --project shaping   # only transcripts whose dir contains "shaping"
set -euo pipefail

PROJECTS_ROOT="$HOME/.claude/projects"
days=30
limit=400
proj_filter=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)    days="$2"; shift 2 ;;
    --limit)   limit="$2"; shift 2 ;;
    --project) proj_filter="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -d "$PROJECTS_ROOT" ]] || { echo "no transcripts dir: $PROJECTS_ROOT" >&2; exit 1; }

# cutoff epoch (portable: try GNU date, fall back to BSD date)
if cutoff=$(date -d "-${days} days" +%s 2>/dev/null); then :;
else cutoff=$(date -v-"${days}"d +%s); fi

# newest transcripts first, optionally filtered by project dir name
files=$(find "$PROJECTS_ROOT" -name '*.jsonl' -type f 2>/dev/null \
  | { [[ -n "$proj_filter" ]] && grep -i "$proj_filter" || cat; } \
  | while read -r f; do printf '%s\t%s\n' "$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f")" "$f"; done \
  | sort -rn | cut -f2-)

for f in $files; do
  # skip whole file if it hasn't been touched inside the window
  mtime=$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f")
  [[ "$mtime" -lt "$cutoff" ]] && continue
  proj=$(basename "$(dirname "$f")")
  sid=$(basename "$f" .jsonl)

  jq -r --arg proj "$proj" --arg sid "$sid" '
    select(.type=="user")
    | (if (.message.content|type=="string")
        then .message.content
        else ([.message.content[]? | select(.type=="text") | .text] | join(" "))
       end) as $txt
    | select($txt != null and ($txt|length) > 0)
    | [ (.timestamp // "" | .[0:10]), $proj, $sid, ($txt | gsub("\n";" ") | .[0:300]) ]
    | @tsv
  ' "$f" 2>/dev/null
done \
| grep -vE $'\t''(<|Shell cwd was reset|Caveat:|\[Request interrupted|Base directory for this skill|<command-|<local-command)' \
| grep -vE $'\t''$' \
| head -n "$limit"
