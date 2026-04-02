# Planning State — Category Manager - Admin & Dev Only Categories

## Identified So Far

### Current Category Architecture
- Categories stored in MongoDB `generalCategory` (prod) and `generalCategoryInProgress` (staging)
- Two-level hierarchy: `category` (parent) → `subCategory` (child via `parent_id`)
- No visibility/permissions concept exists at the category level in any repo
- Access to the Category Manager tool in Nest is binary (all-or-nothing via `generalNestAccess`)

### Production Data Flow
- **Frontend → marketplace-graphql → m-ksl-classifieds-api (CAPI) → MongoDB/Elasticsearch**
- marketplace-graphql's `services/capi/` directory is an internal HTTP client for m-ksl-classifieds-api (configured via `CAPI_URL` env var)
- CAPI authenticates requests via JWT + HMAC nonce from marketplace-graphql
- listing-http-rest (marketplace-backend) is **not yet serving production traffic** — it will eventually replace CAPI
- Both CAPI and listing-http-rest read from the same MongoDB collections

### Existing User Role Systems
- **Nest**: `dev`, `po`, `qa`, `adops`, `sales-admin` roles (email-based in `UserAccess.php`, 17 devs listed)
- **marketplace-backend**: Bouncer has `root`, `admin`, `service`, `guest`, `nobody` roles; search service has existing `isDevMember` flag for filtering dev-only listings
- **marketplace-graphql**: `GUEST`, `MEMBER`, `ADMIN` GraphQL enum; JWT roles include `root`, `admin`, `sales`, `member`, `guest`
- **m-ksl-classifieds-api**: Receives JWT from marketplace-graphql containing role information
- **Key**: `isDevMember` concept already exists in marketplace-backend search service — dev members see listings marked `isDevMemberListing: true`

### Nest (Admin Tool)
- Full CRUD via `CategoryManager.php` (1,255 lines) with staging/prod workflow
- React/Redux frontend with configurable `rowConfig` for fields
- API routes at `/classifieds/tools-proxy/category-manager/*`
- Existing pattern for adding new fields: config entry + edit component + column component + changed indicator
- `copyInProgressToProd()` does full `deleteMany` + `insertMany` — all fields auto-copy
- `visibilityChanged` flag must be stripped on copy (add to removal list in `copyToCollection()` at line ~836)
- `Hidden.js` component is closest analog for the Visibility edit component (toggle-based with icons)
- `generalNestAccess` is email-list-based per tool — no granular permissions exist

### m-ksl-classifieds-api (CAPI) — PRODUCTION
- Symfony PHP application serving all classifieds category and listing data
- **Category endpoints**: `/category-tree` (5-min Memcache), `/category-filters` (MongoDB `$graphLookup` aggregation), `/category-seo`
- **Search endpoint**: `/listings` — queries Elasticsearch `general` index with `term` filters on `category`/`subCategory` fields
- **Caching**: `CategoryHelper` uses Memcache with 5-min TTL, keyed by `md5(json_encode(options))`
- **MongoDB access**: `GeneralCategoryCollection` reads from `generalCategory` collection
- **Key files**: `CategoryController.php`, `CategoryHelper.php`, `GeneralCategoryCollection.php`, `ListingsSearch.php`, `ListingController.php`
- marketplace-graphql caches CAPI responses for an additional 60 min via go-cache

### marketplace-backend — listing-http-rest (NOT YET PRODUCTION)
- Read-only `CategoryClient` in `listing-http-rest` reads from MongoDB with 60-min in-memory cache
- No category management endpoints — only listing CRUD
- Admin callers identified via `member.Admin()` in bouncer system
- Categories consumed by: listing-http-rest, listing-http-extractor-rest, listing-http-ai-analyze, search-http-rest

### marketplace-backend — search-http-rest (PRODUCTION — SEARCH)
- Does NOT use `CategoryClient` — categories are string filters in Elasticsearch
- Existing `MustNot` exclusion pattern: `isDevMember` boolean on request → `MustNot` filter in query builder (`getCarQueryFilters()`)
- `FilterContainer` struct has `Must`, `MustNot`, `Filter` arrays combined into final bool query
- ES field names: `category` (string), `subCategory` (string), `specSubCatString1-10`
- Existing `SimpleCache` pattern available for caching hidden category IDs
- **No ES schema change needed** — use `terms` `MustNot` filter on `category` field at query time
- Key files: `query.go` (`getClassifiedQueryFilters`), `es6.go` (cache setup), `model.go` (ES field mapping)
- **marketplace-graphql routes 100% of `searchListings` queries here** via `SEARCH_URL` env var (rollout at 10,000/10,000 in `legacy-listing.go:379`)
- Data flow: Frontend → marketplace-graphql (`SearchListings()`) → `services/search/client.go` → POST `{SEARCH_URL}/listings` → search-http-rest → Elasticsearch

### marketplace-backend — listing-http-ai-analyze
- Fetches full taxonomy from GraphQL via background refresh (no request context)
- AI would currently suggest hidden categories to users
- Fix: filter taxonomy per-request in handler before building AI prompt

### marketplace-graphql
- Category queries: `getCategorySeo`, `getCategorySpecifications`, `getClassifiedsConditionalFields`, `getSuggestedCategories`
- Role-based access via `@hasRole` directive — only validates token existence, NOT actual role claim
- JWT contains `Role` field (`root`, `admin`, `sales`, `member`, `guest`)
- No `devMember` concept exists in GraphQL
- Reads from m-ksl-classifieds-api endpoints: `/category-tree`, `/category-seo`, `/category-filters` (via internal `services/capi/` client)
- `fetchClassifiedsCategoryOptions()` in `legacy-searchfilters-classifieds.go` caches category filters for 60 min via go-cache
- No mutations for category management
- GraphQL filtering will be defense-in-depth — m-ksl-classifieds-api (and later listing-http-rest) does authoritative filtering

### Implementation Plan
- 4-phase rollout: Nest UI → CAPI category filtering + search-http-rest search filtering (both production) → listing-http-rest category filtering (pre-production) → GraphQL filtering (defense-in-depth)
- Visibility stored as `{ adminOnly: bool, devOnly: bool }` on each document
- `devOnly` means visible to users with dev member permissions (reuses existing `isDevMember` concept), NOT environment-based
- `adminOnly` means visible only to admin/root users
- Filtering at request time (not cache time) so single cache serves all callers
- Cascading visibility: hidden parent hides all children
- Search filtering via `must_not` terms filter in both CAPI and search-http-rest — no ES schema change
- Listings in hidden categories excluded from search results for non-admin/non-dev users

### Resolved Design Decisions
- **Cascading**: Hidden parent hides all children (simplest, safest)
- **Existing listings in hidden categories**: Hidden from search results via `must_not` filter
- **Cache delay**: 5-min CAPI Memcache + 60-min GraphQL go-cache is acceptable (matches current behavior)
- **Additional visibility states**: Not needed — two booleans cover use cases
- **GraphQL dev member**: Backend-only filtering — no JWT changes, no new GraphQL role
- **Nest permissions**: No granular changes — all category manager users can toggle visibility
- **ES schema**: No change needed — query-time filtering sufficient
- **Dual implementation**: Both CAPI (PHP) and listing-http-rest (Go) need filtering — same MongoDB, two codebases
- **GraphQL caching strategy — CAPI returns full data, GraphQL filters per-request**:
  - CAPI `/category-filters` must return ALL categories (including hidden ones) with `visibility` metadata on each entry
  - GraphQL caches the **complete unfiltered response** — both caches (5-min go-cache and 60-min SpecificationsClient) work unchanged
  - Filtering happens **per-request** in GraphQL resolvers based on caller's JWT role
  - **Reason**: GraphQL has two independent caches that share a single cache key for all callers:
    - `fetchClassifiedsCategoryOptions()` uses single key `AllClassifiedsFilters` in go-cache (5-min TTL). First caller after expiry populates the cache with their JWT — if CAPI filtered per-role, all subsequent callers would see that role's filtered view for 5 minutes.
    - `SpecificationsClient` calls CAPI with **empty `JWTTokens{}`** (no user context) and caches for 60 min. If CAPI filtered per-role, this would always get the anonymous/unauthenticated view.
  - **Implementation**: Add visibility check in `prepareClassifiedsCategoryOptions()` loop (line 641): skip entries where `d.AdminOnly && !isAdmin` or `d.DevOnly && !isDevMember`. Add similar check in `SpecificationsClient.GetSpecifications()` (line 138) before returning specs for a hidden category. Extract caller role from JWT in request context (existing pattern at line 586).
  - **CAPI Memcache same pattern**: CAPI should also cache full data and filter per-request (post-cache filtering), since per-role cache keys would multiply entries

### marketplace-frontend — Category Display Architecture
- **All category display surfaces consume data from GraphQL → CAPI pipeline** — no independent category data sources
- **Sitemap generation** (`app/search/sitemap.ts`): Calls `fetchFilters({ includeAllOptions: true })` → GraphQL `AvailableFilters` → CAPI `/category-filters`. Generates URLs for all category/subcategory combinations. 12-hour cache. Automatically excludes hidden categories if GraphQL filters them. **No frontend code change needed.**
- **Filter UI** (`Filters/SelectFilter.tsx`, `Filters/FilterComponent.tsx`): Renders category/subcategory as `SelectFilterComponent` dropdowns from `AvailableFilters`. **No code change needed.**
- **Search breadcrumbs** (`Search/SearchBreadcrumbs.tsx`): Shows category in trail for classified searches. **No code change needed.**
- **SEO metadata** (`search/services/metadata.ts`, `search/[[...slug]]/actions/fetch-category-seo.ts`): Uses `fetchCategorySeoCached()` from CAPI `/category-seo`. **No code change needed.**
- **Listing detail schema** (`listing/[id]/components/ListingSchema.tsx`): Uses `listing.subCategory` in structured data. Listings in hidden categories still show their category if accessed directly — expected behavior.
- **Sell flow** (`sell/post-a-listing/components/Fields/FieldSuggestedCategories.tsx`): Shows AI-suggested categories from `getSuggestedCategories` GraphQL query. Depends on Feature 7.
- **URL routing** (`search/services/url-parameters.ts`): Direct navigation to hidden category URL returns empty results — acceptable.
- **Similar results** (`Search/SimilarResults.tsx`): Backend filtering handles this.

### GraphQL — AvailableFilters Architecture (Deep Dive)
- **`AvailableFilters`** typed as `[SearchFilterGroup]` in `types.search.graphqls`
- For CLASSIFIED: category returned as two `SelectFilterComponent` items (name: "category", name: "subCategory") in first `SearchFilterGroup`
- **Data flow**: `AvailableFilters` resolver → `getClassifiedFilters()` → `fetchClassifiedsCategoryOptions()` → CAPI `/category-filters` → cached 5 min in go-cache (key: `all-classifieds-filters`)
- **`prepareClassifiedsCategoryOptions()`** (line 636): Builds option lists. No visibility filtering currently. Defense-in-depth filtering should be added here.
- **SpecificationsClient** (`services/capi/specifications.go`): Separate singleton, 60-min cache + `singleflight.Group`. Calls same CAPI `/category-filters` endpoint. `GetSpecifications(category, subCategory)` should not return specs for hidden categories.
- **Two separate caches**: (1) go-cache in `fetchClassifiedsCategoryOptions` (5-min), (2) `SpecificationsClient` (60-min). Both from same CAPI endpoint.
- **Existing filtering pattern**: `prepareSubCatSpecifications()` (line 686) filters by `Status == "Active"` — reusable for visibility.

### Legacy Classifieds Sitemap Generator (m-ksl-classifieds)
- **Queries Elasticsearch directly** — does NOT go through CAPI
- `Sitemap.php`: `generateCatSitemap()`, `generateCatSubCatSitemap()`, `generateCatSubCatStateSitemap()`, `generateCatSubCatStateCitySitemap()`, `generateCatSubCatZipSitemap()`
- Uses ES `terms` aggregation on `category` field — bypasses CAPI filtering
- Called via `createAllSitemaps.php` cron
- **Gap**: CAPI filtering does NOT protect this path. Needs its own `must_not` filter on hidden category IDs.

### Legacy Systems Confirmed NOT Affected
- **m-ksl-homes**: Own category system (hardcoded IDs 275, 276, 278, etc.) — separate from classifieds
- **m-ksl-jobs**: Own category system (`BaseOptions::CATEGORY_DATA`, 45 job categories) — separate
- **mieten**: Rent vertical with own category model — separate
- **m-ksl-generalfeeds**: Feed parsers import listings but don't serve category data. Listings in hidden categories filtered at search time.
- **m-ksl-myaccount / m-ksl-myaccount-v2**: Data comes through GraphQL pipeline

## Still Needs Research
- How CAPI extracts role/admin/devMember status from the JWT it receives — need to confirm the JWT contains enough info for visibility filtering
- Whether CAPI Memcache should use per-role cache keys or filter after cache retrieval (per-role keys are simpler but multiply cache entries)
- Exact handler/function in `listing-http-ai-analyze` where taxonomy is filtered before AI prompt (need to identify the specific file and function)
- Whether `listing-http-extractor-rest` uses the category tree in a way that needs filtering
- Whether the legacy sitemap generator (`m-ksl-classifieds/util/sitemap/`) is still actively deployed or if `marketplace-frontend` sitemap has replaced it

## Unanswered Questions
- Is the legacy sitemap generator (`m-ksl-classifieds/util/sitemap/`) still running in production? This determines whether Feature 11 is needed.

## Research Sources Consulted
- [deseretdigital/marketplace-backend](https://github.com/deseretdigital/marketplace-backend) — Explored `listing-http-rest` CategoryClient, bouncer, routes, domain logic, search `isDevMember` pattern; search-http-rest query builder, `MustNot` pattern, `SimpleCache`, ES model/field mapping; listing-http-ai-analyze taxonomy handling
- [deseretdigital/marketplace-graphql](https://github.com/deseretdigital/marketplace-graphql) — Explored category schema, resolvers, internal m-ksl-classifieds-api client (`services/capi/`), `CAPI_URL` env var, role directives, JWT member attributes, `@hasRole` implementation, `fetchClassifiedsCategoryOptions()` go-cache, SpecificationsClient (60-min cache, singleflight), AvailableFilters resolver chain, prepareClassifiedsCategoryOptions, prepareSubCatSpecifications filtering pattern
- [deseretdigital/nest](https://github.com/deseretdigital/nest) — Explored CategoryManager.php (CRUD, staging/prod copy, changed indicators), React frontend (rowConfig, edit components, Hidden.js pattern), access control (generalNestAccess, UserAccess.php role system), MongoDB schema
- [deseretdigital/m-ksl-classifieds-api](https://github.com/deseretdigital/m-ksl-classifieds-api) — Explored CategoryController, CategoryHelper (Memcache caching), GeneralCategoryCollection (MongoDB aggregation), ListingsSearch (Elasticsearch query builder), ListingController, HomepageController (hardcoded category 349), routes.yaml
- [marketplace-frontend](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend) — Explored sitemap generation, filter UI components, breadcrumbs, SEO metadata, listing detail schema, sell flow, similar results, URL routing. All surfaces consume GraphQL → CAPI pipeline.
- [m-ksl-classifieds](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds) — Explored legacy sitemap generator (Sitemap.php, createAllSitemaps.php) that queries ES directly, bypassing CAPI
- **Legacy repos confirmed NOT affected**: m-ksl-homes, m-ksl-jobs, mieten, m-ksl-generalfeeds, m-ksl-myaccount, m-ksl-myaccount-v2
