#!/usr/bin/env bash
# Deterministic commit + push for the shaping repo, encoding its conventions:
#   - GPG signing OFF (hard requirement: -c commit.gpgsign=false)
#   - required Claude co-author trailer
# The commit MESSAGE is the only judgment part — the caller (a skill/AI) supplies it.
#
# Usage:
#   git-commit-push.sh -m "message"                 # git add -A, commit, push
#   git-commit-push.sh -m "message" --no-push       # commit only
#   git-commit-push.sh -m "message" -- path1 path2  # stage only these paths
#
# Exits non-zero (and prints to stderr) if there is nothing to commit or if the
# push is rejected — the caller must STOP and report, never force.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TRAILER="Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"

msg=""; do_push=1; paths=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) msg="$2"; shift 2 ;;
    --no-push) do_push=0; shift ;;
    --) shift; paths=("$@"); break ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$msg" ]] || { echo "git-commit-push.sh: -m <message> is required" >&2; exit 2; }

cd "$ROOT_DIR"

if [[ ${#paths[@]} -gt 0 ]]; then git add -- "${paths[@]}"; else git add -A; fi

if git diff --cached --quiet; then
  echo "Nothing staged to commit." >&2; exit 3
fi

git -c commit.gpgsign=false commit -m "$msg" -m "$TRAILER" >/dev/null
hash="$(git rev-parse --short HEAD)"
branch="$(git rev-parse --abbrev-ref HEAD)"
echo "COMMITTED	$hash	$branch	$msg"

[[ "$do_push" -eq 1 ]] || { echo "SKIPPED_PUSH	--no-push"; exit 0; }

if git push 2>push.err; then
  echo "PUSHED	$branch"
  rm -f push.err
else
  echo "PUSH_FAILED	$branch	$(tr '\n' ' ' < push.err)" >&2
  rm -f push.err
  exit 4
fi
