# Jobs to Classifieds - Phase 3.2 — Features

## F1: CAPI Saved Search — No Changes Needed

**Goal:** Verify that Jobs saved searches flow through CAPI without modification.

**Why no changes:** CAPI hardcodes `vertical: "general"` which is correct — Jobs listings are now general Classifieds listings with `marketType: "Job"`. The KSL API downstream stores `searchParams` as a JSON blob with minimal validation, so Jobs-specific fields (pay range, employer status, education, etc.) pass through without modification. KSL API publishes `SavedSearchEvent v5` to PubSub on create/update, keeping the percolation pipeline in sync.

**Key Files (reference only):**
- [SavedSearchHelper.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Helper/SavedSearchHelper.php) — `vertical: "general"` at lines 96, 158, 380 (correct as-is)
- [SavedSearchesController.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/common/api/controllers/SavedSearchesController.php) — Unified KSL API handler
- [SavedSearch.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/common/api/models/SavedSearch.php) — Model with JSON pass-through and PubSub publishing

---

## F2: marketplace-graphql — Jobs Saved Search Mutations

**Goal:** Extend the existing `saveSavedSearch` GraphQL mutation to support Jobs as a Classifieds listing type.

**Requirements:**
- Add `ListingTypeJob` case to the `saveSavedSearch` resolver (currently only supports CAR and CLASSIFIED)
- Add `JobsFilterConfig` to [config.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/config/config.go) defining valid Jobs filter names:
  - **StringFilters:** `keyword`, `city`, `state`, `employerStatus`, `payRangeType`, `displayTime`, `companyPerks`, `marketType`
  - **IntFilters:** `category`, `educationLevel`, `yearsOfExperience`, `zip`
  - **RangeFilters:** `salary` → `salaryFrom`/`salaryTo`, `hourly` → `hourlyFrom`/`hourlyTo`
  - **DistanceFilter:** `zip` + `miles`
- Add `MapJobsSavedSearchParams()` helper in [legacy-savedsearch-helper.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/legacy-savedsearch-helper.go)
- **Pay range note:** `prepareRangeFiltersParams()` currently divides price by 100 (cents→dollars). Pay ranges are already in dollars — this conversion must be skipped for `salary` and `hourly` fields
- Route Jobs mutations to CAPI `/saved-searches/` with `vertical` parameter (same endpoint as Classifieds)

**Key Files:**
- [legacy-savedsearch.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/legacy-savedsearch.go) — Add Jobs case to resolver
- [legacy-savedsearch-helper.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/legacy-savedsearch-helper.go) — Add Jobs param mapping
- [config.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/config/config.go) — Add JobsFilterConfig

---

## F3: Saved Search from New Classifieds/Jobs SRP

**Goal:** Users can save a search directly from the new SRP when Jobs filters are applied.

**Requirements:**
- "Save Search" button on SRP captures current filter state including Jobs-specific fields
- Calls `saveSavedSearch` GraphQL mutation with `listingType: JOB` (or CLASSIFIED with `marketType: "Job"`)
- Supports naming the saved search
- Supports enabling alerts with frequency selection (immediately, daily, weekly) for email and push

---

## F4: MyAccount Saved Search — Jobs Field Support

**Goal:** Update MyAccount New Search, Edit Search, and list view to support Jobs fields within the Classifieds flow.

**Requirements:**
- **EditGeneral.tsx** — Show Jobs-specific fields when `marketType === "Job"` or a Jobs category is selected:
  - **Show:** `payRangeType` toggle (Salary/Hourly), `salaryFrom`/`salaryTo` or `hourlyFrom`/`hourlyTo`, `employerStatus`, `educationLevel`, `yearsOfExperience`, `companyPerks`
  - **Hide:** Classifieds-only fields (`newUsed`, `sellerType`, `specSubCat*` fields)
- **Criteria.tsx** — Add display labels and formatting for pay range fields in the list view
  - Add to `SPECIAL_LABELS` map and `FIELD_PRIORITY` constants
- **API route** — Wire Jobs vertical through to CAPI (which now accepts `vertical` parameter)
- **Types** — Jobs fields already defined in [saved-search.d.ts](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/types/saved-search/saved-search.d.ts): `payRangeType`, `salaryFrom`, `salaryTo`, `jobType`, `educationLevel`, `yearsOfExperience`

**Key Files:**
- [EditGeneral.tsx](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/components/SavedSearch/Modals/EditGeneral.tsx) — Add conditional Jobs fields
- [EditJob.tsx](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/components/SavedSearch/Modals/EditJob.tsx) — Reference for Jobs field implementation (446 lines, already exists)
- [Criteria.tsx](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/components/SavedSearch/Criteria.tsx) — Update display labels
- [saved-searches.ts](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/constants/saved-searches.ts) — Update `FIELD_PRIORITY`
- [JobsOptions.ts](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/stores/saved-search/JobsOptions.ts) — Job categories, types, education levels

---

## F5: Classifieds Percolation — Add Jobs Fields

**Goal:** Extend the Classifieds percolation and matching pipeline to support Jobs-specific fields so that saved searches with pay range criteria can match Jobs listings.

**Requirements:**
- **ES mapping** — Add to [mappings/classifieds.json](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-percolation/mappings/classifieds.json):
  - `salaryFrom` (float), `salaryTo` (float), `hourlyFrom` (float), `hourlyTo` (float)
  - `payRangeType` (keyword)
  - `employerStatus` (keyword), `educationLevel` (integer), `yearsOfExperience` (integer)
  - `companyPerks` (text)
- **Percolation service** — Update [services/classifieds.go](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-percolation/services/classifieds.go):
  - Add pay range fields to `ClassifiedSavedSearch` struct
  - Add overlap range matching in `getQueryFilters()` for salary/hourly (listing range overlaps search range = match)
- **Match service** — Update [verticalexpectedfields/fields.go](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-match-service/verticalexpectedfields/fields.go):
  - Add `salaryFrom`, `salaryTo`, `hourlyFrom`, `hourlyTo`, `payRangeType`, `employerStatus`, `educationLevel`, `yearsOfExperience`, `companyPerks` to Classifieds expected fields
- **Alert workers** — Update [Config.php](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-alert-workers/src/Library/SavedSearch/Config.php):
  - Add pay range fields to Classifieds config as range-fields with two-field overlap logic
  - Add `employerStatus`, `educationLevel`, `yearsOfExperience` as exact-match fields
  - Add `companyPerks` as array-contains field
- **Remove unfinished Jobs-specific code** from percolation, match service, and alert workers (never completed, being replaced by Classifieds flow)

---

## F6: Data Migration Script

**Goal:** Migrate ~12,000 legacy Jobs saved searches into the Classifieds saved search system with zero downtime.

**Requirements:**
- Read from legacy MongoDB `jobsSavedSearch` collection
- Transform to Classifieds format:
  - Write to `generalSavedSearch` collection (not a separate Jobs collection)
  - Add `marketType: "Job"` to search params
  - Map Jobs criteria fields to Classifieds-compatible field names
- Preserve alert settings (email/push, active flags, frequency: immediately/daily/weekly)
- Index into `classifieds-ss-queries` ES percolation index (not `jobs-ss-queries`)
- Idempotent — safe to re-run if interrupted
- Validation step: compare source vs. destination counts and spot-check criteria accuracy
- **Runs after Phase 3.1** (Jobs listings must be visible in Classifieds first)
- **Category mapping** from legacy Jobs → Classifieds categories will be provided by Phase 3.1 (Shaping Project #003). Migration script consumes that mapping.

**Data Model (source — MongoDB `jobsSavedSearch`):**
| Field | Type | Description |
|-------|------|-------------|
| `id` | int | Saved search ID |
| `memberId` | int | User/member ID |
| `searchName` | string | Display name |
| `alert` | bool | Alerts enabled |
| `deliveryMethods.email.active` | bool | Email alerts active |
| `deliveryMethods.email.frequency` | string | immediately/daily/weekly |
| `deliveryMethods.push.active` | bool | Push alerts active |
| `deliveryMethods.push.frequency` | string | immediately/daily/weekly |
| `criteria_category` | int | Job category |
| `criteria_keyword` | string | Search keyword |
| `criteria_city/state/zip/miles` | mixed | Location criteria |
| `criteria_salaryFrom/To` | float | Salary range |
| `criteria_hourlyFrom/To` | float | Hourly rate range |
| `criteria_payRangeType` | string | salary/hourly |
| `criteria_educationLevel` | int | Education requirement |
| `criteria_yearsOfExperience` | int | Experience requirement |
| `criteria_employerStatus` | string | Employment type |
| `criteria_companyPerks` | string | Benefits/perks |
| `criteria_displayTime` | string | Posting recency |

**Legacy Reference:**
- [resetDB.js](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/testDbReset/resetDB.js) — MongoDB dump/restore patterns
- [populate/main.go](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-percolation/populate/main.go) — ES index population script

---

## F7: Legacy Messaging

**Goal:** Inform users on the legacy platform about upcoming saved search migration.

**Requirements:**
- Display messaging on legacy Jobs saved search pages indicating changes are coming
- Messaging should appear before migration begins
- Timing must align with when Jobs listings become visible/searchable in Classifieds

---

## F8: Alert Continuity

**Goal:** Email and push alerts continue working seamlessly after migration.

**Requirements:**
- Classifieds percolation pipeline matches Jobs listings (with `marketType: "Job"`) against migrated saved searches in `classifieds-ss-queries` index
- Email alerts sent via Classifieds email path (`/classifieds/general/email/sendListingAlertEmail`)
- Push notifications continue via existing notification service
- Maintain all three frequency options: immediately, daily, weekly
- Pay range overlap matching preserved in Classifieds percolation
- Matched alerts recorded in `generalMatchedAlerts` MongoDB collection
