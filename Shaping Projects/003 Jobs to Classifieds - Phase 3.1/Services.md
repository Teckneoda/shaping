# Jobs to Classifieds - Phase 3.1: Migrate Listings — Services

## Services to Update

### listing-http-rest
**Repo**: `deseretdigital/marketplace-backend`
**Path**: `apps/listing/services/listing-http-rest/`

**Current Jobs support**:
- `MarketType: Job` with fields: `JobsApplicationURL`, `JobsPayRangeType`, `JobsPayFrom`, `JobsPayTo`
- Jobs activation policy (requires: title, description, category, subCategory, city, state, name, contactMethod — no price required)
- Lifecycle endpoints: delete, deactivate, mark-sold (blocked for Jobs), mark-sale-pending (blocked for Jobs), renew (fully implemented — returns 200)
- Status flow: Stub -> PendingActivation -> Active -> Inactive/Sold/Expired/Deleted
- Visibility: Inactive listings only visible to owner or admin/service callers

**Changes needed**:
- No model changes required — all legacy fields are handled via existing fields:
  - `employerStatus`, `educationLevel`, `yearsOfExperience` → sub-category specifications
  - `companyName` → `BusinessName`
  - `companyLogo` → photo array (first image)
  - `responsibilities`, `qualifications`, `requirements`, `contactNotes` → appended to `Description`
  - `companyPerks`, `contract`, `relocation`, `investment` → dropped (not migrated)
- Ensure inactive/deleted listings remain queryable by admin/CX for support workflows

### Category Configuration (MongoDB `generalCategory` collection)
**Repo**: `deseretdigital/marketplace-backend`
**Path**: `apps/listing/services/listing-http-rest/internal/client/category.go`

**Changes needed**:
- Add Jobs category and subcategories to `generalCategory` MongoDB collection
- Map legacy numeric category IDs (1-45, 40 categories — IDs 4, 13, 25, 31, 34 unused) to new category/subCategory strings
- Configure `listingTypes` to allow `Job` market type on appropriate subcategories

## Services to Create

### Migration Script / Worker
**Location**: New two-service setup in `marketplace-backend` (follow `auto-csl` services migration pattern)
**Reference pattern**: `apps/auto-csl/services/auto-csl-http-rest/` + `apps/auto-csl/services/auto-csl-ps-processor/`

**Purpose**: Repeatable migration of legacy job listings from `jobs` MongoDB collection to new Classifieds system. Hybrid approach: API-based for active listings, direct MongoDB write for non-active.

**Architecture** (same as auto-csl):
- **HTTP entry point**: Accepts `{ "listingIds": [...], "reimport": false }` from admin/root/service callers. Publishes each ID as a separate PubSub message to a migration topic.
- **PubSub worker**: Processes each listing individually, logging success/failure per listing.

**Authentication**:
- Worker obtains service JWT from Member API: `POST {MEMBER_API_URL}/service-sessions` with `Authorization: ddm-member-api-key {INTERSERVICE_KEY}`
- JWT has `role: "service"` → `IsPrivileged = true` → access to service-only endpoints
- Interservice key stored in Google Secret Manager

**Migration flow — Active listings** (API path):
1. Read legacy listing from MongoDB `jobs` collection
2. Create stub via `POST /listing` (listing-http-rest assigns new ID)
3. Save mapped field data via `PUT /listing/{id}`
4. Upload photos via `POST /listing/{id}/photos` (non-dealer only)
5. Request activation via `POST /listing/{id}/request-activation` (triggers fraud-validator, which auto-activates after 5-min delay). Note: `Activate` endpoint is reserved for fraud-validator only — migration must NOT call it directly.
6. Log migration in `jobListingMigrations` collection (legacy ID → new listing ID)

**Migration flow — Expired/soft-deleted listings** (direct MongoDB path):
1. Read legacy listing from MongoDB `jobs` collection
2. Transform fields and write directly to `ClassifiedListing` collection with correct status (`Expired` or `Deleted`) and timestamps (`expireTime`, `deletedAt`)
3. Generate new ID (must not collide with existing classifieds IDs)
4. Add history object indicating import
5. Log migration in `jobListingMigrations` collection

**Requirements**:
- Read from legacy MongoDB `jobs` collection
- Accept a list of legacy listing IDs to migrate a specific batch
- Create `jobListingMigrations` collection to log imports and map legacy ID → new listing ID (same pattern as `serviceListingMigrations`)
- Add history object on each migrated listing indicating it was an import
- Elasticsearch indexing handled automatically via MongoDB oplog connector (both API and direct write paths)
- Status mapping:
  - `active` → `Active`
  - `expired` → `Expired`
  - `deleted`, `inactive`, `hidden` → soft-delete state
  - `moderate`, `abuse`, `inprogress` → **skip entirely**
- Field transforms:
  - Pay conversion: legacy dollars (int) → cents (int, `* 100`)
  - Category conversion: legacy numeric IDs (1-45, 40 categories) → new string-based category/subCategory
  - `employerStatus`, `educationLevel`, `yearsOfExperience` → sub-category spec fields
  - `companyName` → `BusinessName`
  - `companyLogo` → photo array (first image)
  - `responsibilities`, `qualifications`, `requirements`, `contactNotes` → append to `Description`
- Re-runnable with **overwrite flag** to re-import and overwrite previously migrated data; without flag, skips already-migrated records
- Validation and error handling for malformed records

## Legacy Platform Messaging
**Repo**: Legacy Jobs platform (m-ksl-jobs)

**Pages requiring messaging**:
- Detail page
- Home page
- Jobs SRP
- Jobs Post-a-listing page
- MyAccount (when filtered to Jobs)

Content and timing TBD before build.

## Legacy Services (Reference Only)

### m-ksl-jobs (Legacy)
- **Database**: MongoDB `jobs` collection (88 fields per listing)
- **Search**: Solr-based indexing (not Elasticsearch)
- **Statuses**: active, expired, deleted, moderate, abuse, hidden, inprogress
- **Auth**: Member-based with JWT
- **Pay storage**: Integers in dollars (salaryFrom/salaryTo, hourlyFrom/hourlyTo)
- **Categories**: Numeric IDs (1-43)
- **Supporting collections**: jobsFavoriteJobs, jobsSavedSearch, jobsMatchedAlerts, jobsApplication, jobsQuickApply, jobsEmployers, jobsTransactions

### Member Listings API (Spec 009 — Draft)
**Repo**: `deseretdigital/marketplace-backend`
**Path**: `apps/listing/services/listing-http-rest/` (new `GET /listing` endpoint)

**Relevance**: Authenticated member listing inventory with pagination, returns all lifecycle states. Critical for post-migration My Account v2 experience. Currently scaffolded (returns 501), domain logic pending.

## External Dependencies

- **MongoDB**: Source (legacy `jobs` collection) and destination (new `ClassifiedListing`)
- **Solr** (legacy): Current search index — will not be updated post-migration
- **Elasticsearch** (new): Synced automatically via MongoDB oplog connector — no manual re-indexing needed
- **Cloudinary**: Image/logo URL migration for company logos
