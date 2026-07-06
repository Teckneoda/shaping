---
name: archive-projects
description: Clean up old/finished Shaping Projects by moving them into `Shaping Projects/_archived/`, then commit and push. Surfaces each active project with context (status, last activity) so the user can decide, prompts which to archive, archives the chosen ones, and syncs to GitHub. Use when the user says "clean up old shaping projects", "archive old projects", "archive finished projects", or "clean up the shaping projects". Args: optional project number(s) to archive directly.
---

# Archive (clean up) Shaping Projects

Move finished/stale projects out of the active `Shaping Projects/` list into `Shaping Projects/_archived/`, then sync to GitHub. Archiving is exactly what `scripts/project-manager.sh archive` does: **move the whole `NNN <Project Name>` folder into `_archived/`, preserving its full name** (so its sequence number is never reused — `next_project_number` scans `_archived/` too).

## 1. Gather active projects with context

List active projects (immediate subdirs of `Shaping Projects/`, excluding `_archived`):
```
ls -d "/Users/cpies/code/shaping/Shaping Projects"/*/ | grep -v '_archived'
```
For each, gather signal so the user can judge what's "old" — do this in one batched pass:
- **Last activity**: most recent commit touching the folder —
  `git -C "/Users/cpies/code/shaping" log -1 --format='%ad' --date=short -- "Shaping Projects/<folder>"`
- **Status hint**: the first non-empty content lines of `planning-state.md` (e.g. "Identified So Far" filled in vs. "No research completed yet"), which suggests whether it shipped, stalled, or never started.

## 2. Prompt which to archive

Present a compact numbered list — folder name, last-activity date, and a one-line status hint per project — then ask the user which to archive. They can reply with numbers, folder names, or "none".

- If the user already named project number(s) in their request (e.g. "archive 8 and 9"), skip the prompt and confirm those instead.
- If there are **4 or fewer** clear candidates and you want a click-through, `AskUserQuestion` (multiSelect) works; with more than 4 active projects use the plain numbered-list prompt (the question widget caps at 4 options).
- Do **not** archive anything until the user confirms the specific set.

## 3. Archive each chosen project

Resolve each selection to its folder (match by leading zero-padded number, e.g. `008`). For each confirmed project, move it preserving the folder name:
```
mkdir -p "/Users/cpies/code/shaping/Shaping Projects/_archived"
mv "/Users/cpies/code/shaping/Shaping Projects/<NNN Name>" "/Users/cpies/code/shaping/Shaping Projects/_archived/<NNN Name>"
```
This mirrors `cmd_archive` in [`scripts/project-manager.sh`](../../scripts/project-manager.sh). Quote paths — folder names contain spaces. Do not rename or renumber.

(If several projects need archiving, doing the `mv` directly is faster than the script's one-at-a-time interactive menu and produces the identical result. If you'd rather drive the interactive picker, run `scripts/project-manager.sh archive` once per project so the user selects in their terminal.)

## 4. Commit and push to GitHub

Invoke the **`commit-push`** skill to sync the archive moves up to the remote. Pass a message listing the archived project(s), e.g. `Archive shaping project(s): 008 Category Feature Flagging, 009 Category Manager`. `commit-push` handles the repo conventions (stages the moves as renames, commits with GPG signing off, pushes, and stops/reports if the push is rejected).

## 5. Report

Confirm what moved (`<NNN Name>` → `_archived/`), what was left active, and the pushed commit (hash + message, from `commit-push`). Note that archived numbers stay reserved.

## Related
- `commit-push` — the final GitHub-sync step (step 4).
- `scripts/project-manager.sh archive` — the canonical single-project interactive archive; this skill batches the same operation.
- `shape` — the reverse workflow (starting/researching a project).
