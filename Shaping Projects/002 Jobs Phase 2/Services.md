# Jobs Phase 2 — Services

Services created or updated for Phase 2. **Legend:** ✅ Built · 🔨 Gap · ❓ Open · 🚫 Out of scope. File:line refs are against the synced research repos (2026-06-25).

---

## Architecture Overview

```
Web (Next.js, apps/ksl-marketplace)  ·  MyAccount app (myaccount.ksl.com — separate repo)  ·  App (React Native — separate repo)
    ↓ GraphQL
marketplace-graphql (gateway: feature gates, SRP filters, detail fields, lifecycle mutations)
    ↓ REST
marketplace-backend/apps/listing/services/
    ├── listing-http-rest   (CRUD, GET detail, lifecycle action endpoints)
    ├── search-http-rest     (dedicated SRP search service — ES query building)
    ├── listing-mcs-netcore  (Mongo change streams → ES sync)
    └── listing-cron-*        (auto-renew, soft-delete[skeleton], boosts, stats)
MongoDB → (connector) → Elasticsearch ;  Archive DB = 🔨 net-new
```

---

## 1. listing-http-rest (Go REST API)

**Location:** `marketplace-backend/apps/listing/services/listing-http-rest`

### Mostly built (Phase 1)
- ✅ Model: statuses incl. `Inactive`/`Expired`/`Deleted` (`internal/types/listing.go:31-40`); `MarketTypeJob` (`:51`); all 7 Jobs fields (`:1316-1323`); `DeletedAt` + `DeactivatedAt` (`:1326-1327`)
- ✅ Lifecycle guards (`listing.go:125-166`)
- ✅ `GET /listing/{id}` returns all Jobs fields + `listingType` (`internal/handler/get.go`, `internal/types/response.go`)
- ✅ Action endpoints (`routes.go`): `PUT .../mark-sold`, `.../mark-sale-pending`, `DELETE /listing/{id}` (soft delete), `PUT .../deactivate`, `.../renew`, `POST .../request-activation`, `PUT .../draft` (restore-to-draft), `DELETE .../purge`
- ✅ Renew = 30-day window + 14-day tail (`internal/domain/renew.go:19-21`) → 14-day interval already enforced

### Gaps
- 🔨 **Soft-delete / archive lifecycle logic** — see `listing-cron-soft-delete` (§4) and Archive DB (§6); confirm ES exclusion on soft delete/deactivate.
- ❓ Verify `markListingSold`/`makeListingAvailable` path for Jobs (GraphQL side is CAPI-only today).

---

## 2. search-http-rest (dedicated SRP search service)

**Location:** `marketplace-backend/apps/listing/services/search-http-rest`

- ✅ `marketType=Job` filtering (same-index).
- ✅ Pay-range custom filter mapping (`internal/config/filter.go:223-250`) + overlap logic (`internal/store/elastic/query.go` `generateJobsPayRangeFilters`).
- ✅ SRP response carries pay-range fields (`internal/api/classified-listing.go`).
- 🔨 **ES model missing** `jobsEmploymentType`/`jobsEducationLevel`/`jobsYearsExperience` (`internal/store/elastic/model.go` only has applicationUrl + payRangeType + pay agg).
- 🔨 **Filter config missing** the 3 string filters (`config/filter.go` only has payRangeType/From/To). GraphQL exposes the filter groups but nothing backs them in ES yet — close this loop (Open Q8).

---

## 3. marketplace-graphql (gateway)

**Location:** `marketplace-graphql`

- ✅ Feature-flag infra w/ member-ID allowlist (`graph/queryresolvers/featureconfig.go`, `remoteconfig.go`); Jobs gates (`jobs_gate.go`).
- ✅ `Job` as gated `marketType` (`classifieds-conditional-fields.go:59-61`).
- ✅ Jobs SRP filter groups (`jobs_srp_filter_groups.go`).
- ✅ Jobs detail fields in schema (`graph/schema/types.listings.graphqls:987-1013`).
- ✅ Lifecycle mutations → listing-http-rest (`mutationresolvers/classifieds_listing_lifecycle.go`): `deactivateClassifiedsListing`, `renewClassifiedsListing`, `softDeleteClassifiedsListing`, `restoreClassifiedsListingToDraft`, `purgeClassifiedsListing`.
- 🔨 If Jobs is a **category** (not just marketType): add category-level gating/creation (Open Q1).
- ❓ `markListingSold`/`makeListingAvailable` are CAPI-only (`mutationresolvers/listing-status.go`) — wire listing-http-rest if Jobs needs it.

---

## 4. Lifecycle Crons

**Location:** `marketplace-backend/apps/listing/services/listing-cron-*`

- ✅ Present: `listing-cron-auto-renew`, `listing-cron-boosts`, `listing-cron-stats`.
- 🔨 `listing-cron-soft-delete` — **scaffolded but not implemented**: has `internal/client`, `internal/types` (candidate, summary, config; ~600 LOC) but `app.go` run loop is empty (15 lines). Build the candidate-query + status-transition + archive-move logic.
- 🔨 Crons required (Notion): Deleted→Archive @30d; Inactive→Archive @1yr; Expired→Archive @1yr (only listings ≥30d in that status); Stub→Archive @2wk.
- 🔨 Auto-**Expire** process — confirm whether it lives in `listing-cron-auto-renew`.
- ❓ Archived→hard purge @6mo (existing `purge` endpoint vs separate job).

---

## 5. Elasticsearch / Mongo Connector

- ✅ Indexed Jobs fields: applicationUrl, payRangeType, payFrom, payTo; `marketType=Job`.
- 🔨 Add mappings: `jobsEmploymentType`, `jobsEducationLevel`, `jobsYearsExperience`.
- 🔨 `listing-mcs-netcore` (Mongo change streams → ES): sync the 3 string fields.
- 🔨 Ensure soft-deleted / deactivated / expired listings excluded from search (remove-on-transition or filter-by-status — confirm existing pattern).

---

## 6. Archive DB 🔨 (net-new)

- 🔨 No archive datastore/collection or `archive` concept exists in the codebase today.
- 🔨 Design: target store (separate collection vs separate DB), write path (cron move), read/restore path, 6-month retention then purge.
- ❓ Q4 — ownership + design decision needed before build.

---

## 7. Category Manager (Admin)
- ❓ Confirm Jobs as Category w/ ~40 industry subcategories (Q1).
- 🔨 If so: create category + subcategories; no specs needed (top-level fields); publish behind flag.

---

## 8. Frontend — Web (Next.js, `apps/ksl-marketplace`)

**Requires frontend developer (not assigned)**

- ✅ SRP: Jobs pay-range card, visibility utils, pay-range formatting (`app/components/Filters/Cards/JobsPayRange.tsx`, `utils/jobs-listing-type.ts`, `utils/jobs-pay-range.ts`).
- ✅ Detail schema has Jobs fields + `jobsApplicationMethod: ksl|url` (`services/listing/schema/classifieds.ts:113-148`).
- 🔨 SRP: wire term filters once ES backs them; finalize Jobs listing-type option; (NTH) list view.
- 🔨 Detail: build Jobs display section + two-variant Apply button (`app/listing/[id]/config/classifieds-config.tsx`, `ActionButtons.tsx`).

---

## 9. MyAccount app (`deseretdigital/m-ksl-myaccount-v2`)

**Stack:** Next.js 15 + MobX + SWR; calls own `/api/v1/listings/...` REST routes (not GraphQL directly). Default branch `master`. Hosted at myaccount.ksl.com/listings.

- ✅ **Classifieds lifecycle UI already built** behind `classifiedsLifecycleGateOpen` (`stores/listings/ListingsFilterStore.ts`, `components/Listing/Manage/GeneralManage.tsx`): Deactivate, soft Delete, Activate (restore-to-draft → checkout, `GeneralActivateModal`), Delete-No-Undo purge (`GeneralPurgeModal`), Mark Sold/Sale Pending, Renew, and status dropdown w/ Inactive/Expired/Deleted (gated).
- ✅ Lifecycle REST endpoints wired: `deactivate`, `DELETE` (soft), `restore-draft`, `purge`, `renew`, `sold` (`requests/general-*.ts`).
- ✅ **Q9 resolved → General path.** Migrated Jobs are typed as **Classifieds (marketType `Job`)** so `components/Listings.tsx:34-50` routes them to `GeneralListing`/`GeneralManage`, inheriting the full gated lifecycle. Data-contract decision in the migration — not a UI rewrite. Legacy `JobManage` (which already has Activate/Deactivate/Renew/Delete/Applications but no purge / mark-sold / mark-sale-pending / subscription-cancel) is retained for non-migrated Jobs.
- 🔨 Remaining (General path): render Jobs-specific card fields (pay range, employment type) within `GeneralListing`; status dropdown default "All" → "Active" (`ListingsFilterStore.ts:352,460`); add purge banner; verify modal copy vs Notion. `JobApplicationsModal` = Phase 4.

---

## 10. App (React Native — separate repo, not in research set)
- 🔨 Jobs tab (auto-select category + subcategories); remove Jobs from global search.
- 🔨 Detail page Jobs fields + Apply button.
- 🔨 PAL job fields (hard-coded like Cars) — now in scope (Q6).

---

## Services NOT changed in Phase 2
- `listing-applications` (Quick Apply — Phase 4)
- `listing-feed-parser` / `listing-feed-subscriber` (feed ingestion)
- `listing-cron-boosts` / `listing-cron-stats`
- Saved Search services (Phase 3)
- 🚫 Nest CX restore tool (out of scope)
