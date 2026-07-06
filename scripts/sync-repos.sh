#!/usr/bin/env bash
# Pull latest default branch for every git checkout under Research Repos/ and
# Research Repos/Legacy/. Never forces: dirty trees or non-default branches are
# skipped and reported. Deterministic — no model judgment required.
#
# Usage:
#   sync-repos.sh                 # sync all repos
#   sync-repos.sh <name> [<name>] # sync only the named repo folder(s)
#
# Output (tab-separated) per repo:  <status>\t<repo>\t<detail>
#   status ∈ PULLED | UPTODATE | SKIPPED | ERROR
# Exit 0 always (a skip/error is data, not a script failure); the caller reports.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
RR="$ROOT_DIR/Research Repos"

wanted=("$@")

want() { # $1 = folder name; true if no filter or name matches filter
  [[ ${#wanted[@]} -eq 0 ]] && return 0
  local n; for n in "${wanted[@]}"; do [[ "$n" == "$1" ]] && return 0; done
  return 1
}

default_branch() {
  local repo="$1" def
  def="$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)"
  if [[ -z "$def" ]]; then
    local b
    for b in main master; do
      git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$b" && { def="$b"; break; }
    done
  fi
  printf '%s' "$def"
}

sync_one() {
  local repo="$1" name; name="$(basename "$repo")"
  [[ -d "$repo/.git" ]] || return 0
  want "$name" || return 0

  local def cur dirty before after
  def="$(default_branch "$repo")"
  [[ -n "$def" ]] || { printf 'ERROR\t%s\t%s\n' "$name" "no origin default branch"; return 0; }
  cur="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  dirty="$(git -C "$repo" status --porcelain 2>/dev/null || true)"

  if [[ -n "$dirty" ]]; then printf 'SKIPPED\t%s\tdirty working tree\n' "$name"; return 0; fi
  if [[ "$cur" != "$def" ]]; then printf 'SKIPPED\t%s\ton branch %s (default %s)\n' "$name" "$cur" "$def"; return 0; fi

  before="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo '')"
  if git -C "$repo" pull --ff-only origin "$def" >/dev/null 2>&1; then
    after="$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo '')"
    if [[ "$before" == "$after" ]]; then printf 'UPTODATE\t%s\t%s\n' "$name" "$def"
    else
      local n; n="$(git -C "$repo" rev-list --count "$before..$after" 2>/dev/null || echo '?')"
      printf 'PULLED\t%s\t%s new commit(s) on %s\n' "$name" "$n" "$def"
    fi
  else
    printf 'ERROR\t%s\tpull failed (see git output)\n' "$name"
  fi
}

for repo in "$RR"/*/; do
  [[ -d "$repo" ]] || continue
  [[ "$(basename "$repo")" == "Legacy" ]] && continue
  sync_one "${repo%/}"
done
for repo in "$RR/Legacy"/*/; do
  [[ -d "$repo" ]] || continue
  sync_one "${repo%/}"
done
