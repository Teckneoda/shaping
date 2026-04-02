# Category Manager - Admin & Dev Only Categories — Features

## Feature 1: Visibility Flags on Categories

Add `visibility` object to category and subcategory MongoDB documents with two boolean fields:
- **`adminOnly`** — Category is only visible to admin/root users
- **`devOnly`** — Category is only visible to users with dev member permissions (existing `isDevMember` concept)

Default: both `false` (publicly visible). Missing fields treated as `false` for backward compatibility.

## Feature 2: Nest Admin UI — Visibility Management

- New **Visibility** column in the category tree table showing badges/icons for admin-only and dev-only categories
- New **Visibility** edit form with two checkboxes (Admin Only, Dev Only) when creating or editing categories/subcategories
- Change tracking via `visibilityChanged` indicator in the staging/prod workflow
- Available on both categories and subcategories
- All category manager users can toggle visibility (no granular permissions — `generalNestAccess` is all-or-nothing)

## Feature 3: Legacy CAPI Filtering — Category Endpoints (m-ksl-classifieds-api)

This is the **production-critical** path. CAPI currently serves all category data to marketplace-graphql and frontends.

**Critical design constraint**: CAPI `/category-filters` must return ALL categories (including hidden) with `visibility` metadata on each entry. It must NOT filter based on JWT role. Reason: marketplace-graphql has two caches that use single cache keys for all callers — `fetchClassifiedsCategoryOptions()` (5-min go-cache, key `AllClassifiedsFilters`) and `SpecificationsClient` (60-min, calls CAPI with empty JWT). If CAPI filtered per-role, the first caller's role would determine what all users see for the cache duration.

- `/category-filters` returns all categories with `visibility: { adminOnly, devOnly }` fields — **no per-role filtering**
- `/category-tree` and `/category-seo` — these are consumed directly and CAN filter per-role based on JWT
- `CategoryHelper` adds `visibility` data to responses; for `/category-tree` and `/category-seo`, filters hidden categories based on caller role
- Caller role determined from JWT passed by marketplace-graphql
- **adminOnly** categories excluded when caller is not admin
- **devOnly** categories excluded when caller is not a dev member
- Cascading: hidden parent category hides all subcategories regardless of their own flags
- Memcache (5-min TTL): For `/category-tree` and `/category-seo`, use post-cache filtering (cache full data, filter per-request) to avoid multiplying cache entries per role

## Feature 4: Legacy CAPI Filtering — Search Results (m-ksl-classifieds-api)

**Note:** marketplace-graphql has fully rolled over `searchListings` to search-http-rest (100% rollout). This legacy search path may no longer receive production traffic for that query. However, if m-ksl-classifieds-api search endpoints are called directly by other consumers, filtering is still needed.

- `ListingsSearch` adds `must_not` terms filter on `category` field in Elasticsearch queries to exclude hidden categories
- Non-admin/non-dev users do not see listings in hidden categories in search results
- Admin/dev callers bypass the exclusion filter
- No Elasticsearch schema change needed — query-time filtering only

## Feature 5: Backend Filtering — Category Tree (marketplace-backend, listing-http-rest)

**Not yet serving production traffic for category endpoints** — these changes prepare listing-http-rest for when it replaces CAPI's category endpoints.

- `CategoryClient` reads visibility data from MongoDB into the cached category tree
- New `GetFilteredCategoryTree(ctx, isAdmin, isDevMember)` method filters the cached tree at request time
- **adminOnly** categories excluded when caller is not admin
- **devOnly** categories excluded when caller is not a dev member
- Cascading: hidden parent category hides all subcategories regardless of their own flags
- Reuses existing `isDevMember` pattern from the search service
- Filtering at request time (not cache time) so single cache serves all callers

## Feature 6: Backend Filtering — Search Results (marketplace-backend, search-http-rest)

**Currently serving production search traffic.** marketplace-graphql routes 100% of `searchListings` queries to search-http-rest via `SEARCH_URL` (rollout at 10,000/10,000 in `legacy-listing.go`).

- Search service caches hidden category IDs from the category tree (using existing `SimpleCache` pattern)
- At query time, adds `MustNot` terms filter on `category` field to exclude hidden categories
- Non-admin/non-dev users do not see listings in hidden categories in search results
- Follows existing `isDevMember` exclusion pattern in search query builder — no Elasticsearch schema change needed
- Admin/dev callers bypass the exclusion filter

## Feature 7: Backend Filtering — AI Category Suggestions (marketplace-backend)

- `listing-http-ai-analyze` keeps full taxonomy cached (background refresh, no request context)
- Per-request filtering in handler: before building AI prompt, filter taxonomy to exclude hidden categories
- Prevents AI from suggesting admin/dev-only categories to regular users

## Feature 8: GraphQL Filtering (marketplace-graphql)

**This is now a required filtering layer, not just defense-in-depth.** Because CAPI `/category-filters` returns ALL categories with visibility metadata (to support GraphQL's single-key caches), GraphQL must do per-request filtering for the AvailableFilters and Specifications paths.

- New `CategoryVisibility` GraphQL type with `adminOnly` and `devOnly` fields
- Internal client structs in `services/capi/` updated to deserialize `visibility` data: add `AdminOnly bool` and `DevOnly bool` to `ClassifiedsCategoryFilter` struct (line 48) and `CacheCategory` struct in `specifications.go` (line 36)
- **AvailableFilters path — `prepareClassifiedsCategoryOptions()`** (`legacy-searchfilters-classifieds.go:636`): This is where per-request filtering MUST happen. Add visibility check in the loop at line 641: skip entries where `d.AdminOnly && !isAdmin` or `d.DevOnly && !isDevMember`. Extract caller role from JWT in request context (existing pattern at line 586). The go-cache (5-min, single key `AllClassifiedsFilters`) continues to cache the full unfiltered CAPI response.
- **SpecificationsClient path — `GetSpecifications()`** (`specifications.go:116`): Add visibility check at line 138 before returning specs for a category. The SpecificationsClient calls CAPI with empty `JWTTokens{}` (no user context) and caches for 60 min — this is correct because it caches everything, and filtering happens per-request when specs are looked up. Caller context must be passed into `GetSpecifications()` (signature change needed).
- **`/category-tree` and `/category-seo` paths**: These are filtered by CAPI itself (not cached with single key in GraphQL), so no GraphQL filtering needed for these.
- No JWT changes needed — `devMember` is not a GraphQL concept, but `isDevMember` can be derived from the existing JWT `Role` field or passed as a query parameter

## Feature 9: Frontend — Sitemap Generation (marketplace-frontend)

The frontend sitemap generator at `apps/ksl-marketplace/app/search/sitemap.ts` is a **critical path** for category visibility:

- Calls `fetchFilters({ includeAllOptions: true })` which resolves to GraphQL `AvailableFilters` query
- Iterates all category/subcategory options from `VERTICAL_CONFIG_MAPPING["CLASSIFIED"] = ["cat", "sub", "marketType"]`
- Generates sitemap URLs like `/search/cat/CategoryName/sub/SubcategoryName` for every category
- **12-hour cache** (`sitemapCache`) — hidden categories persist in sitemap up to 12 hours after backend filters them
- If GraphQL filters hidden categories, sitemap generation automatically excludes them (no frontend code change needed)
- Search engines would crawl hidden category URLs if they leak into the sitemap

## Feature 10: Frontend — Category Display Surfaces (marketplace-frontend)

These surfaces all consume data from GraphQL and will **automatically respect** backend filtering with no frontend code changes:

- **Search filter UI** (`Filters/SelectFilter.tsx`, `Filters/FilterComponent.tsx`): Renders category/subcategory dropdowns from `AvailableFilters`
- **Search breadcrumbs** (`Search/SearchBreadcrumbs.tsx`): Shows category in breadcrumb trail for classified searches
- **Services category list** (`page/[slug]/modules/Named/ServicesCategoryList.tsx`): Renders subCategory filter options with counts
- **SEO metadata** (`search/services/metadata.ts`, `search/[[...slug]]/actions/fetch-category-seo.ts`): Generates page titles and meta descriptions using `fetchCategorySeoCached()` from CAPI `/category-seo`
- **Listing detail schema** (`listing/[id]/components/ListingSchema.tsx`): Uses `listing.subCategory` in structured data — listings in hidden categories would still show their category if directly accessed by URL
- **Sell flow** (`sell/post-a-listing/components/Fields/FieldSuggestedCategories.tsx`): Displays AI-suggested categories from `getSuggestedCategories` GraphQL query — needs Feature 7 (AI filtering) to work
- **Similar results** (`Search/SimilarResults.tsx`): Uses category/subCategory for similarity matching
- **URL routing** (`search/services/url-parameters.ts`): Constructs URLs with category params — if a user navigates to a hidden category URL directly, the backend should return empty results

## Feature 11: Legacy Sitemap Generator (m-ksl-classifieds)

The legacy sitemap at `m-ksl-classifieds/util/sitemap/classes/Sitemap.php` queries Elasticsearch **directly** (not through CAPI):

- `generateCatSitemap()` — aggregates ES `category` field, generates `/search/cat/X` URLs
- `generateCatSubCatSitemap()` — aggregates ES `category` + `subCategory`, generates combined URLs
- `generateCatSubCatStateSitemap()`, `generateCatSubCatStateCitySitemap()`, `generateCatSubCatZipSitemap()` — deeper geographic combinations
- **Problem**: These query ES directly via `/classifieds/general/listing/elasticSearch`, bypassing CAPI entirely. If listings exist in hidden categories, they appear in the sitemap
- **Fix options**: (a) Add `must_not` filter on hidden category IDs to the ES aggregation queries, or (b) post-filter the aggregation results against a hidden category list
- This is a cron job (`createAllSitemaps.php`) — runs periodically, not real-time

## Feature 12 (Nice-to-Have): Migrate CAPI Category Read Endpoints to listing-http-rest

**Goal**: Eliminate m-ksl-classifieds-api as the category data source by adding the three read-only category endpoints to listing-http-rest in marketplace-backend. Once these exist, marketplace-graphql's `CAPI_URL` can point to listing-http-rest for category data, removing one of the last reasons CAPI needs to exist for classifieds.

This feature is a **nice-to-have** because the core visibility filtering project works with CAPI. But since we're already adding visibility fields to the category data model and filtering logic to both CAPI and listing-http-rest, this is the natural time to consolidate.

### Current State: listing-http-rest Already Has Most of the Data

The `CategoryClient` (`apps/listing/services/listing-http-rest/internal/client/category.go`) already:
- Reads from MongoDB `generalCategory` collection with 60-min in-memory cache
- Builds a full `CategoryTree` with `CategoryData` and `SubCategoryData` structs
- Reads Specifications (with InputConfig, Status, Weight, etc.) on each SubCategory
- Reads FeaturePrice, ListingTypes, PricingType, MaxPrice, RequiresPayment, ListingFee, etc.
- Has **no HTTP endpoints** — all internal, used for listing validation (create, update, activate)

### Endpoints to Add

#### 13a. `GET /category-filters` → New handler in listing-http-rest
- **What CAPI does**: MongoDB `$graphLookup` aggregation → returns flat array of `{ category, subCategory, specifications[] }` objects. No caching on this endpoint.
- **What listing-http-rest needs**: HTTP handler that transforms the existing `CategoryTree` (already cached 60-min) into the flat response format CAPI returns. Trivially implemented — iterate tree, emit one entry per subcategory.
- **Visibility addition**: Include `visibility: { adminOnly, devOnly }` fields on each entry (CAPI version must also add these per Feature 3).
- **Gap**: None — all data already exists in `SubCategoryData` struct (specifications, category title, subcategory title).

#### 13b. `GET /category-tree` → New handler in listing-http-rest
- **What CAPI does**: MongoDB `$graphLookup` → nested tree with extensive options (`keyType`, `showSunsetItems`, `hideDeprecated`, `showFields`, `showListingCounts`, `specSort`, `specHashify`, `specIncludeInactive`). Memcache 1hr + controller-level cache 5min. Optional ES aggregation for listing counts.
- **What listing-http-rest needs**: HTTP handler that returns the cached `CategoryTree` with options support. In-memory cache already exists (60-min).
- **Gaps**:
  - `showListingCounts` requires Elasticsearch aggregation (category → subCategory doc counts with Active/Pending status filter). listing-http-rest doesn't have an ES client — could call search-http-rest or add a direct ES query.
  - `showSunsetItems`, `hideDeprecated`, `new` flag expiration logic — currently not implemented. CAPI has date-based "new" detection and sunset/deprecated filtering in `CategoryHelper.php`.
  - `keyType` options (`title`/`id`/`array`) — response formatting variations.
  - These options are consumed by Nest's Category Manager UI, not by marketplace-graphql. marketplace-graphql only calls `/category-tree` for basic category data. Could implement a simplified version that serves marketplace-graphql's needs without all of CAPI's options.

#### 13c. `GET /category-seo` → New handler in listing-http-rest
- **What CAPI does**: MongoDB `$graphLookup` → returns `{ metaPageTitle, metaDescription }` for a given category/subcategory. Memcache 1hr.
- **What listing-http-rest needs**: HTTP handler + read SEO fields from MongoDB.
- **Gap**: `CategoryClient` currently does **not** project `metaPageTitle` or `metaDescription` from MongoDB. These fields exist on category/subcategory documents but are not included in the current query. Need to:
  1. Add `MetaPageTitle` and `MetaDescription` fields to `CategoryData` and `SubCategoryData` structs
  2. Add these fields to the MongoDB query projection in `fetchAll()` (line 226 of `category.go`)
  3. New HTTP handler that accepts `category` and optional `subCategory` params, looks up the tree, returns SEO data

### Nest's Two Category Tools — Different Patterns

**Important architecture discovery**: Nest has two separate tools for category management, and they use **different backends**:

1. **Category Manager** (`classifieds/assets/categoryManager/`) — React frontend calls Nest's PHP backend via `/classifieds/tools-proxy/category-manager/{action}`, which writes **directly to MongoDB**. No CAPI involvement at all.
2. **Specification Manager** (`classifieds/assets/specificationManager/`) — React frontend calls `/classifieds/api`, which is a **CAPI proxy** in `App.php` (line 176). This proxies requests to `$_ENV['CAPI_URI']` (m-ksl-classifieds-api). All spec CRUD goes through CAPI.

This means CAPI's spec endpoints are consumed by Nest's Specification Manager (via the API proxy), and CAPI's read endpoints (`/category-tree`, `/category-filters`) are consumed by both marketplace-graphql AND Nest's Specification Manager (for the category picker).

### Read-Only Endpoints (Consumed by marketplace-graphql + Nest Spec Manager)

These serve category data to consumers. marketplace-graphql is the primary consumer; Nest's Specification Manager also calls `/category-tree` for its category picker.

#### 13a. `GET /category-filters` → New handler in listing-http-rest
- **What CAPI does**: MongoDB `$graphLookup` aggregation → returns flat array of `{ category, subCategory, specifications[] }` objects. No caching.
- **What listing-http-rest needs**: HTTP handler that transforms the existing `CategoryTree` (already cached 60-min) into the flat response format. Trivially implemented — iterate tree, emit one entry per subcategory.
- **Visibility addition**: Include `visibility: { adminOnly, devOnly }` fields on each entry.
- **Gap**: None — all data already exists in `SubCategoryData` struct.
- **Consumers**: marketplace-graphql (`fetchClassifiedsCategoryOptions()`, `SpecificationsClient`)

#### 13b. `GET /category-tree` → New handler in listing-http-rest
- **What CAPI does**: MongoDB `$graphLookup` → nested tree with extensive options (`keyType`, `showSunsetItems`, `hideDeprecated`, `showFields`, `showListingCounts`, `specSort`, `specHashify`, `specIncludeInactive`). Memcache 1hr + controller cache 5min. Optional ES aggregation for listing counts.
- **What listing-http-rest needs**: HTTP handler that returns the cached `CategoryTree` with options support. In-memory cache already exists (60-min).
- **Gaps**:
  - `showListingCounts` requires Elasticsearch aggregation (category → subCategory doc counts with Active/Pending status filter). listing-http-rest doesn't have an ES client — could call search-http-rest or add a direct ES query.
  - `showSunsetItems`, `hideDeprecated`, `new` flag expiration logic — CAPI has date-based "new" detection and sunset/deprecated filtering.
  - `keyType` options (`title`/`id`/`array`) — response formatting variations.
  - Could implement a simplified version for marketplace-graphql first, add Nest options later.
- **Consumers**: marketplace-graphql (basic tree data), Nest Specification Manager (category picker with `keyType`)

#### 13c. `GET /category-seo` → New handler in listing-http-rest
- **What CAPI does**: MongoDB `$graphLookup` → returns `{ metaPageTitle, metaDescription }` for a given category/subcategory. Memcache 1hr.
- **What listing-http-rest needs**: HTTP handler + read SEO fields from MongoDB.
- **Gap**: `CategoryClient` does not project `metaPageTitle` or `metaDescription`. Need to add to structs and MongoDB query projection in `fetchAll()` (line 226).
- **Consumers**: marketplace-graphql (`getCategorySeo` resolver)

### Write Endpoints for Nest Category Manager (Currently Direct MongoDB)

Nest's Category Manager writes **directly to MongoDB** — these operations do NOT go through CAPI. To move these into marketplace-backend, listing-http-rest would need new write endpoints:

#### 13d. Category/SubCategory CRUD
- **`POST /category`** — Add a new subcategory (and parent category if needed). Currently `CategoryManager::addSubCategory()` which calls `insertMongoCategory()` + `insertMongoSubCategory()` on `generalCategoryInProgress`. Uses `idTracker` collection for auto-incrementing IDs.
- **`DELETE /category`** — Remove a subcategory (and parent if empty). Currently `removeSubCategory()` → `removeMongoSubCategory()` + `removeMongoCategory()`.
- **`PUT /category`** — Update category/subcategory fields. Currently `updateCategory()` (lines 404-678, the most complex method). Handles: metaPageTitle, metaDescription, featurePrice, maxPrice, listingFee, listingRentalFee, renewFee, renewRentalFee, limitRenew, maxRenewCount, listingTypes, pricingType, subscription (Stripe price IDs), priceDropThreshold, hiddenSellFormFields. Each field has a corresponding `*Changed` tracking flag.
- **`PUT /category/deprecate`** — Toggle deprecated status. Currently `toggleDeprecated()`.
- **`PUT /category/move`** — Toggle moved status with destination category. Currently `toggleMoved()`.

#### 13e. Staging/Production Workflow
- **`POST /category/copy-prod-to-inprogress`** — Reset staging to match production. Currently `copyProdToInProgress()` → `deleteMany` + `insertMany` from `generalCategory` to `generalCategoryInProgress`.
- **`POST /category/copy-inprogress-to-prod`** — Promote staging to production. Currently `copyInProgressToProd()` → logs changes to `generalLog`, `deleteMany` + `insertMany` from `generalCategoryInProgress` to `generalCategory`, generates `newUntilTime`/`sunsetTime` timestamps, strips `*Changed` flags, clears Memcache keys (`general-categories-main`, `general-categories-seo`).
- **`GET /category/in-progress-changes`** — Get diff between staging and production. Currently `getInProgressChanges()`.

#### 13f. Specification CRUD (Currently Proxied Through CAPI)
- **`GET /sub-categories/specifications`** — Get specs for a subcategory from `generalCategoryInProgress`. Currently in CAPI, called by Nest's Specification Manager via `/classifieds/api` proxy.
- **`POST /sub-categories/specifications`** — Create spec with validation (`SpecificationValidator`). Assigns next available fieldname, sets `specificationsChanged` flag.
- **`PUT /sub-categories/specifications`** — Update spec (cannot change inputType). Validates unique label/slug.
- **`PUT /sub-categories/specifications/weights`** — Reorder spec weights.

### MongoDB Collections Required

| Collection | Current Access | listing-http-rest Status |
|---|---|---|
| `generalCategory` (prod) | Read by CategoryClient | ✅ Already connected |
| `generalCategoryInProgress` (staging) | NOT accessed | ❌ Needs new client |
| `generalLog` (audit) | NOT accessed | ❌ Needs new client |
| `idTracker` (auto-increment) | NOT accessed | ❌ Needs new client |

### Migration Path

**Phase A — Read endpoints (unblocks marketplace-graphql migration)**:
1. Implement 13a, 13b, 13c in listing-http-rest with visibility support
2. Deploy and validate identical responses to CAPI
3. Switch marketplace-graphql `CAPI_URL` to listing-http-rest

**Phase B — Write endpoints (unblocks Nest migration)**:
4. Implement 13d, 13e in listing-http-rest (Category Manager direct writes → new HTTP endpoints)
5. Update Nest's `tools-proxy` to call listing-http-rest instead of MongoDB directly
6. Implement 13f in listing-http-rest (Specification Manager CRUD)
7. Update Nest's `/classifieds/api` CAPI proxy to point to listing-http-rest instead of CAPI

**Phase C — Decommission**:
8. Verify no remaining consumers of CAPI category endpoints
9. Remove CAPI category controller and related code

### Effort Estimate Context

- **13a (`/category-filters`)**: Small — data already cached, just needs HTTP handler + response transformation
- **13c (`/category-seo`)**: Small — add 2 MongoDB fields to projection + structs + handler
- **13b (`/category-tree`)**: Medium — needs options support + optional ES listing counts
- **13d (Category CRUD)**: Medium-Large — complex `updateCategory()` with 15+ fields and change tracking
- **13e (Staging/Prod workflow)**: Medium — bulk copy with timestamp generation and flag stripping
- **13f (Spec CRUD)**: Medium — validation logic, fieldname assignment, weight management

## Non-Goals / Out of Scope

- Migrating existing documents (not needed — missing fields default to publicly visible)
- Faster cache invalidation (5-min CAPI Memcache + 60-min GraphQL go-cache + 12-hour frontend sitemap cache matches current behavior)
- Granular Nest permissions (restricting who can edit visibility flags)
- Adding `devMember` concept to JWT or GraphQL role system
- Homes/Jobs/Mieten verticals — these have separate category systems (`m-ksl-homes`, `m-ksl-jobs`) not managed by the classifieds Category Manager
- Resource center categories — sourced from Contentful, not MongoDB
- Specification CRUD endpoints (POST/PUT) — consumed by Nest, separate migration effort
