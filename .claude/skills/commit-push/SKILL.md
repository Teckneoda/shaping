---
name: commit-push
description: Commit the current changes in the shaping repo and push to GitHub, using this repo's conventions (GPG signing OFF). Use when the user says "commit and push", "sync to GitHub", "push my changes". Args: an optional commit message (otherwise one is derived from the diff).
disable-model-invocation: true
---

# Commit & push

Sync working-tree changes in `/Users/cpies/code/shaping` up to GitHub.

> **Why `disable-model-invocation: true`:** committing and pushing are high-risk, outward-facing side effects. This skill is only ever run when the user explicitly invokes it (`/commit-push`). Other skills do **not** invoke this skill to get their work synced — they call the underlying script `scripts/git-commit-push.sh` directly, so the gate here can't be bypassed by loose description-matching.

## 1. Inspect first

```
cd "/Users/cpies/code/shaping"
git status
git diff --stat
```
- If there's **nothing to commit**, say so and stop.
- Note the current branch. If it's not `main`, mention it — the user may want a branch/PR instead. Proceed on the current branch unless told otherwise.

## 2. Decide the message (the only judgment step)

- Use the message the caller passed. Otherwise derive a concise, specific summary from the diff (imperative mood, e.g. "Archive shaping projects 008 and 009"). Don't invent scope the diff doesn't show.

## 3. Commit & push via the script

The mechanics are deterministic and live in a script — GPG-off commit, the required co-author trailer, and the push. Do not hand-run `git commit`/`git push`:

```
scripts/git-commit-push.sh -m "<message>"                 # git add -A, commit, push
scripts/git-commit-push.sh -m "<message>" -- <paths...>   # focused commit (stage only these)
scripts/git-commit-push.sh -m "<message>" --no-push       # commit only
```

The script prints tab-separated result lines: `COMMITTED\t<hash>\t<branch>\t<msg>` then `PUSHED\t<branch>`.
Exit codes to handle:
- `3` — nothing staged → report "nothing to commit".
- `4` — **push rejected** (remote ahead, no upstream, protected branch). **STOP and report** the exact error the script emitted and the options (pull/rebase, `--set-upstream`, open a PR). The script never force-pushes.

## 4. Report
Confirm the commit hash + message and that the push succeeded (or exactly why it didn't).

## Notes
- Only commit/push when the user has asked for it — don't auto-sync unrelated work.
- The `-c commit.gpgsign=false` flag and co-author trailer are baked into the script (hard requirements), so they can't be forgotten.
