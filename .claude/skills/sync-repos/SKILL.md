---
name: sync-repos
description: Pull the latest default branch for every repo under Research Repos (including the Legacy subdir). Use when the user says "pull latest main on all Research Repos", "sync the repos", or "update the research repos". Stops and reports any repo that is dirty or on a non-main branch instead of forcing.
---

# Sync Research Repos

Pull latest for all local research checkouts.

## Roots
- `/Users/cpies/code/shaping/Research Repos/`
- `/Users/cpies/code/shaping/Research Repos/Legacy/` (nested)

Iterate every immediate subdirectory that contains a `.git`. Skip non-git dirs.

## Per repo
1. Detect the default branch (may be `main` or `master`): `git -C "$repo" symbolic-ref refs/remotes/origin/HEAD` or fall back to checking which exists.
2. Check `git status`.
3. If clean **and** on the default branch: `git pull origin <default>`.
4. **If dirty or on a non-main/master branch: DO NOT pull.** Collect it for the report.

## Report
Summarize: which repos pulled cleanly (with new-commit counts if useful), and which were **skipped** and why (dirty tree / on branch `X`). For skipped repos, tell the user their options (stash, commit, switch branch) — do not auto-resolve.

## Notes
- Use `-c commit.gpgsign=false` for any commit in this repo tree (user preference). Not needed for pulls.
- This is the same sync procedure `shape` uses in its step 3; `shape` may invoke this skill.
