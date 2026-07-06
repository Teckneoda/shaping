---
name: shape
description: Run a full shaping/research pass on a numbered Shaping Project. Use when the user says "shape N", "research N", or "shape <project>" (e.g. "shape 4", "Research #3"). Reads the project docs, syncs its repos, pulls Notion context, researches the codebase, then plans with the user and updates the project's living docs.
---

# Shape a project

Trigger: **"shape N"**, **"research N"**, **"Research #N"** where N is a project number.

## 1. Resolve the project
Find the directory under `Shaping Projects/` whose name starts with the zero-padded number (e.g. `004`). If it's under `Shaping Projects/_archived/`, confirm with the user before proceeding.

## 2. Read project state
Read all four from the project directory: `project.json`, `Features.md`, `Services.md`, `planning-state.md`.

`project.json` has `repositories` (array of `{org, repo}`) and `notion_docs` (array of Notion URLs).

## 3. Sync local repos to origin/main
For each repo in `repositories` that exists locally under `/Users/cpies/code/shaping/Research Repos/` (also check the nested `Legacy/` subdir):
- `git status`, then `git pull origin <default-branch>` (detect main vs master).
- **If the pull fails, the tree is dirty, or it's on a non-main branch: STOP.** Report which repo, what branch, and what the user needs to do (stash / switch / resolve). Do not research that repo until they confirm.

The `sync-repos` skill implements this loop — you may invoke it for the sync step.

## 4. Gather Notion context
For each URL in `notion_docs`, fetch with `mcp__claude_ai_Notion__notion-fetch`. Also check `mcp__claude_ai_Notion__notion-get-comments` for open questions/comments (resolve authors via `notion-get-users`).
(Note: the actual MCP server is `claude_ai_Notion`, prefix `mcp__claude_ai_Notion__`.)

## 5. Research the repositories
For each repo: `gh repo view {org}/{repo}` for overview, then fan out with `Agent` (Explore type) to search relevant code, issues, and PRs, and read source from the local `Research Repos/` checkout. Prefer parallel Explore agents over reading whole files yourself.

## 6. Plan with the user (planning mode)
Identify features, services, APIs, data models, and migration steps. Update `Features.md` and `Services.md`. Flag unanswered questions and areas needing research. Use `AskUserQuestion` when a decision is genuinely the user's to make.

## 7. Update planning-state.md
Refresh these sections:
- **Identified So Far** — what's discovered/documented
- **Still Needs Research** — open investigation areas
- **Unanswered Questions** — numbered (Q1, Q2, …) so they can be closed via the `resolve-question` skill
- **Research Sources Consulted** — repos, docs, files reviewed

## Related
- `sync-repos` — the repo-pull step, standalone.
- `notion-sync` — push the updated docs back to Notion (step: after planning).
- `resolve-question` — answer a specific Q# later.
