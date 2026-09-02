# Detail Page Listing Service needs — Features

## Context

Members routed through the **new listing service** (`listing-http-rest`, gated by the
`use_listing_rest` member-id feature flag) get a degraded listing **detail page** compared
to members still served by legacy **CAPI** (the Classifieds API,
[`m-ksl-classifieds-api`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api)).
The GraphQL layer maps the new service's response into the `ClassifiedListing` model
([mapping.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/listing-rest/mapping.go)),
but several detail-page concerns are missing or incomplete. **The GraphQL→CAPI maps are set
up; the gap is full feature flow from `listing-http-rest`.** These must close **before the
Jobs launch**.

Most visible symptom: migrated members see a **view count of "0"** on every listing,
because the new service doesn't return page-view data the way CAPI (Memcache-backed) does.

**Appetite:** ~1 week (per Notion framing, status "FRAMED: OPS Approved").

### How routing works today (important — drives F1/F2)

- **Route is chosen by the VIEWER's member id**, not the listing owner's:
  [fetch-listing.go:21-37](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/queryresolvers/fetch-listing.go#L21-L37).
  Flagged viewers → `fetchClassifiedListingViaRest` (new service); everyone else → `fetchListingLegacy` (CAPI).
- **Jobs visibility gate:** [jobs_gate.go:14-57](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/queryresolvers/jobs_gate.go#L14-L57) →
  `shouldShowJobsMarketType` (matches `use_listing_rest` OR `show_jobs_market_type`; anonymous = false).
- **Shared storage:** both CAPI and listing-http-rest read/write the SAME Mongo collection —
  db `classifieds`, collection `general`
  ([CAPI GeneralCollection.php:35](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Db/Mongo/GeneralCollection.php#L35);
  [listing-http-rest mongo.go:14-15,67](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/store/mongo.go)).
  `"Job"` is already a known marketType in CAPI
  ([Listing.php:15](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Library/Model/Listing.php#L15)),
  and CAPI's `getListing()` has **no marketType filter**.
- **View-count read vs increment** (CAPI, Memcache key `slc-{id}-c`):
  read via `getPageViews`, increment via `incrementPageViews`
  ([ListingController.php:144-189](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ListingController.php#L144-L189);
  [StatHelper.php:84-106](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Helper/StatHelper.php#L84-L106)).
  The increment is **only** fired on the legacy CAPI-served path; the listing-rest path
  intentionally does **not** forward it
  ([fetch-listing.go:44-47](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/queryresolvers/fetch-listing.go#L44-L47)).

---

## F1 — View count parity for migrated non-Jobs listings (the bug fix)

**Problem:** `PageViews` is never populated on the `listing-rest` path — see the TODO at
[mapping.go:271-272](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/listing-rest/mapping.go#L271-L272).
Migrated members see `0`. Legacy CAPI populates it from Memcache
([capi/classifiedListing.go:418-420, 795](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/capi/classifiedListing.go)).

**Chosen solution (decided):** Keep using **CAPI for view data on all general classifieds
EXCEPT Jobs.** In `marketplace-graphql`, after fetching a listing via `listing-http-rest`,
make a **supplemental CAPI call** for `pageViews` (CAPI `getPageViews=1`, no increment) and
merge it into the mapped response. Stays in the BFF layer (already talks to both backends).

**Why this works for non-Jobs:** the count keeps accumulating because most views come from
non-flagged/anonymous viewers, who still hit the legacy CAPI path and fire the increment.
Flagged-viewer increments (currently lost on the rest path) are **also closed** by the F2
decision — graphql fires CAPI `incrementPageViews` on the rest path — so both read and
increment route through CAPI on every path.

**Acceptance:**
- Migrated (listing-rest) **non-Jobs** classifieds show accurate, CAPI-sourced view counts,
  matching what non-migrated members see.
- The supplemental CAPI call is scoped to non-Jobs market types only (see F2).
- CAPI call failure/latency degrades gracefully (no broken detail page; fall back to no count).

---

## F2 — Jobs view count: accumulate via CAPI (decided)

**Updated direction (from team):** We will **not migrate** any legacy Jobs view counts.
Jobs start at 0 and view counts **accumulate from CAPI over time** as listings get viewed —
*not* a permanent hard-hide.

**Feasibility findings:**
- ✅ We **can** fetch Jobs listing details and view counts from CAPI: Jobs live in the same
  `classifieds.general` collection, `"Job"` is a known CAPI marketType, and CAPI's fetch /
  `getPageViews` path is marketType-agnostic (no filtering).
- ⚠️ **The count only grows if the increment fires.** Today the increment fires only on the
  legacy CAPI-served path (chosen by the **viewer's** member id), so views from flagged
  viewers on the listing-rest path are lost.

**✅ DECISION (2026-06-30) — CAPI stays the view-count system of record (increment + read).**
We keep CAPI as the single mechanism for both **incrementing** and **retrieving** page views,
and we do **not** build view-counting into `listing-http-rest`. Instead, the listing-rest path
in `marketplace-graphql` is wired to CAPI for views:
- **Retrieval:** supplemental CAPI `getPageViews` call merged into the rest-mapped response
  (closes the [mapping.go:271-272](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/listing-rest/mapping.go#L271-L272) PageViews gap).
- **Increment:** honor the `incrementViewed` flag (currently dropped at
  [fetch-listing.go:44-47](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/queryresolvers/fetch-listing.go#L44-L47))
  by firing CAPI `incrementPageViews` on the rest path — reusing the existing CAPI counter
  (Memcache `slc-{id}-c`), **not** a new server-side counter.

This keeps one counting/storage mechanism across both serving paths and closes the
lost-increment gap for Jobs **and** all other migrated listings (so this subsumes the
flagged-viewer increment loss noted in F1). No interim "hide the count" is needed for Jobs,
since the count now accumulates from first view.

**Acceptance:**
- Jobs (and any migrated listing) served via listing-rest show CAPI-sourced view counts and
  the count **increments** on a real detail-page view (`incrementViewed: true`), matching the
  legacy path.
- View increment/read on the listing-rest path goes through CAPI; `listing-http-rest` gains
  no view-count logic.
- CAPI call failure/latency degrades gracefully (no broken detail page).

**Remaining sub-items:**
- **Own-listing self-views — RESOLVED (2026-06-30):** legacy CAPI has **no owner-exclusion
  guard** — the increment fires for everyone (incl. the listing owner) whenever the flag is
  set ([ListingController.php:177-182](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ListingController.php#L177-L182),
  [StatHelper.php:99-106](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Helper/StatHelper.php#L99-L106); graphql forwards `incrementViewed` unconditionally). So **parity =
  fire for everyone, no guard needed**. (Excluding owner self-views would be net-new behavior —
  only add a guard if product explicitly wants it.)
- **Perf budget:** latency of the supplemental CAPI read + increment per detail render — needs
  a real measurement / Platform input.

**Where view count renders today (frontend):**
- [ListingDetails.tsx:84-87](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/%5Bid%5D/components/ListingDetails.tsx#L84-L87) — eye icon + pageViews in header.
- [PageStatsFraud.tsx:38,68-70](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/%5Bid%5D/components/PageStatsFraud.tsx) — "Page Stats" card.

---

## F3 — Ribbon passthrough (detail-page parity, minus user-purchased)

**⚠️ Premise corrected (2026-06-30):** the original "Adopt Me, For Rent, Service, plus any
other" list conflated two different ribbon representations. They are distinct:
- **Detail page uses the singular `Ribbon` field.** CAPI's detail mapping
  ([classifiedListing.go:769-781](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/capi/classifiedListing.go#L769-L781))
  computes **only "❤️ Adopt Me"** (Pets + `adoptablePets`); otherwise it passes through the
  **stored** ribbon — which is the **user-purchased** ribbon (set in CAPI `PaymentHelper`),
  and that is **out of scope**.
- **"For Rent" / "Service" are the plural `Ribbons []string`**, built by the **search** path
  (unbxd [backend.go:1222-1250](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/search-http-rest/internal/domain/unbxd/backend.go#L1222-L1250)
  and [listing-service.go:621-650](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/listing-service/listing-service.go#L621-L650))
  for cards / SRP. They are **not** part of the CAPI detail-page singular ribbon.

**Finding:** The listing-rest detail mapping
([mapping.go:255-269](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/listing-rest/mapping.go#L255-L269))
**already synthesizes "❤️ Adopt Me"** with the same condition CAPI uses. The only CAPI branch
it omits is the stored-ribbon passthrough = the user-purchased ribbon (out of scope). So
**detail-page ribbon parity is effectively already met.**

**Remaining (small PM confirm, not a build):** Is detail-page **Adopt Me** parity sufficient,
or does the team also want the search-style **"For Rent" / "Service"** labels surfaced on the
**detail page**? The latter would be **net-new** behavior (legacy CAPI never showed them on
the detail-page ribbon) — a product decision, not a parity fix.

**Acceptance:**
- New-service detail pages show the **"❤️ Adopt Me"** ribbon at parity with CAPI (already
  implemented — verify the condition: `category == "Pets"` + `adoptablePets`).
- User-purchased ribbon text is intentionally **not** carried over.
- If the PM confirms For Rent/Service on the detail page is wanted, mirror the search-side
  conditions (`marketType == "Rent"` / `"Service"`) and keep them consistent with
  `unbxd/backend.go buildRibbons`.

---

## F4 — Rental Rules: verification & polish (not a build-out)

**⚠️ Reassessed (2026-06-30):** traced the full create→store→serve path in `listing-http-rest`.
The rental-rules feature is **~95% already built and working end-to-end** — F4 is
**predominantly verification + test coverage**, not a backend build-out.

**Verified WORKING (with evidence):**
- **Update (write):** `UpdateRequest.RentalRules *[]string`
  ([request.go:35](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/types/request.go#L35));
  applied via `buildChanges` three-state slice semantics
  ([update.go:271](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/domain/update.go#L271)).
- **Validation wired:** `ValidateRentalRules` (≤10 rules, ≤100 chars) called from the update
  validation rules ([validation.go:299-309](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/domain/validation.go#L299-L309)).
- **Market-type transition:** `clearRentalRulesIfNotRent` invoked in `buildChanges`
  ([update.go:303-314](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/domain/update.go#L303-L314)), with a test.
- **Store:** `ClassifiedListing.RentalRules` with bson tag round-trips to Mongo
  ([listing.go:1332](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/types/listing.go#L1332)).
- **Serve (read):** `ListingResponse.RentalRules` populated by `FromListing`, returned by GET
  ([response.go:79,305](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/types/response.go#L79); [get.go:54](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/handler/get.go#L54)).
- **Events:** `rentalRules` populated in raw + activated events from real data.
- **GraphQL mapping** copies through ([mapping.go:231-235](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/listing-rest/mapping.go#L231-L235)).

**Notes / true gaps:**
- **Create handler does not accept `rentalRules`** — by design (create makes a stub; rules are
  set on update). Confirm this matches the intended UX (no rules at create time).
- **Test coverage gap:** domain unit tests exist, but **no end-to-end/handler test** for
  create→update→GET→event including `rentalRules`, and no GET-response assertion for the field.
- **Frontend display verification** (already built for legacy):
  [ListingRentalRules.tsx](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/%5Bid%5D/components/ListingRentalRules.tsx)
  ("Owner Rules and Policies" icon-mapped defaults + "Additional Requirements"); confirm the 4
  predefined default strings still map to icons (`services/listing/schema/classifieds.ts` ~368-400).

**Acceptance:**
- Verify (don't rebuild) the full rental-rules flow end-to-end on the new service: update sets
  rules, GET returns them, events carry them, non-Rent transition clears them.
- Detail page renders default (icon-mapped) and custom rental rules for new-service rentals.
- Add the missing e2e/handler test coverage. **Estimated ~2–3 days**, not a full build sprint.

---

## F5 — Detail page showing Job fields

**Problem:** Job-specific fields are mapped through GraphQL
([mapping.go:43-49](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/listing-rest/mapping.go#L43-L49):
`jobsApplicationUrl`, `jobsPayRangeType`, `jobsPayFrom`, `jobsPayTo`, `jobsEmploymentType`,
`jobsYearsExperience`, `jobsEducationLevel`), already **fetched** by the frontend
([fetchListing.ts:244-250,282](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/%5Bid%5D/actions/fetchListing.ts))
and validated in the schema
([detail-listing.ts:144-150](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/services/listing/schema/detail-listing.ts)).
But they are **rendered nowhere** — zero references to these fields in any detail-page
component. Plumbing is ~done; only the presentation layer is missing.

**Decision (2026-06-30): no change to the current design.** The job fields are surfaced in
a **"Job Specifications"** section on the detail page using the **existing**
`ListingSpecifications` pattern — the same `SpecificationSection` rendering already used for
"Details" / "Vehicle Specifications" / "Appearance"
([ListingSpecifications.tsx](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/%5Bid%5D/components/ListingSpecifications.tsx)).
No dedicated "Job Details" component, no net-new layout, **no Design dependency**.

**Remaining build work (no longer blocked):** map the already-plumbed job fields
(`jobsPayRangeType`, `jobsPayFrom`, `jobsPayTo`, `jobsEmploymentType`, `jobsYearsExperience`,
`jobsEducationLevel`, `jobsApplicationUrl`) into a "Job Specifications" `SpecificationSection`
(label/format each value in the existing spec style). Legacy reference for field
labels/formatting: [`m-ksl-jobs`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs).

**Acceptance:**
- Job listings render their job-specific fields in a "Job Specifications" section on the
  detail page, using the existing specifications design.
- Labels/formatting match the existing specification style; no bespoke layout introduced.
