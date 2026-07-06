---
name: research-repos
description: Research the marketplace codebase for a shaping topic, deciding whether the answer lives in LEGACY repos, the modern UNIFIED repos, or both — then fanning out Explore agents against the right tier(s). Use when the user says "research the repos for X", "where is X handled", "what already exists for X", or as the codebase-research step invoked by the `shape` skill. Args: a research topic/question, and optionally a project number to scope repos to that project's project.json.
---

# Research repos (legacy vs. unified)

Decide **which tier(s)** of the marketplace codebase to research for a topic, then research them. This is the codebase-research engine `shape` uses in its step 5, but it can also be run standalone.

## project.json is the scoped repo list

Each Shaping Project's `project.json` holds the `repositories` that apply to **that** shaped package. Treat it as the source of truth for scope:

- **Always research the repos it calls out.** When given a project number, resolve its folder with `scripts/resolve-project.sh <number>`, read that folder's `project.json` first, and include every repo in `repositories` as a candidate.
- **Keep it up to date.** If research surfaces a repo that clearly belongs to this package but isn't listed, add it to `repositories` (`{org, repo}`, org defaults to `deseretdigital`) — or run `scripts/project-manager.sh update` so the user can confirm. If a listed repo turns out irrelevant, flag it for removal. Report any change you make.

## The two tiers

Tier is determined by **directory location** under `/Users/cpies/code/shaping/Research Repos/` — this is authoritative and never goes stale:

- **UNIFIED (modern)** = top-level `Research Repos/*` — e.g. `marketplace-backend`, `marketplace-frontend`, `marketplace-graphql`, `push-notifications-service`, `saved-search-alert-workers`, `saved-search-match-service`, `saved-search-percolation`, `listing-pricing`, `images-services`, `ddm-platform`, `ddm-protobuf`, `marketplace-reports`, `golang-o11y`. These are the **target** of new work. Per CLAUDE.md: new APIs → `marketplace-backend`, new GraphQL → `marketplace-graphql`, new UI → `marketplace-frontend`.
- **LEGACY** = `Research Repos/Legacy/*` — the `m-ksl-*` / `ksl-*` era (e.g. `m-ksl-jobs`, `m-ksl-classifieds`, `m-ksl-cars`, `ksl-api`, `classifieds-api-client`). These are the **source of truth for current production behavior** and are being re-implemented into the unified repos.

Derive the live lists at runtime rather than trusting a static copy:
```
ls -d "/Users/cpies/code/shaping/Research Repos"/*/ | grep -v '/Legacy/$'   # UNIFIED
ls -d "/Users/cpies/code/shaping/Research Repos/Legacy"/*/                    # LEGACY
```
**Ambiguous:** `nest` and `m-ksl-myaccount-v2` exist in both locations. Treat these as **both** and mention the ambiguity if either is a candidate.

## 1. Scope the candidate repos

- **If given a project number:** read `project.json`, start from its `repositories`, and classify each by whether it resolves under `Legacy/` or top-level.
- **Otherwise:** consider the full inventory (both `ls` commands above).

Then narrow to the topic:
- **Name/keyword match** the topic against repo names (e.g. topic "jobs" → legacy `m-ksl-jobs`; "saved search / alerts" → legacy `m-ksl-alerts`/`m-ksl-alert-workers` + unified `saved-search-*`; "cars" → `m-ksl-cars*`; "classifieds" → `m-ksl-classifieds*` + `marketplace-backend`).
- When a repo's fit is unclear, read its `CLAUDE.md`/`AGENTS.md`/`README` header to confirm domain before committing an Explore agent to it.
- If you identify a relevant repo not already in `project.json`, add it (see "keep it up to date" above).

## 2. Decide the tier — legacy, unified, or both

Classify the topic's intent:

| Topic intent | Research tier |
|---|---|
| "How does X work **today** / current behavior / existing data model / business rules being replaced" | **LEGACY** (then check unified for any partial migration) |
| **Net-new** feature with no legacy equivalent | **UNIFIED only** |
| Find **where new code goes** / patterns to follow / what's **already built** in modern stack | **UNIFIED** (`marketplace-backend` for APIs, `-graphql` for queries/mutations, `-frontend` for UI) |
| **Migration / re-implementation** ("move X to classifieds", "re-implement X", "Phase N of X→Y") | **BOTH** — legacy for current behavior, unified for target + what's already migrated |

**Default when unsure: BOTH.** Most shaping projects here are migrations (legacy → unified), so legacy defines the behavior to preserve and unified is where it lands. Only drop a tier when you're confident it's irrelevant.

State the decision explicitly before researching, e.g.:
> Topic "Quick Apply for jobs" → **both**. Legacy: `m-ksl-jobs` (current apply flow). Unified: `marketplace-backend`, `marketplace-graphql` (target + existing job endpoints).

## 3. Fan out research

For each chosen repo, prefer parallel `Agent` (Explore type) calls over reading whole files yourself:
- `gh repo view deseretdigital/{repo}` for a quick overview when needed.
- Explore the **local** checkout under `Research Repos/` (or `Research Repos/Legacy/`) for the relevant code, data models, endpoints, and flows.
- For legacy: capture **what the behavior is and where it lives** (so it can be preserved/re-implemented).
- For unified: capture **what already exists, where new code should go, and the patterns/ADRs to follow**.

Launch legacy and unified Explore agents in the same batch so they run concurrently.

## 4. Report

Return findings grouped by tier:
- **Legacy findings** — current behavior, data models, business rules, and file locations.
- **Unified findings** — existing implementation, target location for new code, patterns to follow, gaps.
- **Cross-tier gap** — what legacy does that the unified stack does not yet cover (the actual work).
- **project.json changes** — any repos added/flagged during research.
- **Open questions** — anything that needs a human answer (feed these into `planning-state.md` as Q# when run under `shape`).

## Related
- `shape` — invokes this as its codebase-research step (step 5); pass the project number so repos are scoped to `project.json`.
- `sync-repos` — pull latest before researching so findings reflect `origin/main`.
