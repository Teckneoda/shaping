# Jobs to Classifieds — Phase 3.1: Migrate Listings — Planning State

**Last updated**: 2026-03-30

---

## Decisions Made

### Migration Script
- **Approach**: Direct MongoDB write (no API calls, no PubSub events)
- **ID strategy**: Generate new IDs (legacy IDs may collide with existing classifieds)
- **Tracking**: `jobListingMigrations` collection maps legacy ID → new listing ID (same pattern as `serviceListingMigrations`)
- **History**: Each migrated listing gets a history object indicating it was an import
- **Re-run**: Overwrite flag allows re-importing and overwriting previously migrated data; without flag, skips already-migrated records
- **Skipped statuses**: `moderate`, `abuse`, `inprogress` — not migrated

### Status Mapping

| Legacy Status | New Status | Notes |
|---|---|---|
| `active` | Active | Direct map |
| `expired` | Expired | Direct map |
| `deleted` | Soft-delete | Recoverable by CX |
| `inactive` | Soft-delete | Recoverable by CX |
| `hidden` | Soft-delete | Recoverable by CX |
| `moderate` | **Skip** | Not migrated |
| `abuse` | **Skip** | Not migrated |
| `inprogress` | **Skip** | Not migrated |

### Field Mapping Decisions

| Legacy Field | Decision | Target |
|---|---|---|
| `employerStatus` | Sub-category spec fields | Existing specifications |
| `educationLevel` | Sub-category spec fields | Existing specifications |
| `yearsOfExperience` | Sub-category spec fields | Existing specifications |
| `companyName` | Map | `BusinessName` |
| `companyLogo` | Map | Photo array (first image) |
| `responsibilities` | Append | `Description` |
| `qualifications` | Append | `Description` |
| `requirements` | Append | `Description` |
| `contactNotes` | Append | `Description` |
| `companyPerks` | Drop | Not implementing |
| `contract` | Drop | No longer used |
| `relocation` | Drop | No longer used |
| `investment` | Drop | No longer used |

### Feature Flag
- **Out of scope** — Category feature flagging is a separate prerequisite project

### Legacy Platform Messaging
- Messaging on 5 pages: Detail page, Home page, Jobs SRP, Post-a-listing page, MyAccount (filtered to Jobs)
- Content and timing TBD before build

---

## Identified So Far

### Notion Doc — Key Requirements (FRAMED: OPS Approved)

- **Scope**: Migrate **both active and inactive** job listings from legacy to Classifieds
- **Solution components**: (1) Migration script, (2) Legacy platform messaging
- **Timing dependency**: Migration must align with favorites/saved searches readiness — avoid alerting users about listings they can't access
- **CX support concern**: Inactive/removed listings must remain recoverable in soft-delete state
- **Estimate**: 2 weeks web work
- **Business impact**: $1.2M annual revenue, 400K monthly page views, 1,300 active listings, 15K+ resumes

### New System (marketplace-backend) — Jobs Support

- **listing-http-rest** has full Jobs support:
  - `MarketType: Job` with fields: `JobsApplicationURL`, `JobsPayRangeType`, `JobsPayFrom`, `JobsPayTo`
  - Jobs activation policy (no price required; validates title, description, category, subCategory, city, state, name, contactMethod)
  - Lifecycle: delete, deactivate, renew (501 — not implemented), mark-sold/mark-sale-pending (blocked for Jobs)
  - Status: Stub -> PendingActivation -> Active -> Inactive/Sold/Expired/Deleted
  - Visibility: Inactive/deleted listings hidden from public, visible to owner/admin
  - MongoDB storage with ClassifiedListing canonical model
  - PubSub event publishing on state changes

- **Category system**: MongoDB `generalCategory` collection with per-subcategory `listingTypes` config
- **No migration tooling** exists yet (but `etl-migrate-legacy-reviews` provides a pattern)
- **Renewal** scaffolded but returns HTTP 501

### Legacy System (m-ksl-jobs) — Complete Schema

- **Database**: MongoDB `jobs` collection, 88 fields per listing
- **Search**: Solr-based (not Elasticsearch)
- **Statuses**: active, expired, deleted, moderate, abuse, hidden, inprogress
- **ID generation**: Centralized `idTracker` collection
- **Pay storage**: Integers in dollars (salaryFrom/salaryTo, hourlyFrom/hourlyTo)
- **Categories**: Numeric IDs (1-43)

**Supporting MongoDB collections**:
- `jobsFavoriteJobs`, `jobsSavedSearch`, `jobsMatchedAlerts`
- `jobsApplication`, `jobsQuickApply`
- `jobsEmployers`, `jobsTransactions`
- `jobsAutoRefresh`, `jobsMemberPreferences`
- `jobsCoupons`, `jobsCouponUses`, `jobsPackages`

### Complete Field Mapping (Legacy → New System)

| Legacy Field | Type | New System Field | Status |
|---|---|---|---|
| `id` | int | — | New ID generated; legacy ID stored in `jobListingMigrations` |
| `memberId` | int | MemberID | Mapped |
| `jobTitle` | string | Title | Mapped |
| `description` | string | Description | Mapped (+ appended fields below) |
| `category` | int | Category / SubCategory | Needs mapping table (numeric → string) |
| `salaryFrom` | int (dollars) | JobsPayFrom (cents) | Mapped — `* 100` |
| `salaryTo` | int (dollars) | JobsPayTo (cents) | Mapped — `* 100` |
| `hourlyFrom` | int (dollars) | JobsPayFrom (cents) | Mapped — `* 100` + payRangeType=hourly |
| `hourlyTo` | int (dollars) | JobsPayTo (cents) | Mapped — `* 100` + payRangeType=hourly |
| `payRangeType` | string | JobsPayRangeType | Mapped ("salary"/"hourly") |
| `applicationUrl` | string | JobsApplicationURL | Mapped |
| `city` | string | City | Mapped |
| `state` | string (2-letter) | State | Mapped |
| `zip` | string | Zip | Mapped |
| `lat` | float | Lat | Mapped |
| `lon` | float | Lon | Mapped |
| `contactName` | string | Name | Mapped |
| `contactEmail` | string | Email | Mapped |
| `contactPhone` | string | CellPhone | Mapped (format: 123-456-7890) |
| `displayPhone` | bool | `contactMethod` array | If `true`, include `"phone"` in array; if both false, default to `["messages"]` |
| `displayEmail` | bool | `contactMethod` array | If `true`, include `"email"` in array; if both false, default to `["messages"]` |
| `status` | string | Status | See Status Mapping table above |
| `createTime` | date | CreatedAt | Mapped |
| `modifyTime` | date | UpdatedAt | Mapped |
| `displayTime` | date | DisplayTime | Mapped |
| `expireTime` | date | ExpireTime | Mapped |
| `postTime` | date | — | May map to DisplayTime |
| `employerStatus` | string | Sub-category spec fields | **Decided** |
| `companyName` | string | BusinessName | **Decided** |
| `companyLogo` | string | Photo array (first image) | **Decided** |
| `responsibilities` | string | Append to Description | **Decided** |
| `qualifications` | string | Append to Description | **Decided** |
| `requirements` | string | Append to Description | **Decided** |
| `educationLevel` | int (0-4) | Sub-category spec fields | **Decided** |
| `yearsOfExperience` | int | Sub-category spec fields | **Decided** |
| `contactNotes` | string | Append to Description | **Decided** |
| `companyPerks` | string | — | **Dropped** |
| `contract` | string | — | **Dropped** |
| `relocation` | string | — | **Dropped** |
| `investment` | string | — | **Dropped** |
| `photo` | string | Photo array (first image) | See companyLogo |
| `standardFeatured` | bool | `standardFeaturedAd` | **Decided** — direct bool map |
| `featuredDates` | []unix timestamp | `standardFeaturedDates` | **Decided** — convert unix timestamps to FeaturedDate type |
| `inlineSpotlight` | bool | — | **Dropped** — no classifieds equivalent (Cars-only) |
| `topJobStart` | date | — | **Dropped** — not implementing boost migration |
| `feedJobId` | string | — | Feed integration — not migrated |
| `jobendTime` | date | — | Application deadline — not migrated |
| `paid` | int | — | Billing — not migrated |
| `moderator` | string | — | Moderation — not migrated |
| `moderatedTime` | date | — | Moderation — not migrated |
| `abuse` | array | — | Moderation — not migrated |
| `favoriteCount` | — | — | Separate service (Phase 3.2) |
| Billing fields (7) | various | — | Not migrated |

---

## Still Needs Research

1. **Category mapping table** — Need the actual mapping from legacy numeric IDs (1-43) to new category/subCategory strings. Where are Jobs categories defined in the new system?

2. ~~**Pay range edge cases**~~ — **Decided**: Listings must be one or the other (salary or hourly), not both.

4. ~~**Premium features**~~ — **Decided**: Migrate `standardFeatured` → `standardFeaturedAd` and `featuredDates` (unix timestamps) → `standardFeaturedDates` (FeaturedDate). Drop `inlineSpotlight` (Cars-only) and `topJobStart` (not implementing boost migration).

5. **Elasticsearch re-indexing** — After direct MongoDB write, how do migrated listings get indexed in Elasticsearch? Manual trigger needed?

6. ~~**`photo`**~~ — **Decided**: Dealer accounts use existing logo from Nest dealer record (dealer accounts created before migration; no photo migration needed for dealers). Non-dealer accounts only: migrate legacy `photo` field to `photos[0]` on the new listing.

---

## Unanswered Questions

1. **Is `RenewListing` (501) a blocker?** — Migrated expired listings can't be renewed without it.
2. **Legacy platform messaging content** — Who provides the verbiage and timing?
3. **Elasticsearch indexing post-migration** — Is there a bulk re-index process, or do we need to build one?

---

## Research Sources Consulted

| Source | Type | Summary |
|---|---|---|
| Notion: Phase 3.1 doc (3142ac5cb2358178aac7f685e25f9e0b) | Notion page | FRAMED: OPS Approved. Problem statement, solution (migration script + feature flag + messaging), business impact ($1.2M/yr), timing deps, 2-week estimate |
| `deseretdigital/marketplace-backend` (local, synced to origin/main 2026-03-30) | Repository | Listing service with Jobs schema (spec 007), lifecycle (spec 008), no migration tooling, no feature flags |
| `apps/listing/services/listing-http-rest/` | Service code | Full listing CRUD, lifecycle, Jobs fields, activation policies, visibility controls |
| `apps/listing/services/listing-http-rest/internal/types/listing.go` | Model | ClassifiedListing model — 4 Jobs fields, lifecycle timestamps, status enum |
| `apps/listing/services/listing-http-rest/internal/policy/jobs.go` | Policy | Jobs activation policy — no price required |
| `apps/listing/services/listing-http-rest/internal/domain/delete_deactivate.go` | Domain | Lifecycle transitions, mark-sold/sale-pending blocked for Jobs |
| `apps/listing/services/listing-http-rest/internal/client/category.go` | Client | Category config from MongoDB, per-subcategory listingTypes |
| `apps/review/services/etl-migrate-legacy-reviews/` | Migration pattern | Existing ETL migration pattern in the repo |
| `/Users/cpies/code/m-ksl-jobs/` | Legacy codebase | Complete legacy Jobs platform — 88-field schema, MongoDB `jobs` collection, Solr search |
| `/Users/cpies/code/m-ksl-jobs/site-api/api/common/JobsFields.php` | Legacy schema | Full field definitions, types, validation rules, required fields |
| `/Users/cpies/code/m-ksl-jobs/site-api/api/models/Job.php` | Legacy model | Job model with validation and field mapping |
| Specs 007, 008 | Spec docs | Jobs schema integration (complete), lifecycle endpoints (complete) |
