# Planning State — Jobs to Classifieds - Phase 3.2

## Identified So Far

### Project Scope
- Migrate ~12,000 legacy Jobs saved searches into the Classifieds system (not a separate vertical)
- Jobs saved searches become Classifieds saved searches with `marketType: "Job"` + pay range fields
- Ensure saved searches work end-to-end: SRP save, MyAccount create/edit, alert pipeline
- Zero-downtime migration with alert continuity
- Business impact: safeguards $1.2M annual revenue, 400K monthly page views, 1,200 active listings

### Key Decisions Made
1. **No new marketplace-backend service.** CAPI already handles saved search CRUD for Classifieds — make `vertical` dynamic instead of hardcoded to `"general"`, and Jobs flows through the same Classifieds path
2. **Jobs fields added to Classifieds percolation**, not kept as a separate vertical. The unfinished Jobs-specific code in percolation/match/alert services will be removed
3. **MyAccount keeps New Search and Edit Search.** EditGeneral.tsx updated with conditional Jobs fields when `marketType === "Job"` or Jobs category is selected
4. **Phased cutover, no dual-write.** Build API/UI changes in parallel with Phase 3.1, run migration after Phase 3.1 is live, then decommission legacy
5. **marketplace-graphql is the frontend entry point.** `saveSavedSearch` mutation gets a new Jobs case routing to CAPI
6. **Alert workers stay.** Update Classifieds config with Jobs range fields, remove Jobs-specific matching class

### Architecture: Jobs as Classifieds
- Jobs saved searches stored in `generalSavedSearch` MongoDB collection (same as Classifieds)
- Indexed into `classifieds-ss-queries` ES percolation index (not a separate `jobs-ss-queries`)
- Matched alerts recorded in `generalMatchedAlerts`
- `marketType: "Job"` distinguishes Jobs from other Classifieds saved searches
- Pay range overlap matching (listing range overlaps search range = match) added to Classifieds query filters

### CAPI Flow (Traced)
```
marketplace-graphql saveSavedSearch(listingType: JOB)
  → Validate filters against JobsFilterConfig
  → MapJobsSavedSearchParams() → key/value map
  → POST/PUT CAPI /saved-searches/ (with vertical param)
    → SavedSearchHelper creates/updates via KSL API
    → Stored in generalSavedSearch MongoDB collection
    → SavedSearchEvent published to PubSub
    → Percolation service indexes into classifieds-ss-queries
```

### Pay Range Implementation
- Two separate range fields: `salary` (salaryFrom/salaryTo) and `hourly` (hourlyFrom/hourlyTo)
- `payRangeType` determines which range is active
- marketplace-graphql `prepareRangeFiltersParams()` must NOT divide pay values by 100 (price does cents→dollars, pay is already in dollars)
- Overlap matching: listing salary 40k-50k matches search salary 10k-45k (ranges overlap)

### MyAccount UI
- `EditGeneral.tsx` gets conditional Jobs fields (pay range, pay type, employer status, education, experience, perks) shown when `marketType === "Job"` or Jobs category selected
- `EditJob.tsx` already exists (446 lines) as reference for Jobs field patterns
- `Criteria.tsx` updated with display labels for pay range fields
- Jobs fields already defined in TypeScript types: `payRangeType`, `salaryFrom`, `salaryTo`, `jobType`, `educationLevel`, `yearsOfExperience`

## Still Needs Research

- **App (mobile) impact:** Notion notes the app "should work as is" but may need work for Jobs-specific fields — needs investigation
- **KSL API downstream path:** RESOLVED — KSL API has a unified `SavedSearchesController` that accepts a `vertical` parameter and maps to the correct MongoDB collection. Minimal field validation means searchParams (including pay range) passes through as-is. Since Jobs is folding into Classifieds, we use `vertical: "general"` with `marketType: "Job"` in searchParams — no KSL API changes needed
- **Category mapping:** Verify Jobs category IDs are compatible with the Classifieds category system, or if mapping is needed during migration
- **`hourlyFrom`/`hourlyTo` in ES:** Verify whether hourly rates need separate fields in the Classifieds ES mapping or if they map through the salary field with `payRangeType` as qualifier

## Unanswered Questions

1. ~~**KSL API endpoint:**~~ RESOLVED — `classifieds/general/savedSearchesGeneral/addSavedSearch` accepts Jobs searchParams as-is. KSL API stores searchParams as a JSON blob with minimal validation, and publishes `SavedSearchEvent v5` to PubSub on create/update. No changes needed — CAPI's hardcoded `vertical: "general"` is correct since Jobs listings become general Classifieds listings.
2. **Category IDs:** Category mapping between legacy Jobs and Classifieds will be provided in Phase 3.1 (Shaping Project #003). Migration script should consume that mapping.
3. **TODO — Mobile app conversation:** Schedule conversation with app team to determine if the mobile app needs changes to display Jobs-specific saved search fields (pay range, pay type) or if it already handles them.

## Research Sources Consulted

### Notion Documents
- [Jobs to Classifieds - Phase 3.2 Migrate saved search](https://www.notion.so/3212ac5cb235808991fbd3a730bb78dd) — Project framing document with problem statement, potential solutions, business impact
- [BUILD: Jobs to Classifieds - Phase 3.2](https://www.notion.so/3332ac5cb235800aa73efd418aa1dd11) — Build plan (empty, status: "Needs Shaping")

### Repositories
- **deseretdigital/marketplace-backend** — No saved search CRUD endpoints; established service pattern: Handler → Domain → Store → PubSub (listing-http-rest reference)
- **marketplace-graphql** — `saveSavedSearch` mutation supports CAR + CLASSIFIED only; Jobs is read-only (alert counts). Filter configs exist for Cars and Classifieds. CAPI integration via REST. Architecture: thin GraphQL layer, no business logic, REST-only backends
- **CAPI (m-ksl-classifieds-api)** — `SavedSearchController.php` POST/PUT endpoints; `SavedSearchHelper.php` hardcodes `vertical: "general"`; delegates to KSL API; stores searchParams as JSON blob; no PubSub publishing
- **KSL API (ksl-api)** — Unified `SavedSearchesController` with `DATABASE` constant mapping verticals to MongoDB collections. `SavedSearch.php` model stores searchParams as JSON with minimal validation. Publishes `SavedSearchEvent v5` to PubSub on create/update. `vertical: "general"` routes to `generalSavedSearch` collection — correct for Jobs-in-Classifieds
- **saved-search-percolation** — Go; Classifieds mapping at `mappings/classifieds.json`, unfinished Jobs code at `services/jobs.go` and `mappings/jobs.json`
- **saved-search-match-service** — Go; Classifieds expected fields in `verticalexpectedfields/fields.go`, query doc in `queryDoc.go`
- **saved-search-alert-workers** — PHP/Symfony; master config `Config.php`, Classifieds matching in `SearchMatchGeneralClass.php`, Jobs matching in `SearchMatchJobsClass.php` (to be removed)
- **Legacy/m-ksl-jobs** — GraphQL `savedSearchSave` mutation, MongoDB `jobsSavedSearch` collection (~12,000 records), aggregation queries
- **Legacy/m-ksl-myaccount-v2** — Vertical-specific edit forms (EditJob.tsx exists, 446 lines), Criteria.tsx display, TypeScript types with Jobs fields, API routes (Jobs returns NOT_IMPLEMENTED)

## Changelog
- 2026-03-31: Initial shaping session — researched all legacy saved search services, Notion docs, marketplace-backend, and legacy frontend implementations. Documented features, services, architecture, and open questions.
- 2026-03-31: Resolved all 7 open questions. Key decisions: no new marketplace-backend service (use CAPI), Jobs as Classifieds with marketType, phased cutover, remove unfinished Jobs percolation code, extend Classifieds pipeline with Jobs fields. Rewrote Features.md (8 features) and Services.md (7 services + cleanup) with implementation details.
- 2026-03-31: Researched KSL API saved search persistence — confirmed CAPI hardcoded `vertical: "general"` is correct for Jobs-in-Classifieds, no KSL API changes needed. searchParams pass-through with minimal validation. KSL API publishes SavedSearchEvent v5 to PubSub. Marked mobile app impact as TODO conversation with app team.
