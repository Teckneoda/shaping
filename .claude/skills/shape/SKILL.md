---
name: shape
description: Run a full shaping/research pass on a Shaping Project, identified by number OR by a Notion URL. Use when the user says "shape N", "research N", "shape <project>", or "shape <notion-url>" (e.g. "shape 4", "Research #3", "shape https://notion.so/..."). Resolves or creates the project, syncs its repos, pulls Notion context, researches the codebase, then plans with the user and updates the living docs.
---

# Shape a project

Trigger: **"shape N"**, **"research N"**, **"Research #N"** (project number), or **"shape <notion-url>"** (a Notion doc link).

## 1. Resolve the project

Both "by number" and "by Notion URL" resolution are deterministic lookups handled by one shared script — run it first (don't hand-parse the id or scan `project.json` files yourself):
```
scripts/resolve-project.sh <number|notion-url>
```
- **Prints a folder path (exit 0):** that's the project to shape. If it also prints `ARCHIVED` on stderr, the folder is under `_archived/` — **confirm with the user before proceeding**. Then go to step 2.
- **Exits non-zero (no match):**
  - Given a **number** → tell the user no such project exists.
  - Given a **Notion URL** → nothing references it yet; **create a new project** (step 1a), then continue.

(The script extracts the 32-char page id from the URL — correctly ignoring the `?v=` view id, which is also 32 hex — and matches it against every `notion_docs[].id`, falling back to the entry's `url`.)

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
Run the shared sync script — scoped to this project's repos by passing their folder names:
```
scripts/sync-repos.sh <repo-name> <repo-name> ...   # names from project.json .repositories[].repo
```
It fast-forwards each clean repo and reports `SKIPPED`/`ERROR` for any that are dirty or on a non-default branch. **If any relevant repo comes back `SKIPPED` or `ERROR`: STOP.** Report which repo, its branch/state, and what the user needs to do (stash / switch / resolve). Do not research that repo until they confirm. (This is the same script the `sync-repos` skill runs.)

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
