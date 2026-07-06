---
name: resolve-question
description: Close out a numbered open question in a Shaping Project's planning-state.md and fold the answer into the relevant docs. Use when the user says "resolve Q9", "Q17 <answer>", or answers a numbered question (e.g. "Q2: no design change"). Args: project number (if ambiguous), the Q number(s), and the answer.
---

# Resolve a planning question

The user answers one or more numbered questions from a project's **Unanswered Questions** section. Sometimes several at once ("Q17 embed. Q16 <url>").

## Steps
1. **Resolve the project.** If the current context makes it obvious, use that; otherwise ask which project number, then resolve its folder deterministically with `scripts/resolve-project.sh <number>` (don't hand-build the `NNN` folder name).
2. Read `planning-state.md` and locate the referenced **Q#** under "Unanswered Questions".
3. **Apply the answer** to the substantive docs — `Features.md` and/or `Services.md` — wherever that question's outcome changes the plan.
4. **Close the question** in `planning-state.md`: mark it resolved (with the answer) or move it out of "Unanswered Questions". If the answer opens new questions, add them (renumbered/appended).
5. Add a dated changelog entry at the bottom of `planning-state.md` noting what was resolved.
6. Briefly report what changed. If the resolution meaningfully alters the docs, offer to push to Notion via `notion-sync`.

## Notes
- Answers may be terse (a URL, "embed", "no change to current design") — interpret against the question's text before editing.
- Don't invent detail the user didn't give; if the answer is ambiguous for a doc edit, confirm first.
