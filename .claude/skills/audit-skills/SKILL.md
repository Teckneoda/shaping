---
name: audit-skills
description: Audit the Claude skills in this repo for visibility (auto-fire risk / menu clutter), determinism (AI doing work a script should), and composability (duplicated logic), then produce concrete rewrites plus a changelog. Use when the user says "audit my skills", "review the skills", "audit the skills folder", or asks to check skills for side effects / duplicated logic / steps that should be scripts. Args: an optional single skill name to scope the audit to just that skill.
---

# Audit skills

Review every skill under `.claude/skills/*/SKILL.md` (or the one named in args) across three dimensions, then **show the rewrites with a changelog of what changed and why**. Prefer applying the changes (new scripts + edited `SKILL.md` frontmatter/steps); if the user only wants the assessment, present findings first and apply on confirmation.

## 0. Load the skills

```
ls -d .claude/skills/*/
```
Read each `SKILL.md` (frontmatter **and** body). Also note existing shared scripts in `scripts/` — the deterministic/composability fixes usually land there, and some may already exist.

## 1. Visibility (frontmatter flags)

- **High-risk side effects → `disable-model-invocation: true`.** Any skill whose steps **deploy, commit, push, or send/write to an external service** (Notion, Slack, GitHub, email) should not be auto-fireable by description-matching — the user must invoke it explicitly. Add the flag and a one-line `> **Why...`** note in the body.
  - **Watch the composition trap:** if skill B invokes gated skill A to do the side effect, gating A breaks B. The fix is to push the side-effect logic into a **script** both call directly via Bash (see §2/§3), so the gate on the skill can't be bypassed *and* callers don't depend on the model re-invoking it.
- **Pure background knowledge → `user-invocable: false`.** Only for skills a human would never `/run` themselves (reference material invoked solely by other skills). Do **not** force this on a skill that has a natural user trigger phrase — report "none qualify" when that's the truth.

## 2. Deterministic vs non-deterministic

Find steps where the AI is *interpreting* something that is actually a **fixed, repeatable operation** — string/JSON parsing, folder lookups, `git` status/pull loops, `ls`+`grep` gathering, path building. These waste tokens and vary run-to-run.

- **Replace them with a script** in `scripts/` (shared) or the skill's own folder (skill-specific). Code = same result every time, no token cost.
- **Keep the AI** for the steps that need judgment (wording, "which is old", tier/architecture decisions, question interpretation, mapping content to sections). State explicitly in the rewrite which steps stay AI and why.
- Make scripts robust: `set -euo pipefail`, tab-separated output the skill parses, meaningful exit codes for the caller to branch on, and quote paths (folder names have spaces). **Smoke-test every script** against the real repo before finalizing (and undo any test side effects, e.g. a stray commit).

## 3. Composability (duplicated logic)

Flag any skill that re-implements logic another skill already has. Common culprits here: project-number/URL → folder resolution, listing active projects, the repo-sync loop, and git commit conventions.

- **Extract shared logic into one callable script** (or a smaller composable skill) and point every duplicate at it.
- Prefer a **script** over skill-to-skill invocation for shared *side-effect* primitives, so a `disable-model-invocation` gate on the user-facing wrapper doesn't break internal callers.

## 4. Deliver

Present, grouped by the three dimensions above:
1. A short **findings summary** (what qualifies under each dimension; honest non-findings included).
2. The **rewrites** — new/edited files (frontmatter changes, script bodies, replaced steps).
3. A **changelog table**: for each change, *what changed* and *why*, and which steps deliberately stayed AI-driven.

Leave changes uncommitted unless asked; offer to sync via `commit-push` at the end.

## Notes
- Match this repo's script conventions (bash 3.2, `jq` available, GPG signing off, the required co-author trailer — see `scripts/git-commit-push.sh`).
- Don't over-apply the flags: `disable-model-invocation` only for real outward/irreversible side effects; `user-invocable: false` only for genuine background-only skills.
