# Jobs to Classifieds - Phase 3.2 — Services

## Services to Update

### 1. CAPI — m-ksl-classifieds-api (No Changes Needed)

**Purpose:** Jobs saved searches flow through the existing Classifieds path as-is.

**Why no changes:** CAPI hardcodes `vertical: "general"` which is correct — Jobs listings are now general Classifieds listings with `marketType: "Job"`. The KSL API downstream stores `searchParams` as a JSON blob with minimal validation, so Jobs-specific fields (pay range, employer status, education, etc.) pass through without modification. KSL API publishes `SavedSearchEvent v5` to PubSub on create/update, keeping the percolation pipeline in sync.

**Key Files (reference only):**
- [SavedSearchHelper.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Helper/SavedSearchHelper.php) — `vertical: "general"` at lines 96, 158, 380 (correct as-is)
- [SavedSearchesController.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/common/api/controllers/SavedSearchesController.php) — Unified KSL API handler
- [SavedSearch.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/common/api/models/SavedSearch.php) — Model with JSON pass-through and PubSub publishing

---

### 2. marketplace-graphql (Update)

**Purpose:** Extend `saveSavedSearch` mutation to support Jobs listing type, routing through CAPI.

**Changes:**
- Add `ListingTypeJob` case to `SaveSavedSearch` resolver
- Add `JobsFilterConfig` in `config.go` with Jobs-specific filter definitions
- Add `MapJobsSavedSearchParams()` helper for Jobs filter → CAPI format mapping
- Skip cents→dollars conversion in `prepareRangeFiltersParams()` for salary/hourly fields
- Route Jobs requests to CAPI `/saved-searches/` with vertical parameter

**Key Files:**
- [legacy-savedsearch.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/legacy-savedsearch.go) — Add Jobs case (lines 70-128)
- [legacy-savedsearch-helper.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/legacy-savedsearch-helper.go) — Add Jobs param mapper
- [config.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/config/config.go) — Add JobsFilterConfig (after line 363)

---

### 3. saved-search-percolation (Update)

**Purpose:** Extend the Classifieds ES mapping and query generation to support Jobs-specific fields. Remove unfinished Jobs-specific code.

**Changes:**
- **Add to Classifieds ES mapping** ([mappings/classifieds.json](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-percolation/mappings/classifieds.json)):
  - `salaryFrom`, `salaryTo`, `hourlyFrom`, `hourlyTo` (float)
  - `payRangeType` (keyword)
  - `employerStatus` (keyword), `educationLevel` (integer), `yearsOfExperience` (integer)
  - `companyPerks` (text)
- **Update ClassifiedSavedSearch struct** in [services/classifieds.go](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-percolation/services/classifieds.go) with new fields
- **Add query filters** for pay range overlap matching (port logic from `services/jobs.go`)
- **Remove** Jobs-specific code:
  - [services/jobs.go](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-percolation/services/jobs.go) — Delete (unfinished)
  - [mappings/jobs.json](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-percolation/mappings/jobs.json) — Delete
  - Jobs case in [services/elastic.go](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-percolation/services/elastic.go) — Remove

---

### 4. saved-search-match-service (Update)

**Purpose:** Ensure Classifieds query documents include Jobs fields when percolating.

**Changes:**
- Add to Classifieds expected fields in [verticalexpectedfields/fields.go](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-match-service/verticalexpectedfields/fields.go):
  - `salaryFrom`, `salaryTo`, `hourlyFrom`, `hourlyTo`, `payRangeType`
  - `employerStatus`, `educationLevel`, `yearsOfExperience`, `companyPerks`
- Update query document creation in [queryDoc.go](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-match-service/queryDoc.go) to extract these fields from Jobs listings
- **Remove** Jobs-specific expected fields and query doc handling (replaced by Classifieds flow)

---

### 5. saved-search-alert-workers (Update)

**Purpose:** Update Classifieds matching config to handle Jobs-specific fields.

**Changes in [Config.php](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-alert-workers/src/Library/SavedSearch/Config.php):**
- Add to Classifieds `range-fields`: `salary` (salaryFrom/salaryTo) and `hourly` (hourlyFrom/hourlyTo) with two-field overlap logic
- Add to Classifieds `exact-match-fields`: `employerStatus`, `educationLevel`, `yearsOfExperience`, `payRangeType`
- Add to Classifieds `array-contains-fields`: `companyPerks` (type: "any")
- **Remove** Jobs-specific config and matching classes:
  - [SearchMatchJobsClass.php](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-alert-workers/src/Library/SavedSearch/SearchMatchJobsClass.php) — Delete
  - Jobs section in Config.php — Remove

---

### 6. MyAccount v2 — m-ksl-myaccount-v2 (Update)

**Purpose:** Update saved search UI to support Jobs fields within the Classifieds form.

**Changes:**
- [EditGeneral.tsx](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/components/SavedSearch/Modals/EditGeneral.tsx) — Conditional Jobs fields when `marketType === "Job"` or Jobs category selected
- [Criteria.tsx](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/components/SavedSearch/Criteria.tsx) — Display labels for pay range fields
- [saved-searches.ts](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/constants/saved-searches.ts) — Add Jobs fields to `FIELD_PRIORITY`
- [/pages/api/v1/saved-search/](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/pages/api/v1/saved-search/) — Wire Jobs vertical to CAPI
- Reference: [EditJob.tsx](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/components/SavedSearch/Modals/EditJob.tsx) (existing Jobs form, 446 lines) for field implementation patterns

---

### 7. Migration Script (New)

**Purpose:** One-time migration of ~12,000 legacy Jobs saved searches into the Classifieds system.

**Implementation:**
- Read from legacy MongoDB `jobsSavedSearch` collection
- Transform to Classifieds format: add `marketType: "Job"`, write to `generalSavedSearch`
- Index into `classifieds-ss-queries` ES percolation index
- Publish `SavedSearchEvent` (type: CREATED, type: CLASSIFIED) for each to trigger re-indexing
- Validation: count comparison, criteria spot-checks
- Runs after Phase 3.1 is live
- Pattern to follow: [populate/main.go](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-percolation/populate/main.go)

---

## Cleanup (Remove)

After migration is complete:
- `jobs-ss-queries` ES index — delete
- `jobsSavedSearch` MongoDB collection — archive then delete
- `jobsMatchedAlerts` MongoDB collection — archive then delete
- Jobs-specific code in percolation, match service, alert workers (listed above)
- Legacy m-ksl-jobs saved search frontend paths

---

## System Architecture

```
                   ┌─────────────────┐
                   │   Frontend      │
                   │  (SRP/MyAcct)   │
                   └────────┬────────┘
                            │ GraphQL
                   ┌────────▼────────┐
                   │ marketplace-    │
                   │ graphql         │
                   └────────┬────────┘
                            │ REST API
                   ┌────────▼────────┐
                   │ CAPI            │◄── Migration Script
                   │ (classifieds    │    (one-time, writes to
                   │  API)           │     generalSavedSearch +
                   └────────┬────────┘     classifieds-ss-queries)
                            │ KSL API
                            │ vertical: "general"
                            │ marketType: "Job"
                            ▼
                   ┌─────────────────┐
                   │ KSL API         │──► MongoDB: generalSavedSearch
                   │ (persistence)   │──► PubSub: SavedSearchEvent v5
                   └─────────────────┘
                            │
              ┌─────────────┼─────────────┐
              ▼                           ▼
   ┌──────────────────┐       ┌────────────────────────┐
   │ saved-search-    │       │ Elasticsearch          │
   │ percolation      │──────►│ classifieds-ss-queries │
   └──────────────────┘       │ (includes Jobs fields) │
                              └────────┬───────────────┘
                                       │ Percolate
              PubSub: NewVerticalListing│
              ┌────────────────────────┐│
              ▼                        ▼▼
   ┌──────────────────┐       ┌────────────────────────┐
   │ saved-search-    │──────►│ MongoDB                │
   │ match-service    │       │ generalMatchedAlerts   │
   └────────┬─────────┘       └────────────────────────┘
            │ PubSub: SavedSearchNotification v3
            ▼
   ┌──────────────────┐
   │ saved-search-    │──► Email / Push Notifications
   │ alert-workers    │
   └──────────────────┘
```

## Implementation Sequence

1. **Parallel with Phase 3.1:**
   - F1: CAPI — make vertical dynamic
   - F2: marketplace-graphql — add Jobs filter config + mutation support
   - F4: MyAccount UI — Jobs fields in EditGeneral.tsx
   - F5: Percolation/match/alert — add Jobs fields to Classifieds config, remove Jobs-specific code
2. **After Phase 3.1 is live:**
   - F6: Run migration script
   - F8: Verify alert continuity
3. **Before migration:**
   - F7: Legacy messaging
4. **After migration verified:**
   - Cleanup: remove legacy Jobs saved search paths, ES index, MongoDB collections
