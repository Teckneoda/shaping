# Jobs to Classifieds - Phase 3.1: Migrate Listings — Services

## Services to Update

### listing-http-rest
**Repo**: `deseretdigital/marketplace-backend`
**Path**: `apps/listing/services/listing-http-rest/`

**Current Jobs support**:
- `MarketType: Job` with fields: `JobsApplicationURL`, `JobsPayRangeType`, `JobsPayFrom`, `JobsPayTo`
- Jobs activation policy (requires: title, description, category, subCategory, city, state, name, contactMethod — no price required)
- Lifecycle endpoints: delete, deactivate, mark-sold (blocked for Jobs), mark-sale-pending (blocked for Jobs), renew (returns 501 — not yet implemented)
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
- Map legacy numeric category IDs (1-43) to new category/subCategory strings
- Configure `listingTypes` to allow `Job` market type on appropriate subcategories

## Services to Create

### Migration Script / Worker
**Location**: New service in `marketplace-backend` (follow `etl-migrate-legacy-reviews` pattern)
**Reference pattern**: `apps/review/services/etl-migrate-legacy-reviews/`

**Purpose**: Repeatable migration of legacy job listings from `jobs` MongoDB collection to new `ClassifiedListing` model via direct MongoDB write.

**Requirements**:
- Read from legacy MongoDB `jobs` collection
- Direct MongoDB write to `ClassifiedListing` collection (no API calls, no PubSub events)
- Generate new IDs for all migrated listings (avoid collisions with existing classifieds IDs)
- Create `jobListingMigrations` collection to log imports and map legacy ID → new listing ID (same pattern as `serviceListingMigrations`)
- Add history object on each migrated listing indicating it was an import
- Status mapping:
  - `active` → `Active`
  - `expired` → `Expired`
  - `deleted`, `inactive`, `hidden` → soft-delete state
  - `moderate`, `abuse`, `inprogress` → **skip entirely**
- Field transforms:
  - Pay conversion: legacy dollars (int) → cents (int, `* 100`)
  - Category conversion: legacy numeric IDs (1-43) → new string-based category/subCategory
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

## External Dependencies

- **MongoDB**: Source (legacy `jobs` collection) and destination (new `ClassifiedListing`)
- **Solr** (legacy): Current search index — will not be updated post-migration
- **Elasticsearch** (new): Re-indexing migrated listings via search-http-rest
- **Cloudinary**: Image/logo URL migration for company logos
