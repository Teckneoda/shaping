---
name: archive-projects
description: Clean up old/finished Shaping Projects by moving them into `Shaping Projects/_archived/`, then commit and push. Surfaces each active project with context (status, last activity) so the user can decide, prompts which to archive, archives the chosen ones, and syncs to GitHub. Use when the user says "clean up old shaping projects", "archive old projects", "archive finished projects", or "clean up the shaping projects". Args: optional project number(s) to archive directly.
---

# Archive (clean up) Shaping Projects

Move finished/stale projects out of the active `Shaping Projects/` list into `Shaping Projects/_archived/`, then sync to GitHub. Archiving is exactly what `scripts/project-manager.sh archive` does: **move the whole `NNN <Project Name>` folder into `_archived/`, preserving its full name** (so its sequence number is never reused — `next_project_number` scans `_archived/` too).

## 1. Gather active projects with context

Gathering the candidate list is deterministic — run the shared script instead of hand-rolling `ls` + `git log` + `head`:
```
scripts/list-projects.sh
```
It prints one tab-separated row per active project: `<num>\t<folder>\t<last-activity date>\t<status hint>` (status hint = first content line of `planning-state.md`). Your judgment is only *which* of these are "old" enough to archive — the data-gathering is the script's job.

## 2. Prompt which to archive

Present a compact numbered list — folder name, last-activity date, and a one-line status hint per project — then ask the user which to archive. They can reply with numbers, folder names, or "none".

- If the user already named project number(s) in their request (e.g. "archive 8 and 9"), skip the prompt and confirm those instead.
- If there are **4 or fewer** clear candidates and you want a click-through, `AskUserQuestion` (multiSelect) works; with more than 4 active projects use the plain numbered-list prompt (the question widget caps at 4 options).
- Do **not** archive anything until the user confirms the specific set.

## 3. Archive each chosen project

Resolve each selection to its folder with the shared script (`scripts/resolve-project.sh <number>` → prints the folder path; it also warns `ARCHIVED` on stderr if it's already archived). For each confirmed project, move it preserving the folder name:
```
mkdir -p "/Users/cpies/code/shaping/Shaping Projects/_archived"
mv "/Users/cpies/code/shaping/Shaping Projects/<NNN Name>" "/Users/cpies/code/shaping/Shaping Projects/_archived/<NNN Name>"
```
This mirrors `cmd_archive` in [`scripts/project-manager.sh`](../../scripts/project-manager.sh). Quote paths — folder names contain spaces. Do not rename or renumber.

(If several projects need archiving, doing the `mv` directly is faster than the script's one-at-a-time interactive menu and produces the identical result. If you'd rather drive the interactive picker, run `scripts/project-manager.sh archive` once per project so the user selects in their terminal.)

## 4. Commit and push to GitHub

Sync the archive moves up to the remote with the **shared commit script** (the same one `commit-push` wraps — so conventions live in one place, and this skill doesn't depend on the model re-invoking the gated `commit-push` skill):
```
scripts/git-commit-push.sh -m "Archive shaping project(s): 008 Category Feature Flagging, 009 Category Manager"
```
It stages moves as renames (`git add -A`), commits with GPG signing off + the co-author trailer, and pushes. If it exits `4` (**push rejected**), STOP and report the exact error it printed — do not force. This push is safe to run here because it happens only *after* the user confirmed the specific set in step 2.

## 5. Report

Confirm what moved (`<NNN Name>` → `_archived/`), what was left active, and the pushed commit (hash + message, from `commit-push`). Note that archived numbers stay reserved.

## Related
- `scripts/list-projects.sh` — candidate gathering (step 1).
- `scripts/resolve-project.sh` — number → folder (step 3).
- `scripts/git-commit-push.sh` — the shared commit/push primitive (step 4); `commit-push` wraps the same script for standalone use.
- `scripts/project-manager.sh archive` — the canonical single-project interactive archive; this skill batches the same operation.
- `shape` — the reverse workflow (starting/researching a project).
