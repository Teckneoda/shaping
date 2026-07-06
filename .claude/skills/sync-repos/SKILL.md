---
name: sync-repos
description: Pull the latest default branch for every repo under Research Repos (including the Legacy subdir). Use when the user says "pull latest main on all Research Repos", "sync the repos", or "update the research repos". Stops and reports any repo that is dirty or on a non-main branch instead of forcing.
---

# Sync Research Repos

Pulling latest is a **fully deterministic** operation — detect the default branch, check for a dirty tree / wrong branch, fast-forward if clean. There is no judgment to make per repo, so it lives in a script; your job is only to run it and report the result.

## Run it

```
scripts/sync-repos.sh              # all repos under Research Repos/ and Research Repos/Legacy/
scripts/sync-repos.sh <name> ...   # only the named repo folder(s)
```

Each line is tab-separated `<status>\t<repo>\t<detail>`, where status is:
- `PULLED` — fast-forwarded (detail = new-commit count)
- `UPTODATE` — already current
- `SKIPPED` — **dirty tree** or **on a non-default branch** (not touched)
- `ERROR` — no origin default branch, or the pull failed

## Report

Summarize which repos pulled cleanly and which were `SKIPPED`/`ERROR` and why. For skipped repos, give the user their options (stash, commit, switch branch) — **do not auto-resolve**. The script never forces, so nothing is lost by reporting and stopping.

## Notes
- The script is the same sync step `shape` uses (its step 3) — `shape` runs this exact script.
- It fast-forwards only (`--ff-only`); it never merges or rebases.
- Commits in this repo tree use `-c commit.gpgsign=false` (see `commit-push`), but pulls need no signing.
