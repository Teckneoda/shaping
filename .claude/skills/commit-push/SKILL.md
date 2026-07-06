---
name: commit-push
description: Commit the current changes in the shaping repo and push to GitHub, using this repo's conventions (GPG signing OFF). Use when the user says "commit and push", "sync to GitHub", "push my changes", or when another skill needs to sync its file changes to the remote. Args: an optional commit message (otherwise one is derived from the diff).
---

# Commit & push

Sync working-tree changes in `/Users/cpies/code/shaping` up to GitHub. Other skills (e.g. `archive-projects`) invoke this as their final sync step.

## 1. Inspect first

```
cd "/Users/cpies/code/shaping"
git status
git diff --stat
```
- If there's **nothing to commit**, say so and stop.
- Note the current branch. If it's not `main`, mention it — the user may want a branch/PR instead (see CLAUDE.md/harness git guidance). Proceed on the current branch unless told otherwise.

## 2. Stage the right changes

- Default: `git add -A` to capture all changes (including file moves/renames as renames).
- If the caller wants a **focused** commit (e.g. only the archived folders), stage just those paths instead (e.g. `git add "Shaping Projects/"`) and report anything left unstaged.

## 3. Commit

```
git -c commit.gpgsign=false commit -m "<message>"
```
- **Always** pass `-c commit.gpgsign=false` — GPG signing is off in this repo (hard requirement).
- Use the message the caller passed. Otherwise derive a concise, specific summary from the diff (imperative mood, e.g. "Archive shaping projects 008 and 009"). Don't invent scope the diff doesn't show.
- Append the co-author trailer required by the harness:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  ```

## 4. Push

```
git push
```
- If push is rejected (remote ahead, no upstream, protected branch), **STOP and report** the exact error and options (pull/rebase, `--set-upstream`, open a PR). Do **not** force-push.

## 5. Report
Confirm the commit hash + message and that the push succeeded (or exactly why it didn't).

## Notes
- Only commit/push when the user (or an invoking skill acting on the user's request) has asked for it — don't auto-sync unrelated work.
