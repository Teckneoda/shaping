---
name: notion-sync
description: Sync a Shaping Project's docs to/from its Notion page, preserving Notion's existing format and only touching designated sections. Use when the user says "sync to Notion", "sync shaped details to Notion", "check for updates/questions on the notion doc", or asks to push slices/technical details to Notion. Args: project number and optional direction (push/pull).
---

# Notion sync

Two directions. Default to **push** unless the user says "check for updates/questions" or otherwise implies pulling Notion → local.

## Resolve target
Read the project's `project.json`. `notion_docs` is an array of `{url, id, title}` objects — fetch each by its `url` (or `id`) with `mcp__claude_ai_Notion__notion-fetch`.
(The MCP server is `claude_ai_Notion`; tool prefix `mcp__claude_ai_Notion__`. CLAUDE.md's older `mcp-notion` name is stale.)

## Golden rules (apply both directions)
- **Match Notion's existing formatting** — headers, callouts, toggles. Never dump raw markdown that doesn't match the surrounding style.
- **Only touch designated sections.** Never edit content above/outside the agreed markers. The user's recurring conventions:
  - Everything **after the "SHAPING" heading** is yours to edit; nothing above it.
  - **"TECHNICAL DETAILS (Engineering)"** — engineering/service details go here.
  - **"Risks and rabbit holes"** → add a header **"Proposed slices"** after it for the slice breakdown.
- When unsure which section a piece of content maps to, ask rather than guess.

## Push (local → Notion)
1. Read the relevant local docs (`Features.md`, `Services.md`, `planning-state.md`).
2. Map content into the correct Notion sections per the markers above.
3. If pushing slices: **estimate time per slice and an overall project estimate.**
4. Update via `mcp__claude_ai_Notion__notion-update-page`. Preserve everything outside the target sections.

## Pull (Notion → local)
1. Fetch the page and `mcp__claude_ai_Notion__notion-get-comments` (resolve authors with `notion-get-users`).
2. Diff against `planning-state.md` — surface new comments, questions, or edits.
3. Fold new questions into the **Unanswered Questions** section (numbered Q1, Q2, …) and report what changed. Don't silently overwrite local docs — summarize and confirm.

## Commit after sync
After a sync completes, commit the local changes relevant to what was just synced.
- Stage only the files tied to this sync — the project's `Features.md`, `Services.md`, `planning-state.md`, `project.json`. Don't sweep in unrelated changes elsewhere in the repo.
- Commit with `-c commit.gpgsign=false` (user preference — no GPG signing in this repo).
- Write a message describing the sync, e.g. `Sync <project> shaping docs to Notion`.
- If nothing relevant changed locally (e.g. a pure pull that only surfaced questions you haven't applied yet), skip the commit and say so.
- Commit only; do not push unless the user asks.

## Related
- `shape` — produces the docs you're syncing.
- `resolve-question` — closes Q# items surfaced by a pull.
