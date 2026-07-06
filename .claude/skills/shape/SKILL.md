---
name: shape
description: Run a full shaping/research pass on a Shaping Project, identified by number OR by a Notion URL. Use when the user says "shape N", "research N", "shape <project>", or "shape <notion-url>" (e.g. "shape 4", "Research #3", "shape https://notion.so/..."). Resolves or creates the project, syncs its repos, pulls Notion context, researches the codebase, then plans with the user and updates the living docs.
---

# Shape a project

Trigger: **"shape N"**, **"research N"**, **"Research #N"** (project number), or **"shape <notion-url>"** (a Notion doc link).

## 1. Resolve the project

**If given a project number:** find the directory under `Shaping Projects/` whose name starts with the zero-padded number (e.g. `004`). If it's under `Shaping Projects/_archived/`, confirm with the user before proceeding. Then go to step 2.

**If given a Notion URL:** determine whether a project for it already exists.
1. Extract the Notion **page ID** from the input URL — the 32-char hex id at the end of the path (strip the title slug; it may be dashed or undashed).
2. Scan every `Shaping Projects/**/project.json` (include `_archived/`) and compare against each `notion_docs` entry's **`id`** field. (`notion_docs` is an array of `{url, id, title}` objects — match on `id`, which is already normalized; fall back to extracting the id from the entry's `url` if `id` is missing.)
3. **If a project references it:** that's the project to shape — go to step 2.
4. **If nothing references it:** create a new project (step 1a), then continue.

### 1a. Create a new project (no existing reference)
1. Fetch the doc with `mcp__claude_ai_Notion__notion-fetch` to get its **title** and enough content to scope it.
2. Do **initial research** to determine which repos belong in `project.json`: read the doc's scope, then use `Agent` (Explore) and `gh search` across the known orgs/repos to identify the relevant repositories. Cross-reference `.shaping-config/known-repos.json` for the usual candidates.
3. Run the new-project script so the user can confirm the inputs — it is interactive (free-text project name, repo multi-select, free-text Notion URLs), so it cannot be driven headlessly:
   ```
   scripts/project-manager.sh new
   ```
   Surface your recommendations up front so the user can enter them directly:
   - **Project name / folder** → the Notion doc **title** (the script auto-prefixes the next sequence number).
   - **Repositories** → the repos your research identified (the script's multi-select has an "Add new repository…" row for any not already known).
   - **Notion docs** → paste the original Notion URL.
4. After the script creates the project, verify `project.json`. The script derives the notion_doc `id` and a **slug-based** `title` from the URL — overwrite that `title` with the real fetched Notion title from step 1a.1. Then continue to step 2.

## 2. Read project state
Read all four from the project directory: `project.json`, `Features.md`, `Services.md`, `planning-state.md`.

`project.json` has `repositories` (array of `{org, repo}`) and `notion_docs` (array of `{url, id, title}` objects).

## 3. Sync local repos to origin/main
For each repo in `repositories` that exists locally under `/Users/cpies/code/shaping/Research Repos/` (also check the nested `Legacy/` subdir):
- `git status`, then `git pull origin <default-branch>` (detect main vs master).
- **If the pull fails, the tree is dirty, or it's on a non-main branch: STOP.** Report which repo, what branch, and what the user needs to do (stash / switch / resolve). Do not research that repo until they confirm.

The `sync-repos` skill implements this loop — you may invoke it for the sync step.

## 4. Gather Notion context
For each entry in `notion_docs`, fetch by its `url` (or `id`) with `mcp__claude_ai_Notion__notion-fetch`. Also check `mcp__claude_ai_Notion__notion-get-comments` for open questions/comments (resolve authors via `notion-get-users`).
(Note: the actual MCP server is `claude_ai_Notion`, prefix `mcp__claude_ai_Notion__`.)

## 5. Research the repositories
Invoke the `research-repos` skill (pass this project number) — it decides whether each part of the scope lives in **legacy** repos (`Research Repos/Legacy/*`), the modern **unified** repos (top-level `Research Repos/*`), or **both**, then fans out Explore agents against the right tier(s). It also keeps `project.json`'s `repositories` list current as it discovers relevant repos.

If researching a single repo directly: `gh repo view {org}/{repo}` for overview, then fan out with `Agent` (Explore type) to search relevant code, issues, and PRs, and read source from the local `Research Repos/` checkout. Prefer parallel Explore agents over reading whole files yourself.

## 6. Plan with the user (planning mode)
Identify features, services, APIs, data models, and migration steps. Update `Features.md` and `Services.md`. Flag unanswered questions and areas needing research. Use `AskUserQuestion` when a decision is genuinely the user's to make.

## 7. Update planning-state.md
Refresh these sections:
- **Identified So Far** — what's discovered/documented
- **Still Needs Research** — open investigation areas
- **Unanswered Questions** — numbered (Q1, Q2, …) so they can be closed via the `resolve-question` skill
- **Research Sources Consulted** — repos, docs, files reviewed

## Related
- `research-repos` — the codebase-research step (step 5): legacy vs. unified tier decision + Explore fan-out.
- `sync-repos` — the repo-pull step, standalone.
- `notion-sync` — push the updated docs back to Notion (step: after planning).
- `resolve-question` — answer a specific Q# later.
