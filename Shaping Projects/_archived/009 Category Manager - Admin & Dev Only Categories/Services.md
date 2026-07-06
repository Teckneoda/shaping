# Category Manager - Admin & Dev Only Categories — Services

## Services Modified

### 1. Nest — Category Manager Admin Tool
- **Repo**: `deseretdigital/nest`
- **Language**: PHP (backend) + React/Redux (frontend)
- **Changes**: Add visibility field handling in `CategoryManager.php`, new React components for visibility editing and display
- **Key files**:
  - `classifieds/src/Lib/CategoryManager.php` — Update `updateCategory()` (add `$set` for visibility + `visibilityChanged` flag), `insertMongoCategory()`, `insertMongoSubCategory()` (add default visibility), `copyToCollection()` (strip `visibilityChanged` on prod copy, line ~836)
  - `classifieds/assets/categoryManager/src/config/index.js` — Add Visibility to `rowConfig` with `changedIndicator: 'visibilityChanged'`, scope `['category', 'subCategory']`
  - New: `classifieds/assets/categoryManager/src/components/CategoryEdit/fields/Visibility.js` — Two checkboxes (adminOnly, devOnly), follows `Hidden.js` pattern with Redux dispatch
  - New: `classifieds/assets/categoryManager/src/components/categories/Visibility.js` — Column display with badges/icons
- **Notes**:
  - `copyInProgressToProd()` does full `deleteMany` + `insertMany` — all fields auto-copy, no selective logic needed
  - `generalNestAccess` is all-or-nothing per tool — no granular permission changes needed

### 2. m-ksl-classifieds-api (CAPI) — Category Endpoints (PRODUCTION CRITICAL)
- **Repo**: `deseretdigital/m-ksl-classifieds-api`
- **Language**: PHP (Symfony)
- **Changes**: Filter visibility on category endpoints and search queries
- **Key files**:
  - `src/Controller/CategoryController.php` — Endpoints: `/category-tree`, `/category-filters`, `/category-seo`. Pass caller role context to helper methods.
  - `src/Helper/CategoryHelper.php` — Filter hidden categories from `getCategoryTree()` and `getCategorySeo()` responses. Has Memcache (5-min TTL) — must either cache per-role or filter after cache retrieval.
  - `src/Db/Mongo/GeneralCategoryCollection.php` — `getAllCategoryFilterInformation()` uses `$graphLookup` aggregation. Could add `$match` to exclude hidden categories at the MongoDB level, or filter in PHP after retrieval.
  - `src/Library/Search/ListingsSearch.php` — Add `must_not` terms filter on `category` field in Elasticsearch query builder to exclude listings in hidden categories.
  - `src/Controller/ListingController.php` — `/listings` endpoint. Pass caller role context to search.
- **Notes**:
  - This is the **current production backend** for all category and listing data
  - marketplace-graphql calls CAPI via `CAPI_URL` env var with JWT + nonce auth
  - **`/category-filters` must return ALL categories with visibility metadata (no per-role filtering)** — marketplace-graphql caches this response with single keys shared across all callers. Per-request filtering happens in GraphQL.
  - `/category-tree` and `/category-seo` CAN filter per-role based on JWT — these are not cached with shared single keys in GraphQL
  - Memcache (5-min TTL): cache full data, filter per-request (post-cache filtering) to avoid per-role key multiplication
  - Two-tier caching: Memcache in CAPI (5 min) + go-cache in marketplace-graphql (5 min for filters, 60 min for specs) — visibility changes could take up to 65 minutes to fully propagate

### 3. marketplace-backend — listing-http-rest (Category Tree Filtering)
- **Repo**: `deseretdigital/marketplace-backend`
- **Language**: Go
- **Status**: **Not yet serving production traffic for category endpoints** — prepares for CAPI replacement
- **Changes**: Add `Visibility` struct, populate from MongoDB, add `GetFilteredCategoryTree()` method
- **Key files**:
  - `apps/listing/services/listing-http-rest/internal/client/category.go` — Add `Visibility` struct to category/subcategory models, populate from MongoDB, new `GetFilteredCategoryTree(ctx, isAdmin, isDevMember)` method that filters cached tree at request time
- **Nice-to-Have (Feature 13)**: Add three new HTTP endpoints to replace CAPI's category read endpoints:
  - `GET /category-filters` — Transform cached `CategoryTree` into flat `[{ category, subCategory, specifications[], visibility }]` format. **Smallest gap** — all data already cached in `SubCategoryData` struct.
  - `GET /category-tree` — Expose cached `CategoryTree` with options support (`keyType`, `showSunsetItems`, `hideDeprecated`, `showFields`). `showListingCounts` needs ES aggregation (listing-http-rest has no ES client — could call search-http-rest or add direct ES query). **Largest gap.**
  - `GET /category-seo` — Return `{ metaPageTitle, metaDescription }` for a category/subcategory. **Gap**: `CategoryClient.fetchAll()` (line 226) does not currently project `metaPageTitle` or `metaDescription` from MongoDB — need to add to `CategoryData`/`SubCategoryData` structs and MongoDB query.
  - New file: `apps/listing/services/listing-http-rest/internal/handler/category.go` — HTTP handlers for all three endpoints
  - Update: `apps/listing/services/listing-http-rest/routes.go` — Register new routes

### 4. marketplace-backend — search-http-rest (Search Result Filtering)
- **Repo**: `deseretdigital/marketplace-backend`
- **Language**: Go
- **Status**: **Serving production search traffic.** marketplace-graphql routes 100% of `searchListings` queries here via `SEARCH_URL` (rollout at 10,000/10,000 in `legacy-listing.go:379`)
- **Changes**: Cache hidden category IDs, add `MustNot` exclusion filter to search queries
- **Key files**:
  - `apps/listing/services/search-http-rest/internal/store/elastic/query.go` — Add `MustNot` terms filter in `getClassifiedQueryFilters()` to exclude hidden categories (follows existing `isDevMember` exclusion pattern)
  - `apps/listing/services/search-http-rest/internal/domain/es6/es6.go` — Add `SimpleCache` for hidden category IDs loaded from category tree
- **Notes**:
  - No Elasticsearch schema change or reindex needed
  - Uses existing `FilterContainer.MustNot` pattern and `SimpleCache` infrastructure
  - marketplace-graphql calls this service via `services/search/client.go` → POST `{SEARCH_URL}/listings`

### 5. marketplace-backend — listing-http-ai-analyze (AI Category Suggestions)
- **Repo**: `deseretdigital/marketplace-backend`
- **Language**: Go
- **Changes**: Per-request taxonomy filtering before AI prompt construction
- **Key files**:
  - Handler that builds AI prompt — filter cached taxonomy to exclude hidden categories before sending to AI
- **Notes**:
  - Background taxonomy refresh (no request context) keeps full cache
  - Filtering happens per-request in the handler, not in the cache

### 6. marketplace-graphql (Required Per-Request Filtering)
- **Repo**: `deseretdigital/marketplace-graphql`
- **Language**: Go + GraphQL
- **Status**: **Required filtering layer** — because CAPI `/category-filters` returns all categories with visibility metadata (to support single-key caching), GraphQL must do per-request filtering
- **Changes**: Add `CategoryVisibility` type, update internal client structs, add per-request filtering in resolvers
- **Key files**:
  - `graph/schema/types.categories.graphqls` — New `CategoryVisibility` type
  - `services/capi/category.go` — Add `Visibility` struct to category structs
  - `graph/queryresolvers/legacy-searchfilters-classifieds.go` — **Primary filtering point**: Add visibility check in `prepareClassifiedsCategoryOptions()` loop (line 641). Also update `ClassifiedsCategoryFilter` struct (line 48) with `AdminOnly bool` and `DevOnly bool` fields. The `fetchClassifiedsCategoryOptions()` go-cache (5-min, single key `AllClassifiedsFilters`) continues to cache full unfiltered response.
  - `services/capi/specifications.go` — Update `CacheCategory` struct (line 36) with visibility fields. Add visibility check in `GetSpecifications()` (line 138). Signature change needed to accept caller context. The 60-min cache + `singleflight.Group` continues to cache full data (calls CAPI with empty JWT).
  - `graph/queryresolvers/legacy-listing.go` — `SearchListings()` routes to search-http-rest (100% rollout) via `services/search/client.go`
  - `services/search/client.go` — HTTP client for search-http-rest, calls POST `{SEARCH_URL}/listings`
- **Notes**:
  - `@hasRole` directive only validates token existence, not actual role — filtering must check JWT `Role` field directly
  - No `devMember` concept in GraphQL — `isDevMember` must be derived from JWT or passed as a parameter
  - `/category-tree` and `/category-seo` paths are filtered by CAPI (not single-key cached in GraphQL) — no GraphQL filtering needed for those
  - When `CAPI_URL` switches from m-ksl-classifieds-api to listing-http-rest, no GraphQL code changes needed

### 7. marketplace-frontend — Sitemap Generation
- **Repo**: `deseretdigital/marketplace-frontend` (not in project.json — frontend repo)
- **Language**: TypeScript (Next.js)
- **Status**: **Serving production traffic** — generates sitemaps for search engines
- **Changes**: No code changes needed IF GraphQL filters hidden categories from AvailableFilters
- **Key files**:
  - `apps/ksl-marketplace/app/search/sitemap.ts` — Calls `fetchFilters({ includeAllOptions: true })` → GraphQL `AvailableFilters` → CAPI `/category-filters`. Iterates all category/subcategory options, generates sitemap URLs like `/search/cat/X/sub/Y`
- **Notes**:
  - 12-hour sitemap cache (`sitemapCache`) — hidden categories persist in sitemap up to 12 hours after backend filters them
  - `VERTICAL_CONFIG_MAPPING["CLASSIFIED"] = ["cat", "sub", "marketType"]` controls which filter keys become sitemap URLs
  - No code change required because sitemap gets categories from GraphQL AvailableFilters — if GraphQL filters them, they're excluded

### 8. Legacy Classifieds Sitemap Generator (m-ksl-classifieds)
- **Repo**: `deseretdigital/m-ksl-classifieds` (not in project.json — legacy repo)
- **Language**: PHP
- **Status**: **Serving production traffic** — generates XML sitemaps via cron
- **Changes**: Add `must_not` filter on hidden category IDs to ES aggregation queries
- **Key files**:
  - `util/sitemap/classes/Sitemap.php` — `generateCatSitemap()` (line 247), `generateCatSubCatSitemap()` (line 329), `generateCatSubCatStateSitemap()` (line 519), `generateCatSubCatStateCitySitemap()` (line 617), `generateCatSubCatZipSitemap()` (line 815)
  - `util/sitemap/createAllSitemaps.php` — Cron entry point that calls all generators
- **Notes**:
  - **Queries Elasticsearch directly** via `/classifieds/general/listing/elasticSearch` — bypasses CAPI entirely
  - Uses ES `terms` aggregation on `category` field to discover which categories have active listings
  - CAPI filtering does NOT protect this path — must add its own filtering
  - Needs to either: (a) add `must_not` terms filter on hidden category IDs to ES queries, or (b) fetch hidden category list from MongoDB and post-filter aggregation results

## Services NOT Modified

### marketplace-frontend — Display Components
- **Reason**: All category display surfaces (filter dropdowns, breadcrumbs, SEO metadata, listing detail, sell flow, similar results) consume data from GraphQL. If GraphQL filters hidden categories, the frontend automatically excludes them.
- **Impact**: No frontend code changes needed — backend filtering propagates through the entire pipeline
- **Key surfaces**: `SelectFilter.tsx`, `SearchBreadcrumbs.tsx`, `ServicesCategoryList.tsx`, `metadata.ts`, `fetch-category-seo.ts`, `ListingSchema.tsx`, `FieldSuggestedCategories.tsx`, `SimilarResults.tsx`

### m-ksl-homes, m-ksl-jobs, mieten
- **Reason**: Separate category systems not managed by the classifieds Category Manager
- **Impact**: None — these verticals have their own category data (Homes uses hardcoded IDs, Jobs uses BaseOptions constants)

### m-ksl-generalfeeds (Feed Parsers)
- **Reason**: Feed parsers import external listings into KSL categories. They don't serve category data to users.
- **Impact**: A feed could import a listing into a hidden category — that listing would simply be hidden from non-admin/non-dev search results by the search filtering (Feature 4/6). No feed parser changes needed.

## Data Stores Affected

### MongoDB
- **Collections**: `generalCategory`, `generalCategoryInProgress` (and `*Dev` variants)
- **Change**: New `visibility` field on category and subCategory documents: `{ adminOnly: bool, devOnly: bool }`
- **Migration**: None required (additive, missing = publicly visible)
- **Read by**: Nest (write), m-ksl-classifieds-api (read, production), listing-http-rest (read, not yet production)

### Elasticsearch
- **Change**: None — filtering done at query time via `must_not` terms filter in both CAPI and search-http-rest
- **Queried by**: search-http-rest (production search via marketplace-graphql), m-ksl-classifieds-api (legacy search path, may still have direct consumers)

### Memcache
- **Used by**: m-ksl-classifieds-api CategoryHelper (5-min TTL)
- **Impact**: May need per-role cache keys or post-cache filtering to serve different results to admin vs regular users
