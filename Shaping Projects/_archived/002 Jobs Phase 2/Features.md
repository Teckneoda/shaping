# Jobs Phase 2 — Features

Required features to complete the project (SRP, Detail Page, MyAccount), organized by area.

**Legend:** ✅ Built (verified in code) · 🔨 Gap (needs build) · ❓ Open · 🚫 Out of scope

> **Context (2026-06-25):** Phase 1 shipped most of the backend + GraphQL surface this phase originally scoped. Items below are marked with their verified state. The net-new Phase 2 work is concentrated in the **status lifecycle automation + Archive DB**, **end-to-end wiring of the 3 string Jobs filters**, the **web frontend**, the **external MyAccount app**, and the **React Native app**.

---

## 1. Category Manager Setup

### 1.1 Jobs Category & Subcategories
- ✅ **Decided (Q1): Jobs IS a real Category** with ~40 industry **subcategories** (Accounting & Finance, Healthcare, Transportation & Logistics, …) per the Job Facets doc.
- 🔨 Create the Jobs category + subcategories in Category Manager; publish to production behind the feature flag.
- No subcategory **specifications** required. Employment Type, Education Level, Years of Experience are **top-level listing fields** (`jobsEmploymentType`, `jobsEducationLevel`, `jobsYearsExperience`), handled like pay range. Company Perks **not implemented**.
  - `jobsEmploymentType`: Full Time, Part Time, Contract, Temporary, Internship, Seasonal (Notion facet list also includes "Weekend Only")
  - `jobsEducationLevel`: None, High School, 2 Year Degree, 4 Year Degree, Advanced Degree
  - `jobsYearsExperience`: None, 1-2 Years, 3-4 Years, 5-7 Years, 8-10 Years, >10 Years

### 1.2 Feature Flag for Jobs
- ✅ Member-ID allowlist feature-flag infra exists (`marketplace-graphql`: `featureconfig.go`, `jobs_gate.go`).
- ✅ `Job` marketType is already gated out of production responses for non-allowlisted users (`shouldShowJobsMarketType`, `filterOutJob`).
- 🔨 Add **category-level** gating (the existing gate is at the marketType level only; Q1 confirms Jobs is a category).
- Flag must be removable for launch.

---

## 2. Elasticsearch & Data Sync

### 2.1 ES Mapping Updates
- ✅ ES doc already indexes `jobsApplicationUrl`, `jobsPayRangeType`, `jobsPayFrom`, `jobsPayTo` and `marketType=Job` is supported (same-index filtering).
- 🔨 Add ES mappings for `jobsEmploymentType`, `jobsEducationLevel`, `jobsYearsExperience` (`search-http-rest/internal/store/elastic/model.go`).

### 2.2 Mongo Connector Updates
- 🔨 Update the Mongo→ES connector (`apps/listing/services/listing-mcs-netcore`) to sync the 3 string fields above.

### 2.3 Search Filter Config (the missing middle)
- ✅ Pay-range custom filters wired (`config/filter.go`, `query.go` overlap logic).
- 🔨 Add `jobsEmploymentType` / `jobsEducationLevel` / `jobsYearsExperience` as select/term filters in `config/filter.go`. **GraphQL already returns these filter groups, but ES + filter config do not back them yet** — Phase 2 must close this loop. (✅ Q8 decided: these **are** SRP-filterable.)

---

## 3. SRP (Search Results Page)

### 3.1 Backend — Search Service
- ✅ `marketType=Job` filtering supported by the dedicated `search-http-rest` service.
- ✅ Pay-range custom filter mapping done.
- 🔨 Employment/education/experience term filters (see §2.3).

### 3.2 Backend — GraphQL
- ✅ `Job` is a selectable `marketType` option (gated).
- ✅ Jobs filter groups (job type, education, experience, pay range) returned via `jobs_srp_filter_groups.go`.

### 3.3 Frontend — Web SRP (requires frontend resource)
- ✅ Jobs pay-range filter card + visibility utils exist.
- 🔨 Final wiring/polish of "Jobs" as a selectable listing type and conditional display of the term filters once ES backs them.
- Display rules (frontend-only):
  - Jobs mixed with other listing types → standard grid 🔨
  - 🚫/NTH Jobs-only → Jobs **list** view (descoped to nice-to-have; "Matt said ~30 min")
- **HIGHEST PRIORITY** per Notion: Jobs listings returned on initial SRP load + when Jobs selected, so the App team can build the Jobs card early.

---

## 4. Detail Page

### 4.1 Backend — Listing Service
- ✅ `GET /listing/{id}` already returns all Jobs top-level fields + `listingType`.

### 4.2 Backend — GraphQL
- ✅ All Jobs fields already in the detail schema (`types.listings.graphqls:987-1013`).

### 4.3 Frontend — Web Detail Page (requires frontend resource + design)
- ✅ Detail mockups now exist in Notion (collapsed / expanded / job specifications).
- 🔨 Build a Jobs detail **section** (config-driven render): Pay Range (formatted by `jobsPayRangeType`), Employment Type, Education Level, Years of Experience.
- 🔨 **Apply button — two variants** (schema field `jobsApplicationMethod` = `ksl | url` exists):
  - `url` → navigate to `jobsApplicationUrl`
  - `ksl` → "Apply Now" **dummy** button (real Apply Now is Phase 4)
- ✅ Q2 decided: **Detail Page is read-only**; editing goes through PAL (out of scope). The AC "update via GraphQL" line does not apply to Phase 2.

---

## 5. MyAccount

> ⚠️ The MyAccount listings UI is hosted at **myaccount.ksl.com** — a **separate app not in the current research repos**. Backend/GraphQL support is largely built; the UI work is unscoped until that repo is added (Open Q5).

### 5.1 Backend — Listing Service action endpoints
- ✅ All exist: `mark-sold`, `mark-sale-pending`, `delete` (soft delete), `deactivate`, `renew`, `request-activation`, `draft` (restore-to-draft), `purge`.
- ✅ Renewal already enforces the **14-day interval** (legacy Jobs "renew anytime" intentionally not carried over).
- ❓ `markListingSold` / `makeListingAvailable` GraphQL mutations are CAPI-only — confirm whether Jobs needs the listing-http-rest path (Open).

### 5.2 Status Lifecycle & Soft Delete
- ✅ Statuses exist: `Active`, `Inactive`, `Expired`, `Deleted`, `Sold`, `Pending`, `Stub`, etc.; `deletedAt` + `deactivatedAt` timestamps exist.
- 🔨 **Deactivate workflow**: Active → `Inactive`; reactivate = restore-to-draft → edit → checkout (re-pay subscriptions).
- 🔨 Soft-deleted / inactive listings excluded from ES search, not counted toward limits, billing stopped (verify ES exclusion path).
- ❓ Retention values (proposed in Notion, **pending Legal sign-off**): Deleted 30d, Inactive 1yr, Expired 1yr, Stub 2wk, Archived 6mo.

### 5.3 Archive DB + Lifecycle Crons 🔨 (largest net-new area)
- 🔨 **Archive DB** — does not exist yet. Design + build the archive datastore + write/read paths.
- 🔨 Cron: move `Deleted` → Archive after 30 days (`listing-cron-soft-delete` is scaffolded but the run loop is empty).
- 🔨 Cron: move `Inactive` → Archive after 1 year.
- 🔨 Cron: move `Expired` → Archive after 1 year; ensure auto-archive only touches listings ≥30 days in `Deleted`/`Expired`.
- 🔨 Auto-**Expire** process (confirm if it belongs in `listing-cron-auto-renew`).
- ❓ Archived → permanent **purge** after 6 months (via existing `purge` endpoint or separate hard-delete job?).

### 5.4 CX Restore Endpoint — 🚫 OUT OF SCOPE
- The CX-only "restore tool" (Nest) is **out of scope** for the Jobs → Classifieds migration (Notion update). Users self-restore via Activate → draft → checkout. *(Reversal from earlier draft of these docs.)*

### 5.5 Frontend — MyAccount (`deseretdigital/m-ksl-myaccount-v2`, branch `master`)
> ✅ **Largely already built for Classifieds.** The **GeneralManage** path implements the full lifecycle behind the `classifiedsLifecycleGateOpen` flag: Deactivate, soft Delete, **Activate** (restore-to-draft → checkout via `GeneralActivateModal`), **Delete (No Undo)** purge (`GeneralPurgeModal`), Mark Sold/Sale Pending, Renew, plus the **status dropdown** with Inactive/Expired/Deleted (gated). Stack: Next.js 15 + MobX + SWR, calling its own `/api/v1/listings/...` REST routes (not GraphQL directly).

- ✅ **Decided (Q9): General (Classifieds) path.** Migrated Jobs are typed as **Classifieds (marketType `Job`)** so `components/Listings.tsx:34-50` routes them to `GeneralListing`/`GeneralManage` and they inherit the full gated lifecycle above for free. This is a **migration data-contract decision**, not a UI rewrite. Legacy `JobManage` (already has Activate/Deactivate/Renew/Delete/Applications; lacks purge / mark-sold / mark-sale-pending) is retained for any non-migrated Jobs — no parity build needed.
- 🔨 Render Jobs-specific **card display** (pay range, employment type, etc.) within `GeneralListing` so migrated Jobs show their fields.
- 🔨 Status dropdown default is **"All"** today (`ListingsFilterStore.ts:352,460`); Notion wants **"Active"** — small change, both verticals. Add the "Deleted"/"All" 30-day purge banner.
- 🔨 Verify modal copy matches Notion (1-year Inactive, 30-day Deleted, privacy-statement Delete-No-Undo text).
- ❓ `classifiedsLifecycleGateOpen` comes from API meta — confirm whether a parallel Jobs gate is needed or Jobs launch under the same flag.
- No inline field editing — editing redirects to PAL (out of scope).

---

## 6. App (React Native — separate repo, not in research set; 2-week estimate, capacity unconfirmed)

### 6.1 SRP / Jobs Tab
- 🔨 Tapping Jobs tab auto-selects Jobs category + shows subcategory list (same as Services); remove Jobs from global search.

### 6.2 Detail Page
- 🔨 Hook unified detail page to render Jobs fields (pay range, Apply button).

### 6.3 PAL — now in scope
- 🔨 Render job-specific fields; use PAL endpoint for posting/editing; hard-code fields (similar to Cars). *(Notion now lists this in app scope; confirm with App team — Open Q6.)*

---

## Out of Scope
- 🚫 CX/Nest restore tool (now explicitly out for this migration)
- 🚫 Saved Search & Alerts for Jobs (Phase 3)
- 🚫 Quick Apply / Resume uploads / Virus scanning (Phase 4); the `ksl` Apply path is a **dummy** button this phase
- 🚫 Full migration of existing Jobs listings (Phase 3/5)
- 🚫 Replacing subcategory-spec model with semantic key/value filters
- 🚫 `jobApplicationDeadline` field (dropped); Company Perks (dropped)

---

## Open Blockers

| Blocker | Owner | Status |
|---------|-------|--------|
| MyAccount repo name (myaccount.ksl.com) | Chris | **Awaiting repo** — Chris to provide; add to project.json (Q5) |
| Archive DB design (net-new datastore + read/restore path) | Eng | Not started (Q4) |
| Legal sign-off on retention values (30d/1yr/1yr/6mo) | Legal | Values proposed, not signed off (Q3) |
| Web frontend developer not assigned | PM | Not started (Q7) |
| App team 2-week capacity + PAL scope | App | Not confirmed (Q6) |

*Resolved this session: Q1 (Jobs is a Category), Q2 (Detail read-only), Q8 (employment/education/experience are SRP-filterable).*
