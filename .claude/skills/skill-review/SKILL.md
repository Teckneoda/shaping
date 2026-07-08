---
name: skill-review
description: Review the back-and-forth that just happened after a skill was used, and enhance that skill so the same friction is handled automatically next time. Use when the user says "review the skill I just used", "can we make this automatic", "improve that skill based on what just happened", or "skill-review". Args: an optional skill name to target (otherwise inferred from the recent conversation).
---

# Skill review

The user just ran a skill and had to steer it — answering clarifying questions, correcting a wrong assumption, feeding context the skill should have gathered itself, or hand-walking steps. The goal of this skill is to **turn that manual back-and-forth into automatic behavior** by editing the offending skill (its `SKILL.md`, and/or a shared script), then showing what changed and why.

This works from the **conversation already in context** — the "back and forth I just had." Don't go hunting through transcript files; the exchange to review is the one immediately preceding this invocation.

## 1. Identify the skill under review

- If args name a skill, use it. Otherwise infer from the recent conversation which skill was invoked (look for the `Skill`/`<command-name>` that kicked off the exchange).
- If it's genuinely ambiguous which skill caused the friction, ask the user which one — don't guess.
- Read that skill's `SKILL.md` (frontmatter **and** body) from `.claude/skills/<name>/SKILL.md`, plus any scripts it calls in `scripts/`.

## 2. Extract the friction from the exchange

Re-read the back-and-forth and list every point where the skill did **not** just work. Categorize each:

- **Clarifying questions Claude asked** — could the answer have been resolved from the project docs, `project.json`, Notion, or a script instead of asking?
- **Corrections the user made** — a wrong assumption, wrong file/path, wrong ordering, wrong default. What rule would have prevented it?
- **Context Claude had to be handed** — info the skill should have gathered on its own (a lookup, a file read, a repo state check).
- **Manual/repeated steps** — deterministic operations the user walked Claude through that a script should own.
- **Ambiguity in the skill's wording** — instructions that were open to the interpretation that went wrong.

## 3. Decide what's actually worth automating

Not every turn should be baked in. For each friction point, judge:

- **Automate it** if it's *recurring and general* — it would happen again on the next run for any project/input.
- **Leave it as a question** if it's a genuine per-run judgment call (which project, which option) that legitimately needs the user. In that case the fix may just be making the skill *ask better / ask once, up front* rather than removing the question.
- **Don't over-fit to this one case** — a single user's one-off choice ("this time, skip X") is not a new default. Encode the *principle*, not the incident.

Apply the same lens as `audit-skills`:
- Deterministic, repeatable work (parsing, path/folder resolution, git status/pull, `ls`+`grep` gathering) → **push into a script**, don't describe it in prose.
- Judgment (wording, tier/architecture calls, mapping content to sections) → **keep AI-driven**, but tighten the instruction so it goes the right way.
- Reuse existing shared scripts (`scripts/resolve-project.sh`, `scripts/list-projects.sh`, `scripts/sync-repos.sh`, `scripts/git-commit-push.sh`) rather than re-implementing.

## 4. Draft the enhancement

Produce the concrete edit:
- **`SKILL.md` changes** — tightened steps, new default rules, a "gather X before asking" instruction, or an added up-front context step. Update the `description:` too if the trigger conditions or args changed.
- **Script changes** — if a deterministic step should move into code, write/extend a script in `scripts/` (match repo conventions: bash 3.2, `set -euo pipefail`, `jq` available, tab-separated output, quoted paths, GPG signing off). **Smoke-test any new/changed script** against the real repo and undo test side effects.

## 5. Deliver

Present:
1. A short **friction summary** — what in the exchange required steering, grouped by the categories in §2.
2. The **proposed edits** — the actual `SKILL.md` diff and any script, each tied to the friction point it eliminates.
3. A one-line **rationale** per change (and note anything you deliberately left as a question and why).

Show the plan first and apply on confirmation, unless the change is small and unambiguous — then apply directly and report. Leave changes uncommitted unless asked; offer to sync via `commit-push` at the end.

## Notes
- Editing `.claude/skills/**` and `scripts/**` is an in-repo change, not an outward side effect — no gating needed. But if the enhanced skill would gain a real outward/irreversible side effect, apply the `audit-skills` visibility rules (`disable-model-invocation`).
- Prefer the smallest change that removes the friction. A precise sentence often beats a new script.
- If the friction was actually the *user's* mistake (not the skill's), say so plainly instead of contorting the skill to absorb it.
