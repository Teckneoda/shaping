# Category Feature Flagging — Services

## Services Modified

### 1. marketplace-graphql (PRIMARY — Category Filtering)
- **Repo**: `deseretdigital/marketplace-graphql`
- **Language**: Go + GraphQL
- **Status**: **Serving production traffic** — all frontend category data flows through here
- **Changes**: Add per-request category filtering using existing Remote Config feature gating
- **Key files**:
  - `graph/queryresolvers/featureconfig.go` (line 32) — Add `"CategoryVisibility"` to `allowedFeatures` map with `EnabledKey` and `AllowListKey`
  - `graph/queryresolvers/legacy-searchfilters-classifieds.go` (line 636) — Filter Jobs category in `prepareClassifiedsCategoryOptions()` loop based on Remote Config gate + member ID
  - `services/capi/specifications.go` (line 116) — Filter Jobs in `GetSpecifications()` with caller context (signature change)
  - `services/capi/category.go` (line 86) — Filter Jobs in `GetCategorySeo()` for non-allowlisted callers
- **Existing infrastructure used**:
  - `services/remoteconfig/remoteconfig.go` — `IsFeatureEnabled()` with member ID allowlist (line 93)
  - `middleware.go` — Member ID extraction from JWT into context (line 107)
  - `graph/queryresolvers/featureconfig.go` — `FeatureConfig` pattern with `AllowListKey`
- **Notes**:
  - Caching is safe: go-cache (5-min) and SpecificationsClient (60-min) cache full unfiltered data. Filtering is per-request in resolvers.
  - Same caching strategy as #9 — no difference in cache behavior
  - Categories identified by string name (e.g., `"Jobs"`) — matched against `d.Category` field

### 2. marketplace-backend — search-http-rest (Search Result Filtering)
- **Repo**: `deseretdigital/marketplace-backend`
- **Language**: Go
- **Status**: **Serving production search traffic** — 100% of `searchListings` queries
- **Changes**: Add env-var-based category exclusion filter with member ID allowlist
- **Key files**:
  - `apps/listing/services/search-http-rest/main.go` (line 27) — Add `HIDDEN_CATEGORIES`, `HIDDEN_CATEGORY_ALLOWLIST_MEMBER_IDS`, `HIDDEN_CATEGORIES_ENABLED` env vars
  - `apps/listing/services/search-http-rest/internal/store/elastic/query.go` (line 618) — Add `MustNot` terms filter on `category` field in `getClassifiedQueryFilters()`
  - `apps/listing/services/search-http-rest/internal/domain/es6/es6.go` (line 105) — Thread memberID through `searchClassifieds()` to query builder
  - `apps/listing/services/search-http-rest/internal/handler/search.go` (line 41) — memberID already extracted here
- **Existing patterns used**:
  - `isDevMember` MustNot exclusion pattern (query.go line 345)
  - `parseAllowlistMemberIDs()` from listing-ps-price-drop (line 67)
  - `FilterContainer.MustNot` array (query.go line 475)
- **Notes**:
  - No Elasticsearch schema change — query-time filtering only
  - ES field is `category` (string), e.g., `"Jobs"`
  - Member ID available in handler but needs threading to query builder (small plumbing change)

### 3. marketplace-backend — listing-http-ai-analyze (AI Category Suggestions)
- **Repo**: `deseretdigital/marketplace-backend`
- **Language**: Go
- **Status**: **May be serving production traffic** — needs confirmation
- **Changes**: Per-request filtering of cached taxonomy before building AI prompt
- **Key files**:
  - Handler that builds AI prompt — filter cached taxonomy to exclude Jobs categories before sending to AI
  - `main.go` — Add `HIDDEN_CATEGORIES`, `HIDDEN_CATEGORY_ALLOWLIST_MEMBER_IDS` env vars (same pattern as search-http-rest)
- **Notes**:
  - Background taxonomy refresh (no request context) keeps full cache
  - Filtering happens per-request in the handler, not in the cache
  - Without this, AI could suggest Jobs categories to non-allowlisted users
  - Same env var pattern as search-http-rest — small effort

## Services NOT Modified

### Nest — Category Manager Admin Tool
- **Reason**: Admin-only tool, not public-facing. Categories managed via existing CRUD. Visibility controlled externally via Remote Config, not via category document fields.
- **Impact**: None — admins always see all categories in Nest

### m-ksl-classifieds-api (CAPI) — Category Endpoints
- **Reason**: Filtering happens downstream in marketplace-graphql. CAPI continues to return all categories (including Jobs) to GraphQL, which then filters per-request. This avoids touching production-critical legacy PHP code.
- **Impact**: None — CAPI behavior unchanged
- **Trade-off**: If any consumer calls CAPI directly (bypassing GraphQL), they would see Jobs categories. This is acceptable because CAPI is an internal API only called by marketplace-graphql.

### marketplace-backend — listing-http-rest
- **Reason**: Not yet serving production traffic for category endpoints. When it replaces CAPI, filtering will still happen in GraphQL.
- **Impact**: None for now — can add filtering when it goes production

### marketplace-frontend
- **Reason**: All frontend surfaces consume GraphQL. Backend filtering propagates automatically.
- **Impact**: None — no frontend code changes

## Data Stores Affected

### Firebase Remote Config
- **Change**: Two new parameters:
  - `CLASSIFIED_jobs_category_hidden` (boolean)
  - `CLASSIFIED_jobs_category_allowed_member_ids` (JSON array of member IDs)
- **Managed via**: Firebase Console (no deployment needed to change allowlist)

### Elasticsearch
- **Change**: None — query-time `must_not` filtering only
- **No reindex needed**

### MongoDB
- **Change**: None — no schema changes to category documents

### Memcache
- **Change**: None — CAPI caching behavior unchanged
