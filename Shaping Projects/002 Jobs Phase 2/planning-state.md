# Jobs Phase 2 — Planning State

Living document tracking what's identified, what still needs research, and open questions. Updated each shape session.

**Last shaped:** 2026-06-25

> ⚠️ **Major finding (2026-06-25):** Codebase research shows Phase 1 shipped far more of the Phase 2 surface than the earlier planning docs assumed. Most of the listing-service, search-service, and GraphQL work is **already built**. The genuinely remaining Phase 2 work is concentrated in: (1) end-to-end wiring of the 3 string Jobs filters (ES mapping + connector + search filter config), (2) the **listing lifecycle automation + Archive DB** (deactivate/expire/delete → archive crons + retention), (3) **web frontend** detail-page + SRP wiring, (4) the **external MyAccount app** (separate repo — not yet in research set), and (5) the **React Native app**.

---

## Status Legend
✅ Built / verified in code   🔨 Gap — needs build   ❓ Open question   🚫 Out of scope

---

## Identified So Far

### Already built (verified in marketplace-backend / marketplace-graphql / marketplace-frontend)

**listing-http-rest** (`apps/listing/services/listing-http-rest`)
- ✅ All listing statuses incl. `Inactive`, `Expired`, `Deleted` — `internal/types/listing.go:31-40`
- ✅ `MarketTypeJob = "Job"` — `listing.go:51`
- ✅ All 7 Jobs fields on the model — `listing.go:1316-1323` (payRangeType, payFrom, payTo, applicationUrl, employmentType, yearsExperience, educationLevel)
- ✅ `DeletedAt` + `DeactivatedAt` (and `SoldAt`, `SalePendingAt`) timestamps — `listing.go:1326-1329`
- ✅ Lifecycle policy guards — `listing.go:125-166` (delete from Stub/Active/Inactive/Expired/Sold; deactivate from Active; restore-to-draft from Inactive/Expired/Deleted)
- ✅ `GET /listing/{id}` returns all Jobs fields + `listingType` (CLASSIFIED|JOB) — `internal/handler/get.go`, `internal/types/response.go`
- ✅ MyAccount action endpoints all exist — `routes.go`: `PUT /listing/{id}/mark-sold`, `/mark-sale-pending`, `DELETE /listing/{id}` (soft delete), `PUT /listing/{id}/deactivate`, `/renew`, `POST .../request-activation`, `PUT .../draft` (restore-to-draft), `DELETE .../purge`
- ✅ Renewal enforces the **14-day rule**: 30-day window, 14-day tail (renew unlocks after day 16) — `internal/domain/renew.go:19-21` → acceptance criterion already met

**search-http-rest** (dedicated SRP search service — `apps/listing/services/search-http-rest`)
- ✅ Custom pay-range filter mapping (`jobsPayRangeType`, `jobsPayFrom`, `jobsPayTo`) — `internal/config/filter.go:223-250`, overlap logic in `internal/store/elastic/query.go` (`generateJobsPayRangeFilters`)
- ✅ SRP API returns pay-range fields — `internal/api/classified-listing.go`

**marketplace-graphql**
- ✅ Feature-flag infra with member-ID allowlist — `graph/queryresolvers/featureconfig.go`, `remoteconfig.go`; Jobs gates in `jobs_gate.go` (`shouldShowJobsMarketType`, anon users excluded)
- ✅ `Job` exposed as a selectable `marketType` (gated) — `classifieds-conditional-fields.go:59-61` (`filterOutJob` when gate off)
- ✅ Jobs SRP filter groups already built — `jobs_srp_filter_groups.go` (job type, education level, years experience, pay range) + visibility rules
- ✅ All Jobs detail fields in schema — `graph/schema/types.listings.graphqls:987-1013`
- ✅ Lifecycle mutations proxy to listing-http-rest — `classifieds_listing_lifecycle.go`: `deactivateClassifiedsListing`, `renewClassifiedsListing`, `softDeleteClassifiedsListing`, `restoreClassifiedsListingToDraft`, `purgeClassifiedsListing`

**marketplace-frontend** (web — `apps/ksl-marketplace`)
- ✅ Jobs pay-range filter card — `app/components/Filters/Cards/JobsPayRange.tsx`
- ✅ Jobs SRP visibility logic + pay-range utils — `utils/jobs-listing-type.ts`, `utils/jobs-pay-range.ts`
- ✅ Jobs fields in classifieds detail schema incl. `jobsApplicationMethod: "ksl" | "url"` (maps to the two-button Apply requirement) — `services/listing/schema/classifieds.ts:113-148`

### Confirmed scope (from Notion shaping doc)
- Jobs fields are **top-level** (not specSubCat): employment type, education level, years experience pivoted to top-level alongside pay range. **Company Perks dropped.** `jobApplicationDeadline` dropped.
- `marketType` same-index filtering; add "Job" value (done).
- SRP grid-vs-list is **frontend-only**; Jobs-list view is now **NTH** (descoped from must-have).
- **Status lifecycle + retention** (Notion locked): `Deleted` → 30 days → Archived; `Expired` → 1 year → Archived; `Inactive` → 1 year → Archived; `Stub` → 2 weeks → Archived; Archived = 6-month retention.
- **Deactivate** workflow: user deactivates → `Inactive`; reactivates by going through PaL + checkout again (restore-to-draft → edit → checkout).
- Detail-page Apply button has **two variants**: (1) navigate to external URL, (2) "Apply Now" dummy button (real Apply Now is Phase 4).

---

## Still Needs Research / Build (the real Phase 2 gaps)

### Backend — Jobs filter end-to-end wiring 🔨
- 🔨 ES index model is missing `jobsEmploymentType`, `jobsEducationLevel`, `jobsYearsExperience` — `search-http-rest/internal/store/elastic/model.go` only has applicationUrl + payRangeType (+ pay aggregation)
- 🔨 Search filter config only maps pay fields — `search-http-rest/internal/config/filter.go:223-250` has **no** employment/education/experience string filters, even though GraphQL already returns those filter groups. **End-to-end filtering for those 3 fields is incomplete.**
- 🔨 Mongo→ES connector (`apps/listing/services/listing-mcs-netcore`) must sync the 3 string fields

### Backend — Lifecycle automation + Archive DB 🔨 (largest net-new area)
- 🔨 **Archive DB does not exist** — no archive collection/database or `archive` concept anywhere in listing-http-rest. Needs design + build.
- 🔨 `listing-cron-soft-delete` is **scaffolded but not implemented** — has client/types/auth (`internal/...`, ~600 LOC) but `app.go` run loop is empty (15 lines). Needs the actual candidate-query + transition logic.
- 🔨 Crons required per Notion: (a) soft-delete `Inactive`→archive after 1yr, (b) `Deleted`→archive after 30d, (c) `Expired`→archive after 1yr, plus an auto-**Expire** process. `listing-cron-auto-renew` exists and handles renew/expire reminders — confirm whether expiry-setting lives there.
- ❓ How does "Archived (6-mo retention) → permanent purge" execute? Is `purge` endpoint (exists) the mechanism, or a separate hard-delete job?

### GraphQL 🔨 / ❓
- ❓ Is **Jobs a distinct Category** in Category Manager (Notion: "Category = Jobs", ~40 industries as subcategories), or only a `marketType`? marketType gating is built; **category-level** gating/creation is not confirmed. Needs Category Manager work + possible category-level feature flag.
- 🔨 `markListingSold` / `makeListingAvailable` are **CAPI-only** today — confirm whether Jobs MyAccount needs the listing-http-rest path wired (`listing-status.go`)

### Web frontend 🔨
- 🔨 Detail-page Jobs display **section** not built (schema fields exist; config-driven render in `app/listing/[id]/config/classifieds-config.tsx` needs a Jobs section)
- 🔨 Apply button two-variant rendering in `ActionButtons.tsx` (URL vs dummy Apply Now)
- 🔨 SRP "Jobs" listing-type option wiring/visibility polish; grid-vs-list = NTH

### MyAccount (`deseretdigital/m-ksl-myaccount-v2` — added + researched 2026-06-25)
- ✅ **Mostly already built for Classifieds.** The General manage path implements the full lifecycle behind `classifiedsLifecycleGateOpen`: Deactivate, soft Delete, Activate (restore-to-draft → checkout), Delete-No-Undo purge, Mark Sold/Sale Pending, Renew, and the status dropdown with Inactive/Expired/Deleted. Stack: Next.js 15 + MobX + SWR; own `/api/v1/listings/...` REST routes (not GraphQL).
- ✅ **Q9 RESOLVED → General path.** Migrated Jobs are typed as **Classifieds (marketType `Job`)** so they render `GeneralListing`/`GeneralManage` and inherit the full gated lifecycle. Routing is purely `listing.type` in `components/Listings.tsx:34-50` (Jobs→JobManage, Classifieds→GeneralManage), so this is a **data-contract decision in the migration**, not a UI rewrite. Legacy `JobManage` is NOT decommissioned by this — it stays for any non-migrated Jobs.
  - Note: `JobManage.tsx` (236 LOC) already has Job Activate/Deactivate/Renew/Delete/Applications modals — it's richer than first noted — but lacks Delete-No-Undo **purge**, **Mark Sold / Mark Sale Pending**, and subscription-cancel, which only exist in `GeneralManage.tsx` (476 LOC, behind `classifiedsLifecycleGateOpen`). Riding General avoids porting those.
- 🔨 Remaining MyAccount work (General path): ensure Jobs-specific **card display** (pay range, employment type, etc.) renders within `GeneralListing`; status dropdown default "All" → "Active" (`ListingsFilterStore.ts:352,460`); add purge banner; verify modal copy vs Notion (1yr/30d/privacy text). `JobApplicationsModal` (Quick Apply) is Phase 4 — not needed now.

### App (React Native — separate repo, not in research set)
- 🔨 Jobs tab auto-selects Jobs category + subcategory list; remove Jobs from global search
- 🔨 Detail page hooks into unified detail page for Jobs fields + Apply button
- 🔨 PAL: render job-specific fields, hard-code (like Cars) — **now in scope** per Notion (was TBD)

---

## Resolved this session (2026-06-25)
- ✅ **Q1 — Jobs IS a real Category** with ~40 industry subcategories (not just a marketType). → Category Manager must create the Jobs category + subcategories, and GraphQL needs **category-level** gating (the existing gate is marketType-level only).
- ✅ **Q2 — Detail Page is READ-ONLY** for Phase 2; all editing goes through PAL (out of scope). The AC "update via GraphQL" line does not apply.
- ✅ **Q8 — Employment/Education/Experience ARE filterable on SRP.** → Build the full loop: ES mapping + Mongo connector sync + `search-http-rest` filter config to back the GraphQL filter groups that already exist.
- ✅ **Q9 — MyAccount: General (Classifieds) path.** Migrated Jobs typed as Classifieds (marketType `Job`) → render `GeneralManage` and inherit the full built lifecycle. Data-contract decision in the migration; legacy `JobManage` retained for non-migrated Jobs. Remaining work is Jobs card display in `GeneralListing` + dropdown default + copy verification.

## Unanswered Questions

| # | Question | Owner | Notes |
|---|----------|-------|-------|
| Q3 | Legal sign-off on retention values (30d / 1yr / 1yr / 6mo). Values proposed in Notion but Legal checkbox still unchecked. | Legal | Blocks finalizing cron retention config |
| Q4 | Where does the **Archive DB** live (separate collection? separate datastore?) and what's the read path for restore from archive? | Eng | Net-new; no existing pattern |
| Q6 | App team **2-week capacity** + PAL scope confirmation. | App | Notion now lists PAL in scope |
| Q7 | Frontend developer assignment for web SRP/Detail work. | PM | Standing blocker |

✅ **Q5 resolved** — MyAccount repo is `deseretdigital/m-ksl-myaccount-v2` (branch `master`); added to project.json and researched this session.

---

## Research Sources Consulted

**Notion**
- *Jobs to Classifieds — Phase 2 SRP, Detail, MyAccount* (page `3142ac5cb2358155a035d6758d0b8691`) — primary shaping doc; status "PKG: Building". Captured locked decisions, full status lifecycle + retention, Archive DB diagram, Manage-menu spec, two-button Apply, app PAL in scope, CX restore now out of scope.
- *Job Facets and Specifications* (page `3132ac5cb235806da903e777b55be742`) — facet list: ~40 industry subcategories, Job Type, Pay Range, Education, Years Experience; Company Perks & Top Jobs struck out.

**Repos** (synced to origin/main 2026-06-25, all clean)
- `deseretdigital/marketplace-backend` — listing-http-rest, search-http-rest, listing-cron-* , listing-mcs-netcore (see Identified So Far for file:line refs)
- `deseretdigital/marketplace-graphql` — feature gates, SRP filters, detail schema, lifecycle mutations
- `deseretdigital/marketplace-frontend` — SRP filter cards, detail config, jobs utils; **confirmed MyAccount is external (myaccount.ksl.com)**
- `deseretdigital/m-ksl-myaccount-v2` (branch `master`, cloned 2026-06-25) — listings management UI; Classifieds lifecycle already built behind a gate (see MyAccount section above)

**Not yet researched** — React Native app repo (not in research set; need repo name), `nest` (was the CX restore tool — now out of scope).

---

## Changelog
- **2026-06-25 (later):** Resolved Q1 (Jobs is a Category), Q2 (Detail read-only), Q8 (employment/education/experience SRP-filterable). Added `deseretdigital/m-ksl-myaccount-v2` to project.json (resolves Q5) and researched it — Classifieds lifecycle UI already largely built behind a gate. Also fixed stale `AI-Agents` Research Repos path in both CLAUDE.md files. ⚠️ Note for future syncs: m-ksl-myaccount-v2 default branch is **`master`**, not `main`.
- **2026-06-25 (later still):** Resolved **Q9 → General (Classifieds) manage path** for migrated Jobs (data-contract decision: type migrated Jobs as Classifieds/marketType Job; inherit GeneralManage lifecycle; legacy JobManage retained for non-migrated Jobs).
- **2026-06-25:** First structured shape session. Created `project.json` + `planning-state.md` (project predated scaffolding). Synced 3 repos to main. Fetched 2 Notion docs. Verified Phase 1 already shipped most of the listing-service / search-service / GraphQL surface; rewrote Features.md & Services.md around built-vs-gap reality. Flagged Archive DB + lifecycle crons as the largest net-new work, and the external MyAccount repo as missing from the project.
