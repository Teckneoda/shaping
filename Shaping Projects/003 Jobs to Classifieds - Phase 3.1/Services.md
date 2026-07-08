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
- ✅ **DONE (verified in code 2026-06-25)** — The three new top-level Jobs fields are already implemented as `*string` on `ClassifiedListing` ([listing.go:1321-1323](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/types/listing.go#L1321-L1323)): `JobsEmploymentType`, `JobsYearsExperience`, `JobsEducationLevel`. Also wired through request/response types, `domain/update.go`, and `domain/validation.go`. **ES mappings + Mongo connector are also done** — `feeds-ps-transformer` and `feeds-ps-syncer` both reference the new fields. The "Phase 2 ES/connector follow-up" is no longer outstanding for these fields.
- ⚠️ **The three fields are validated ENUMS, not free strings** — migration must translate legacy values to these exact tokens ([validation.go:31-33](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/domain/validation.go#L31-L33)):
  - `jobsEmploymentType`: `full-time`, `part-time`, `contract`, `temporary`, `seasonal`, `internships`, `weekend-only`
  - `jobsEducationLevel`: `none`, `high-school`, `2-year-degree`, `4-year-degree`, `advanced-degree`
  - `jobsYearsExperience`: `none`, `1-2-years`, `3-4-years`, `5-7-years`, `8-10-years`, `10-plus-years`
  - **The legacy education/experience integer codes are arbitrary keys (NOT in 0→4 semantic order).** See the exact mapping tables in planning-state.md. A naive numeric map would corrupt data.
- Remaining legacy fields are handled via existing fields:
  - `employerStatus` → `jobsEmploymentType`, `educationLevel` → `jobsEducationLevel`, `yearsOfExperience` → `jobsYearsExperience` (new top-level fields above)
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
2. Transform fields and write directly to the **`general` collection** (constant `generalCollection = "general"` in [store/mongo.go:15](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/store/mongo.go#L15); `ClassifiedListing` is the document model, the collection name is `general`) with correct status (`Expired` or `Deleted`) and timestamps (`expireTime`, `deletedAt`)
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
  - `employerStatus` → `jobsEmploymentType`, `educationLevel` → `jobsEducationLevel`, `yearsOfExperience` → `jobsYearsExperience` (top-level enum fields — **key-based translation, see exact tables in planning-state.md**)
  - `companyName` → `BusinessName`
  - `companyLogo` → photo array (first image)
  - `responsibilities`, `qualifications`, `requirements`, `contactNotes` → append to `Description`
- Re-runnable with **overwrite flag** to re-import and overwrite previously migrated data; without flag, skips already-migrated records
- Validation and error handling for malformed records
- **Favorites (inline, per listing)**: after each listing is migrated and its mapping recorded, query `jobsFavoriteJobs` for favorites with `savedId` == this legacy listing ID, transform each into `generalFavorites` (`memberId` string→int, generate `favoriteId = "{memberId}-{adId}"`, all notification prefs `false`, preserve `createTime`), idempotency-check on `favoriteId`, and insert. No separate favorites script and no `jobListingMigrations` lookup pass — the new `adId` is the ID just assigned to the listing. Favorites for skipped listings are never migrated. Favorites re-migration under the overwrite flag is a nice-to-have, not required.

**Collections touched (favorites)**: source `jobsFavoriteJobs`, destination `generalFavorites` (same collection Classifieds uses).

**Elasticsearch sync for favorites:** `listing-http-favorites-rest` is in production, so favorites are read directly from MongoDB — **no ES sync step is required** for migrated favorites.

## Legacy Platform Messaging
**Repo**: Legacy Jobs platform (m-ksl-jobs)

**Pages requiring messaging**:
- Detail page
- Home page
- Jobs SRP
- Jobs Post-a-listing page
- MyAccount (when filtered to Jobs)

Content and timing TBD before build. Also covers the legacy favorites surfaces (MyAccount favorites page when filtered to Jobs, and the Jobs detail page favorite-button area).

## Services That Do NOT Need Changes (Favorites)

Migrated favorites land in `generalFavorites` — the same collection Classifieds already uses — so the existing favorites stack serves them with no code changes.

### CAPI — m-ksl-classifieds-api
Full CRUD on `generalFavorites` via `POST/PUT/DELETE /listings/{listingId}/favorites`. Validates the listing exists in the `general` collection — migrated Jobs listings are there (from this project). No changes needed.

**Reference:** [ListingFavoriteController.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ListingFavoriteController.php), [FavoriteHelper.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Helper/FavoriteHelper.php)

### listing-http-favorites-rest (marketplace-backend)
**In production.** Serves favorites from `generalFavorites` (CLASSIFIED vertical) directly from MongoDB. Migrated Jobs favorites land there and are served/counted automatically. Because this service is live, migrated favorites need **no ES sync step**. No changes needed.

**Reference:** [domain/favorites.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-favorites-rest/internal/domain/favorites.go)

### search-http-rest (marketplace-backend)
Favorites enrichment for search results. Migrated favorites carry `vertical: "classifieds"` and are served by the existing Classified mapping. No changes needed.

**Reference:** [domain/favorites.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/search-http-rest/internal/domain/favorites.go)

### listing-ps-price-drop (marketplace-backend)
Reads `generalFavorites` for price-drop notifications. Migrated favorites default to `notifyOnPriceDrop: { email: false, push: false }` — they won't trigger notifications unless the user opts in post-migration. No changes needed.

**Reference:** [store/favorite.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-ps-price-drop/internal/store/favorite.go)

### MyAccount — m-ksl-myaccount-v2
Migrated favorites appear under the "Classifieds" section (they're in `generalFavorites`). Users selecting "All" or "Classifieds" see their migrated Jobs favorites. The "Jobs" section filter shows empty post-migration — acceptable during transition; cleanup is a later phase.

**Reference:** [favorites/[vertical]/[id].ts](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/pages/api/v1/favorites/%5Bvertical%5D/%5Bid%5D.ts)

### marketplace-graphql — live favorite routing (context, not part of this migration)
`marketplace-graphql` has `FavoriteListing`/`UnfavoriteListing`/`UpdateFavoriteListing` mutations. `ListingTypeJob` cases currently route to the legacy KSL API; `ListingTypeClassified` cases route to CAPI (the target path). Re-pointing Jobs favorite *actions* to the Classifieds path is a live-cutover concern (3 switch cases in `graph/mutationresolvers/legacy-favoritelisting.go`, ~lines 99 add / 187 remove), tracked separately from the one-time data migration in this project.

## Legacy Services (Reference Only)

### m-ksl-jobs (Legacy)
- **Database**: MongoDB `jobs` collection (88 fields per listing)
- **Search**: Solr-based indexing (not Elasticsearch)
- **Statuses**: active, expired, deleted, moderate, abuse, hidden, inprogress
- **Auth**: Member-based with JWT
- **Pay storage**: Integers in dollars (salaryFrom/salaryTo, hourlyFrom/hourlyTo)
- **Categories**: Numeric IDs (1-43)
- **Supporting collections**: jobsFavoriteJobs, jobsSavedSearch, jobsMatchedAlerts, jobsApplication, jobsQuickApply, jobsEmployers, jobsTransactions

**Legacy Favorites (source for the inline favorites migration)**:
- **Collection**: `jobsFavoriteJobs` — fields: `memberId` (string), `savedId` (string, = legacy listing ID), `createTime` (UTCDateTime)
- **No notification preferences** — no price-drop, no expiring-soon alerts (unlike Classifieds favorites)
- **API**: [FavoriteController.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/api/controllers/FavoriteController.php) — POST `/favorite/favorite`, POST `/favorite/removefavorite`
- **GraphQL**: [MyFavoritesFieldObject.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/APIGraphQL/FieldObject/MyFavoritesFieldObject.php) — `myFavorites` query
- **"Favorite Employer"** exists but is buggy and OUT OF SCOPE

**Classifieds Favorites (target)**:
- **Collection**: `generalFavorites` — fields: `favoriteId` (string, `"{memberId}-{adId}"`), `adId` (int), `memberId` (int), `notifyOnPriceDrop` (object), `notifyOnExpire` (object), `createTime` (UTCDateTime)
- **Schema reference**: [GeneralFavoritesCollection.php:169-205](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Db/Mongo/GeneralFavoritesCollection.php#L169-L205)

### Member Listings API (Spec 009 — Draft)
**Repo**: `deseretdigital/marketplace-backend`
**Path**: `apps/listing/services/listing-http-rest/` (new `GET /listing` endpoint)

**Relevance**: Authenticated member listing inventory with pagination, returns all lifecycle states. Critical for post-migration My Account v2 experience. Currently scaffolded (returns 501), domain logic pending.

## External Dependencies

- **MongoDB**: Source (legacy `jobs` + `jobsFavoriteJobs` collections) and destination (new `general` collection holding `ClassifiedListing` documents, and `generalFavorites` for migrated favorites)
- **Solr** (legacy): Current search index — will not be updated post-migration
- **Elasticsearch** (new): Synced automatically via MongoDB oplog connector — no manual re-indexing needed
- **Cloudinary**: Image/logo URL migration for company logos
