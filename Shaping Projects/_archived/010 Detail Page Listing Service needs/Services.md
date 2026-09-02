# Detail Page Listing Service needs — Services

Services / repos created or updated, by feature (see [Features.md](Features.md)).

---

## marketplace-graphql (BFF layer)

The convergence point — both CAPI and listing-http-rest responses are mapped here.

| Area | File | Change |
|------|------|--------|
| View-count read (F1/F2) | [services/listing-rest/mapping.go:271-272](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/listing-rest/mapping.go#L271-L272) | Resolve the `PageViews` TODO: after the rest fetch, make a supplemental CAPI `getPageViews` call and merge — for **all** market types incl. Jobs (CAPI is the system of record). |
| View read + increment wiring (F1/F2) | [graph/queryresolvers/fetch-listing.go:39-95](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/queryresolvers/fetch-listing.go#L39-L95) | `fetchClassifiedListingViaRest` — add the supplemental CAPI page-view **read**, and **honor `incrementViewed`** (currently dropped at `:44-47`) by firing a CAPI `incrementPageViews` call on the rest path. |
| Ribbon passthrough (F3) | [services/listing-rest/mapping.go:255-269](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/listing-rest/mapping.go#L255-L269) | **Reassessed (2026-06-30): detail-page parity effectively met.** CAPI's detail singular `Ribbon` computes only "❤️ Adopt Me" (else user-purchased passthrough, out of scope); listing-rest already synthesizes Adopt Me. "For Rent"/"Service" are plural search-side `Ribbons`, not detail-page. **Remaining: PM confirm** whether to also surface For Rent/Service on the detail page (net-new vs legacy). |
| Reference: CAPI client | [services/capi/classifiedListing.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/capi/classifiedListing.go) | Existing `getPageViews`/`incrementPageViews` behavior to reuse from the rest path (`incrementPageViews` param at ~399); ribbon behavior to mirror. |

> Note: an unrelated uncommitted change exists locally in
> `graph/queryresolvers/legacy-searchfilters-classifieds.go` (search "Listing Type" filter) —
> **not part of this project**; flagged so it isn't conflated with this work.

---

## marketplace-backend → listing-http-rest (new listing service)

| Area | Path | Change |
|------|------|--------|
| Rental Rules — **verify, not build** (F4) | `apps/listing/services/listing-http-rest/internal/{types,domain,store,pubsub,handler}` | **Reassessed (2026-06-30): ~95% built & working.** Update (`request.go:35` + `update.go:271` buildChanges), validation (`validation.go:299-309`), transition (`update.go:303-314` `clearRentalRulesIfNotRent`), store (`listing.go:1332` bson), serve (`response.go:79,305` + `get.go:54`), and events all work. **Remaining: add e2e/handler tests; confirm create-time has no rules by design. ~2–3 days.** |
| Page-view increment — **no change** (F2 decided) | `apps/listing/services/listing-http-rest` GET `/listing/{id}` | **Decided: do NOT build view-counting here.** CAPI stays the system of record; the increment is fired from marketplace-graphql via CAPI `incrementPageViews` on the rest path. No new server-side increment param. |
| Reference: shared storage | `internal/store/mongo.go:14-15,67` | Confirms new service writes to db `classifieds`, collection `general` (same as CAPI) — basis for F1/F2 feasibility. |
| Reference: Jobs types | `internal/types/listing.go` (`MarketTypeJob`, `Jobs*` fields, `JobsPayRangeType`) | Source of the job fields surfaced in F5. |

---

## marketplace-frontend (detail page UI)

| Area | File | Change |
|------|------|--------|
| View count display (F2) — **no change needed** | [ListingDetails.tsx:84-87](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/%5Bid%5D/components/ListingDetails.tsx#L84-L87), [PageStatsFraud.tsx](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/%5Bid%5D/components/PageStatsFraud.tsx) | F2 decided to accumulate via CAPI, so **no interim hide**. Jobs show a real (initially low) count that grows. Frontend already tolerates null (`?? 0`); no change required. |
| Job fields rendering (F5) | [ListingSpecifications.tsx](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/%5Bid%5D/components/ListingSpecifications.tsx) (+ spec mapping in `config/classifieds-config.tsx`) | **Decided (2026-06-30): no design change.** Map the already-plumbed job fields into a **"Job Specifications"** `SpecificationSection` using the existing pattern (as with "Details"/"Vehicle Specifications"). No new component, no Design dependency. |
| Rental rules display verify (F4) | [ListingRentalRules.tsx](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/%5Bid%5D/components/ListingRentalRules.tsx); defaults transform `services/listing/schema/classifieds.ts` (~368-400) | Verify default-rule icon mapping + custom requirements render for new-service rental listings. |
| Reference: data already plumbed | [actions/fetchListing.ts](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/%5Bid%5D/actions/fetchListing.ts), [schema/detail-listing.ts](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/services/listing/schema/detail-listing.ts) | Jobs fields, rentalRules, ribbon, pageViews all already queried + schema-validated. |

---

## m-ksl-classifieds-api (CAPI — Legacy, reference only)

Legacy reference; no new dev here, but it's the source-of-truth being mirrored.

| Concern | File |
|---------|------|
| Listing fetch (no marketType filter) | [GeneralCollection.php:35-67](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Db/Mongo/GeneralCollection.php#L35-L67) |
| getPageViews / incrementPageViews | [ListingController.php:144-189](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ListingController.php#L144-L189) |
| Page-view Memcache (`slc-{id}-c`) | [StatHelper.php:84-106](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Helper/StatHelper.php#L84-L106) |
| Ribbon model field + marketTypes (incl. Job) | [Listing.php:15,109-110](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Library/Model/Listing.php) |

---

## Open / pending-decision services

- **F2 increment path:** ✅ **DECIDED (2026-06-30)** — CAPI is the view-count system of record
  for both read and increment; the work lives entirely in marketplace-graphql (supplemental
  CAPI `getPageViews` + `incrementPageViews` on the rest path). `listing-http-rest` is
  unchanged. **Own-listing parity resolved** (no owner guard in legacy → none needed).
  **Remaining open: perf budget** of the supplemental call (needs measurement).
- **F5 job-fields UI:** ✅ **DECIDED (2026-06-30)** — no design change; "Job Specifications"
  section via existing spec rendering. No PM/Design dependency.
- **F3 ribbons:** ✅ detail-page parity effectively met (Adopt Me). **Small PM confirm** only:
  whether to also surface For Rent/Service on the detail page (net-new vs legacy).
- **F4 rental rules:** ✅ reassessed as verification + tests (~2–3 days), not a build-out.
