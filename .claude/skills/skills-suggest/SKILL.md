---
name: skills-suggest
description: Mine recent Claude Code sessions for tasks the user keeps doing as one-off prompts, and propose new skills to capture them. For each recurring task, suggests a skill name, a trigger description, and the context/inputs the skill would need. Use when the user says "what should be a skill?", "what am I doing repeatedly?", "suggest skills based on my recent sessions", "what tasks should I turn into skills", or "skills-suggest". Args: optional scope — a project/repo name to focus on (e.g. "shaping") and/or a lookback window in days (e.g. "14 days").
---

# Suggest skills from recent work

Look at what the user has actually been doing across recent sessions, find the **repeated task shapes** that are still being driven by hand-written prompts, and propose turning each into a skill. The output is a ranked set of concrete skill proposals — not a pile of raw prompts.

This is **read-only analysis**. It reads session transcripts and the existing skills; it does not create, edit, or commit anything. If the user likes a proposal, creating it is a separate step (a normal "add a skill named X" request).

## 1. Gather the recent prompts

Deterministic gathering is done by a script — don't hand-parse transcripts:

```
scripts/extract-prompts.sh [--days N] [--project NAME] [--limit N]
```

It scans `~/.claude/projects/*/*.jsonl` (every project the user works in — recurring work spans repos), strips harness/tool/system noise, and prints newest-first tab-separated rows: `date · project-dir · session-id · prompt`.

- Default is **all projects, last 30 days**. Honor any scope in the args: a repo/project name → `--project NAME`; a stated window → `--days N`.
- The `project-dir` column (e.g. `-Users-cpies-code-marketplace-backend`) tells you which repo each prompt came from — useful signal for clustering and for where a skill should live.

## 2. Cluster into recurring task shapes

Read the prompts and group them by the *kind of task*, not exact wording. You are looking for a **task the user performs repeatedly** — the same intent recurring across different inputs/sessions.

- **Discard noise**: bare confirmations ("yes", "stop", "let's try it"), one-off clarifications, and follow-up replies inside a single task are not recurring tasks.
- **A cluster qualifies** when the same intent shows up **at least ~3 times** (across sessions or clearly repeated within them). Note frequency — it drives the ranking.
- Watch for the same task appearing in **multiple repos** (e.g. "trace how X works in this codebase" asked in backend, graphql, and frontend) — cross-repo repetition is the strongest signal.
- Capture, for each cluster: the recurring intent, 2-3 representative example prompts (verbatim, trimmed), how often it appeared, and which repo(s).

## 3. Filter against skills that already exist

Read the existing skills so you don't propose duplicates:

```
ls -d .claude/skills/*/
```

Read each `SKILL.md` frontmatter (`name` + `description`). For every cluster, decide:
- **Already covered** → drop it (or, if the existing skill *almost* covers it, note it as a possible enhancement to that skill rather than a new one).
- **Not covered** → it's a genuine proposal.

Note that skills here are repo-local to `shaping`. A recurring task that happens in *other* repos (e.g. marketplace-backend) may still be worth a skill, but flag where it would need to live.

## 4. Propose the skills

For each surviving cluster, present a proposal with:

- **Suggested name** — kebab-case, verb-led, consistent with existing skill names.
- **What it would do** — one or two sentences (this becomes the skill's purpose).
- **Trigger description** — the natural-language phrases that should fire it (this becomes the `description:` line).
- **Context / inputs it needs** — the concrete things the skill must gather or be handed to run without back-and-forth: which files/docs to read, which repos, what args the user supplies, any script or MCP/CLI it depends on. This is the most important field — it's what turns a prompt into a reusable skill.
- **Evidence** — how many times it recurred and 1-2 example prompts, so the user can judge.
- **Deterministic vs judgment** — a one-line note on what a backing script could own vs what stays AI-driven (mirrors `audit-skills` thinking).

Rank proposals by frequency × how mechanical/repeatable they are (high-frequency mechanical tasks are the best skill candidates).

## 5. Deliver

Present the ranked proposals as a short list. Lead with a one-line summary ("Scanned N prompts across M sessions / K repos over the last D days; found P recurring task shapes worth turning into skills"). End by noting that you can create any of them on request.

## Notes
- Don't over-fit: a task done twice in one afternoon on one project is probably not a durable skill. Prefer patterns that recur across days or sessions.
- Be honest about thin evidence — if only one or two weak clusters emerge, say so rather than padding the list.
- If the user asks to actually build one of the proposals, hand off to a normal skill-creation request (and reuse shared scripts in `scripts/` where the context-gathering is deterministic).
