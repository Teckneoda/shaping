# Planning State — Detail Page Listing Service needs

## Identified So Far

The project closes **detail-page parity gaps for listings served by the new listing
service** (`listing-http-rest`, gated by `use_listing_rest`, routed by the **viewer's**
member id). All paths converge in `marketplace-graphql/services/listing-rest/mapping.go`.
Five workstreams (detail in [Features.md](Features.md)):

- **F1 — View count fix (non-Jobs):** Supplemental CAPI `getPageViews` call in
  marketplace-graphql, merged into the rest-mapped response. Decided: keep CAPI as the
  view-data source for all classifieds except Jobs. `PageViews` TODO at `mapping.go:271-272`.
- **F2 — Jobs view count:** CONFIRMED feasible to fetch Jobs + view counts from CAPI (shared
  `classifieds.general` Mongo collection; `"Job"` is a known CAPI marketType; no marketType
  filter on CAPI fetch). BUT counts only grow if the page-view **increment** fires for Jobs —
  and the increment only fires on the legacy CAPI-served path, never on the listing-rest path
  (intentional: `fetch-listing.go:44-47`). Open decision on how Jobs accumulate views.
- **F3 — Ribbon passthrough:** Expand rest mapping's ribbon synthesis (currently Adopt Me
  only) to full CAPI parity (Adopt Me, For Rent, Service, …) **minus** user-purchased ribbons
  (no longer purchasable at checkout). `mapping.go:255-269`.
- **F4 — Rental Rules:** Build out the **full feature flow in listing-http-rest** (not just
  the existing GraphQL passthrough). Backend type/validation/transition pieces exist; needs
  complete end-to-end flow + frontend display verification.
- **F5 — Job fields on detail page:** Data is fully plumbed (GraphQL mapped, frontend fetched
  + schema-validated) but **rendered nowhere**. Net-new UI. Layout pending PM + Design.

### Key architecture facts established
- CAPI and listing-http-rest share storage: db `classifieds`, collection `general`.
- Route chosen by **viewer's** member id (`fetch-listing.go:21-37`), not listing owner's.
- Jobs visibility gate: `jobs_gate.go` `shouldShowJobsMarketType` (anonymous = false).
- **View-count trigger — verified 3-layer trace** (it is a side effect of the listing fetch,
  gated by a single `incrementViewed` boolean, honored only on the legacy CAPI path today):
  - **Frontend** sets the flag, doesn't count itself: `incrementViewed: true` on real detail
    render (`marketplace-frontend .../listing/[id]/page.tsx:155`; `:63` passes `false` for
    metadata to avoid double-count). It rides the existing `fetchListing` GraphQL query as a
    variable (`.../actions/fetchListing.ts:21,74`). No `useEffect`/beacon/separate mutation —
    frontend only reads & displays the count.
  - **marketplace-graphql** routes the flag by viewer member id (`fetch-listing.go:21-37`).
    Legacy path forwards it → CAPI `getPageViews=1` + `incrementPageViews=1` query params
    (`services/capi/classifiedListing.go:395-422`). listing-rest path **intentionally drops**
    it (`fetch-listing.go:44-47`); PageViews not read back either (TODO `mapping.go:271-272`).
  - **Backend** — legacy CAPI: `ListingController.php:177-182` → `StatHelper::incrementListing
    DetailPageViews` → `++` on **Memcache key `slc-{id}-c`** (`StatHelper.php:99-106`); read =
    same key (`:84-90`). **Memcache only — no Mongo persistence, no IP/session dedupe, no cap.**
    New `listing-http-rest` has **no** view-count logic (no param, no `pageViews` field, no
    stat recording — `internal/handler/get.go`, `internal/types/response.go`).

## Still Needs Research
- F5: ~~exact job fields, ordering, labels, formatting, placement — blocked on PM/Design~~
  **RESOLVED (2026-06-30): no design change — fields shown in a "Job Specifications" section
  via the existing `ListingSpecifications` pattern.** Remaining build work: map the plumbed
  job fields into that spec section (labels/format per existing spec style; `m-ksl-jobs` ref).
- F4: ~~confirm what's incomplete vs working end-to-end~~ **RESOLVED (2026-06-30): ~95% built;
  F4 is verification + test coverage, not a build-out.** Update/validate/store/serve/events all
  work; gaps are missing e2e/handler tests and confirming create-time has no rules by design
  (~2–3 days). See Q4.
- F3: ~~enumerate full CAPI ribbon set~~ **RESOLVED (2026-06-30): detail-page singular `Ribbon`
  = only "Adopt Me" in CAPI (else the user-purchased passthrough, out of scope); listing-rest
  already synthesizes Adopt Me → parity effectively met.** "For Rent"/"Service" are the plural
  search-side `Ribbons`, not detail-page. See Q3 (small PM confirm remains).
- F2: ~~own-listing increment parity~~ **RESOLVED (2026-06-30): legacy CAPI has no owner
  self-view guard — increment fires for everyone; parity = no guard needed.**
- F1/F2 (still open): exact supplemental-CAPI call shape / **perf budget** for the page-view
  read **and** the increment now fired on the rest path (latency added per detail render).
- F2 (no longer blocks accumulation): whether non-flagged/anonymous viewers can open a Job
  detail page is moot for counting (increment fires from the rest path via CAPI regardless) —
  still worth confirming for traffic-mix/perf expectations.

## Unanswered Questions
1. ~~**Jobs view-count accumulation (F2)**~~ — **RESOLVED (2026-06-30): CAPI stays the
   view-count system of record for both increment and retrieval.** We do **not** build
   view-counting into `listing-http-rest`. The listing-rest path in `marketplace-graphql` is
   wired to CAPI: supplemental `getPageViews` (read) merged into the rest-mapped response, and
   CAPI `incrementPageViews` fired on the rest path honoring the `incrementViewed` flag
   (currently dropped at `fetch-listing.go:44-47`), reusing the existing Memcache `slc-{id}-c`
   counter. This closes the lost-increment gap for Jobs **and** all migrated listings, so no
   interim "hide the count" is needed. Remaining sub-items: **perf budget** of the supplemental
   CAPI call (latency per render — still open). Own-listing self-view parity is **resolved** —
   legacy CAPI has no owner-exclusion guard, so parity = fire for everyone (no guard needed).
2. ~~**Job fields UI (F5)**~~ — **RESOLVED (2026-06-30): no change to the current design.**
   Job fields are shown in a **"Job Specifications"** section on the detail page using the
   existing `ListingSpecifications` / `SpecificationSection` pattern (same as
   "Details"/"Vehicle Specifications"). No dedicated component, no net-new layout, **no Design
   dependency.** Remaining build work: map the plumbed job fields into that spec section.
3. ~~**Ribbon set (F3)**~~ — **RESOLVED (2026-06-30):** the "Adopt Me / For Rent / Service"
   list conflated two representations. **Detail page** uses the singular `Ribbon`, which CAPI
   computes as **only "❤️ Adopt Me"** (else the stored user-purchased ribbon — out of scope);
   listing-rest **already** synthesizes Adopt Me, so **detail-page ribbon parity is effectively
   met.** "For Rent"/"Service" are the **plural search-side `Ribbons`** (unbxd `buildRibbons` +
   listing-service), not the detail-page ribbon. **Remaining: small PM confirm** — is Adopt-Me
   parity enough, or does the team also want For Rent/Service on the *detail* page (net-new vs
   legacy)?
4. ~~**Rental Rules (F4)**~~ — **RESOLVED (2026-06-30): mostly verification, not a build-out.**
   Update/validate/store/serve/events all work end-to-end in `listing-http-rest`; the gaps are
   missing e2e/handler test coverage and confirming "no rules at create time" is intended.
   Scope ≈ **2–3 days** (verify + tests), not a full build.
5. ~~Appetite/scope~~ — **Re-scoped (2026-06-30): the ~1-week appetite now looks comfortable.**
   F5 needs no Design and no net-new UI; F3 is essentially done (Adopt Me); F4 is verification
   (~2–3 days), not a build-out. Remaining real work: wire the F2 CAPI read+increment on the
   rest path (F1/F2), the F5 spec-mapping, and F4 verification/tests. **Open dependencies:** F2
   perf budget (measurement), and the small F3 PM confirm.

## Research Sources Consulted
- **Notion:** [Detail Page Listing Service Needs](https://app.notion.com/p/deseret/Detail-Page-Listing-Service-Needs-37c2ac5cb23580e5874ae70f4d505b97) — framing, problem statement, chosen Solution #2, 1-week appetite, "FRAMED: OPS Approved".
- **marketplace-graphql** (synced to origin/main): `services/listing-rest/mapping.go`,
  `graph/queryresolvers/fetch-listing.go`, `jobs_gate.go`, `listing_rest_gate.go`,
  `services/capi/classifiedListing.go`, `legacy-listing.go`.
- **marketplace-frontend** (synced to origin/main): detail page `components/` (ListingDetails,
  PageStatsFraud, ListingRentalRules, ListingSpecifications), `config/classifieds-config.tsx`,
  `actions/fetchListing.ts`, `services/listing/schema/detail-listing.ts`, `schema/classifieds.ts`.
- **marketplace-backend** → `apps/listing/services/listing-http-rest` (`internal/store/mongo.go`,
  `internal/types/listing.go`, `internal/domain/{validation,update}.go`, `internal/pubsub/*`);
  `search-http-rest` (`unbxd/backend.go buildRibbons`).
- **Legacy/m-ksl-classifieds-api (CAPI):** `GeneralCollection.php`, `ListingController.php`,
  `StatHelper.php`, `Library/Model/Listing.php`, `Library/KSL/Classified.php`.

## Sync / Repo Notes
- `marketplace-backend`, `marketplace-frontend`: clean, pulled to origin/main.
- `marketplace-graphql`: pulled; has an **unrelated uncommitted local change** in
  `graph/queryresolvers/legacy-searchfilters-classifieds.go` (search "Listing Type" filter) —
  not part of this project. Flagged, not touched.
- `m-ksl-classifieds-api` (CAPI) is the legacy repo at `Research Repos/Legacy/m-ksl-classifieds-api`
  (read-only reference).

## Changelog
- 2026-06-30: Initial shaping session. Established the five workstreams (F1–F5); confirmed
  shared `classifieds.general` storage and the view-count increment gap; reframed F2 from
  "hide view count" to "Jobs view counts are feasible from CAPI but gated on the increment
  path"; flagged F5 (job-fields UI) and F4 (rental-rules backend flow) as the open scope.
- 2026-06-30: **Resolved Q3, Q4, and the F2 own-listing sub-item via code research.**
  - **Q3 (ribbons):** detail-page singular `Ribbon` in CAPI computes only "❤️ Adopt Me" (else
    stored/user-purchased passthrough, out of scope); listing-rest already does Adopt Me →
    detail-page parity effectively met. "For Rent"/"Service" are plural search-side `Ribbons`
    (unbxd `buildRibbons` + listing-service), not detail-page. Remaining: small PM confirm.
  - **Q4 (rental rules):** ~95% built; verification + missing e2e/handler tests, not a
    build-out (~2–3 days). Update/validate/store/serve/events all confirmed working.
  - **F2 own-listing:** legacy CAPI has no owner self-view guard → parity = fire for everyone.
  - Re-scoped Q5: ~1-week appetite now comfortable (F3 ~done, F4 verification, F5 no design).
  - Updated Features.md (F2/F3/F4), Services.md, and Notion accordingly.
- 2026-06-30: **Resolved Q2 (F5 job-fields UI)** — no change to the current design; job
  fields are shown in a "Job Specifications" section using the existing `ListingSpecifications`
  pattern (no dedicated component, no Design dependency). Remaining F5 work is mapping the
  plumbed job fields into that spec section. Updated Features.md/Services.md/Notion; re-scoped
  Q5 (F5 no longer the slip risk — F4 is). 
- 2026-06-30: Traced the view-count trigger end-to-end (frontend `incrementViewed` flag →
  graphql routing by viewer member id → CAPI Memcache `slc-{id}-c`; new `listing-http-rest`
  has no view logic). **Resolved Q1/F2: CAPI stays the view-count system of record for both
  increment and retrieval** — the listing-rest path in graphql gets a supplemental CAPI
  `getPageViews` (read) and fires CAPI `incrementPageViews` (honoring `incrementViewed`),
  rather than building view-counting into listing-http-rest. Updated Features.md F1/F2 and
  Services.md accordingly.
