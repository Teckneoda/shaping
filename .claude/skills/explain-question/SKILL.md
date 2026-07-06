---
name: explain-question
description: Explain a single open (numbered) planning question in plain language when the terse Unanswered-Questions wording isn't enough to understand it. Synthesizes from the project's own docs + Notion only (no codebase fan-out). The natural follow-up to open-questions. Use when the user says "tell me more about Q4", "what does Q6 mean", "explain that question", "I don't get Q3". Args: the Q number(s) and, if not obvious from context, the project number.
---

# Explain an open question

The user just saw a terse numbered question (usually via `open-questions`) and wants to understand it before answering. Unpack **what it's really asking, why it matters, and the likely options/tradeoffs** — using only the project's existing docs and Notion. This skill is read-only.

## Scope of research
- **Docs / Notion only.** Draw from `planning-state.md`, `Features.md`, `Services.md`, and the project's `notion_docs`. Also lean on any refs the question itself cites (file:line links, Notion pages, prior Q's it references).
- **Do NOT fan out into the Research Repos / codebase.** No `gh`, no repo file exploration, no `research-repos`. If the docs and Notion genuinely can't explain it, say so and suggest a `shape` / `research-repos` pass rather than guessing.

## Steps
1. **Resolve the project + Q number.** Use context if obvious (e.g. `open-questions` just surfaced them); otherwise ask which project, then get its folder with `scripts/resolve-project.sh <number>`.
2. Read `planning-state.md` and locate the referenced **Q#** under "Unanswered Questions" — capture its exact wording, owner/blocker, and any refs or cross-referenced Q's.
3. **Gather supporting context** from that project's `Features.md`, `Services.md`, and — via the Notion MCP server (`mcp__claude_ai_Notion__notion-fetch`) — the entries in `notion_docs`, focusing on the parts touching this question. Follow the specific refs the question cites.
4. **Explain it**, tightly:
   - **What it's asking** — restate the question in plain language.
   - **Why it matters** — what depends on the answer / what it blocks.
   - **Options & tradeoffs** — the candidate answers implied by the docs, with pros/cons where the docs support them.
   - **What's still unknown** — if the docs/Notion don't settle it, name exactly what's missing and where a fuller answer would come from.
5. Keep it focused on the **one** question asked (or the few named). Don't drift into unrelated open items.

## Notes
- Read-only: never edit `planning-state.md`, `Features.md`, or `Services.md` here.
- If the explanation leads the user to an answer, hand off to `resolve-question` (same Q-number contract).
- Ground claims in what the docs/Notion actually say — flag inference as inference, don't invent detail.
