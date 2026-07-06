---
name: open-questions
description: Surface the unresolved (numbered) questions in a Shaping Project's planning-state.md so they can be worked or answered. The read/surface counterpart to resolve-question. Use when the user says "what's still open on N", "find open questions", "what questions are unresolved", "what's left to answer". Args: an optional project number or shaped package; if none, sweeps all active projects one at a time.
---

# Surface unresolved questions

Find and present the still-open **numbered** questions from a project's **Unanswered Questions** section, so the user can decide what to answer next. This skill only *reports* — it does not edit docs. When the user answers, hand off to `resolve-question`.

## Scope
- **A specific project is supplied** (a number like "7", or the user is clearly working a shaped package / a project is obvious from context): scope to that one project only.
- **No project supplied**: sweep **all active** projects under `Shaping Projects/` (skip `_archived/`), but present **one project at a time** — never dump every project's questions at once. Go in project-number order; after each, ask whether to continue to the next project or stop.

## Steps
1. **Resolve scope** per the rules above. For a sweep, list the active project directories first (numeric order).
2. For each in-scope project, read `planning-state.md` and locate the **Unanswered Questions** section.
3. **Extract only the numbered open questions** (`Q6`, `1.`/`2.`, or `| Q6 | … |` table rows — formats vary by project). Skip anything already marked resolved/closed. Do **not** pull in inline TODO / TBD / "confirm" / ⚠️ / ❓ markers scattered through the docs — numbered Unanswered Questions only.
4. **Present them for that one project**: the project name, then each open Q with its number and a concise restatement (preserve the original Q number so it lines up with `resolve-question`). If a question carries an owner/blocker column, include it. If the section is empty or missing, say so plainly.
5. **In a sweep**, after presenting one project, pause and ask whether to move to the next project or stop. Do not proceed to the next project unprompted.

## Notes
- Read-only: never modify `planning-state.md`, `Features.md`, or `Services.md` here.
- If a surfaced question is too terse to understand and the user asks for more detail on it ("tell me more about Q4", "what does that mean"), hand off to `explain-question` (same Q-number contract).
- When the user answers one of the surfaced questions, route to `resolve-question` (same Q-number contract).
- Keep each project's presentation tight — the point is to let the user focus on one project's open items without cross-project noise.
