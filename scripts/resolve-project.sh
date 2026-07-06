#!/usr/bin/env bash
# Resolve a Shaping Project from a number OR a Notion URL/id to its folder path.
#
# Usage:
#   resolve-project.sh 7                       # by number -> "007 ..." folder
#   resolve-project.sh https://notion.so/...   # by Notion URL (matches notion_docs[].id)
#   resolve-project.sh 3142ac5cb235...         # by raw Notion page id
#
# Prints the absolute folder path on stdout (exit 0).
# On no/ambiguous match, prints a message to stderr (exit 1).
# Searches active projects first, then _archived/. If the resolved folder is
# archived, a line "ARCHIVED" is printed to stderr (still exit 0) so callers can warn.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="$ROOT_DIR/Shaping Projects"
ARCHIVE_DIR="$PROJECTS_DIR/_archived"

[[ $# -ge 1 ]] || { echo "usage: resolve-project.sh <number|notion-url|notion-id>" >&2; exit 2; }
arg="$1"

emit() { # $1 = folder path
  case "$1" in "$ARCHIVE_DIR"/*) echo "ARCHIVED" >&2 ;; esac
  printf '%s\n' "$1"; exit 0
}

if [[ "$arg" =~ ^[0-9]+$ ]]; then
  # ── By number ──
  padded="$(printf '%03d' "$arg")"
  for base in "$PROJECTS_DIR" "$ARCHIVE_DIR"; do
    [[ -d "$base" ]] || continue
    for d in "$base"/"$padded"*/; do
      [[ -d "$d" ]] && emit "${d%/}"
    done
  done
  echo "No project found for number $padded" >&2; exit 1
fi

# ── By Notion URL / id ──
base="${arg%%\?*}"          # strip query string (?v=... is also 32-hex, must drop it)
compact="${base//-/}"       # drop dashes from dashed uuids
id="$(printf '%s' "$compact" | grep -oiE '[0-9a-f]{32}' | tail -1 || true)"
[[ -n "$id" ]] || { echo "Could not extract a Notion id from: $arg" >&2; exit 1; }
id="$(printf '%s' "$id" | tr 'A-Z' 'a-z')"

while IFS= read -r -d '' pj; do
  ids="$(jq -r '(.notion_docs // [])[] | (.id // .url) // empty' "$pj" 2>/dev/null || true)"
  while IFS= read -r cand; do
    [[ -n "$cand" ]] || continue
    cand_id="$(printf '%s' "${cand//-/}" | grep -oiE '[0-9a-f]{32}' | tail -1 | tr 'A-Z' 'a-z' || true)"
    if [[ "$cand_id" == "$id" ]]; then emit "$(dirname "$pj")"; fi
  done <<< "$ids"
done < <(find "$PROJECTS_DIR" -name project.json -print0 2>/dev/null)

echo "No project references Notion id $id" >&2; exit 1
