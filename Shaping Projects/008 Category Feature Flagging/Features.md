# Category Feature Flagging — Features

## Overview

Alternative to [Project #9 (Admin & Dev Only Categories)](file:///Users/cpies/code/shaping/Shaping%20Projects/009%20Category%20Manager%20-%20Admin%20%26%20Dev%20Only%20Categories). Instead of adding visibility flags to MongoDB category documents and filtering across the full stack, this approach uses **existing Remote Config infrastructure** in marketplace-graphql and **environment variable allowlists** in search-http-rest to hide specific categories (initially Jobs) from users not on a member ID allowlist.

**Key difference from #9**: No MongoDB schema changes, no CAPI changes, no Nest UI changes. Filtering happens at the GraphQL and search layers only, using configuration rather than data model changes.

## Feature 1: Remote Config Feature Gate — Category Visibility

Add a new feature gate in marketplace-graphql's existing Remote Config infrastructure to control which categories are hidden and which member IDs can see them.

**Implementation**:
- Add new entry to `allowedFeatures` map in [`featureconfig.go`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/queryresolvers/featureconfig.go) (line 32):
  - Feature key: `"CategoryVisibility"` (or `"JobsCategoryAccess"`)
  - `EnabledKey`: `"CLASSIFIED_jobs_category_hidden"` — boolean, when `true` the Jobs category is hidden from non-allowlisted users
  - `AllowListKey`: `"CLASSIFIED_jobs_category_allowed_member_ids"` — JSON array of member IDs who can see Jobs
  - `UseIdentifier`: `IdentifierTypeMemberId`
  - `EnableOnDevelopment`: `false` (so dev environment matches prod behavior for testing)
- Uses existing [`IsFeatureEnabled()`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/remoteconfig/remoteconfig.go) (line 93) which already handles:
  - Boolean feature flag check
  - Member ID allowlist parsing (JSON array or comma-separated)
  - Development environment override
  - Hardcoded override for emergencies

**No new infrastructure needed** — this is a configuration-only change using existing patterns.

## Feature 2: GraphQL Filtering — AvailableFilters (Category Dropdowns)

Filter Jobs category and its subcategories from the `AvailableFilters` response in marketplace-graphql so they don't appear in frontend category dropdowns.

**Implementation**:
- In [`prepareClassifiedsCategoryOptions()`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/queryresolvers/legacy-searchfilters-classifieds.go) (line 636):
  - Extract member ID from context (existing pattern at line 358 of `legacy-listing.go`)
  - Call `IsFeatureEnabled()` with the CategoryVisibility gate config
  - If feature is enabled AND member is NOT on the allowlist: skip entries where `d.Category == "Jobs"` in the loop at line 641
- **Caching is safe**: The go-cache (5-min, single key `AllClassifiedsFilters`) caches the **full unfiltered** CAPI response. Filtering happens per-request in `prepareClassifiedsCategoryOptions()`, which runs on every resolver call after cache hit. This is the exact same pattern #9 uses.

## Feature 3: GraphQL Filtering — Specifications

Prevent specifications for Jobs subcategories from being returned to non-allowlisted users.

**Implementation**:
- In [`SpecificationsClient.GetSpecifications()`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/capi/specifications.go) (line 116):
  - Add caller context parameter (signature change needed — same as #9)
  - Before returning specs for a category, check if it's Jobs and if the caller is on the allowlist
  - The 60-min cache + `singleflight.Group` continues to cache full data (calls CAPI with empty JWT)
  - Per-request filtering in `GetSpecifications()` before returning

## Feature 4: GraphQL Filtering — Category SEO

Prevent SEO metadata for Jobs categories from being served to non-allowlisted users.

**Implementation**:
- In [`GetCategorySeo()`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/capi/category.go) (line 86):
  - Check if the requested category is Jobs
  - If feature is enabled and caller not on allowlist, return empty/nil
  - This prevents `fetchCategorySeoCached()` in the frontend from generating meta tags for Jobs

## Feature 5: Search Filtering — search-http-rest (PRODUCTION)

Prevent listings in the Jobs category from appearing in search results for non-allowlisted users. This is the **production-critical** search path — marketplace-graphql routes 100% of `searchListings` queries here.

**Implementation**:
- Add environment variables to search-http-rest config (following existing [`listing-ps-price-drop`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-ps-price-drop/main.go) pattern, lines 41-44):
  - `HIDDEN_CATEGORIES`: comma-separated category names to hide (e.g., `"Jobs"`)
  - `HIDDEN_CATEGORY_ALLOWLIST_MEMBER_IDS`: comma-separated member IDs who can see hidden categories
  - `HIDDEN_CATEGORIES_ENABLED`: boolean feature flag (default `false`)
- Parse allowlist at startup using same pattern as `parseAllowlistMemberIDs()` (line 67 of listing-ps-price-drop)
- In [`getClassifiedQueryFilters()`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/search-http-rest/internal/store/elastic/query.go) (around line 618):
  - If feature is enabled AND memberID NOT in allowlist:
  - Add `MustNot` terms filter: `{ "terms": { "category": ["Jobs"] } }`
  - Follows existing `isDevMember` exclusion pattern at line 345
- **Member ID flow**: Already available — handler extracts memberID from token at [search.go:41](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/search-http-rest/internal/handler/search.go), passed through domain layer to query builder
  - **Gap**: memberID currently passed to domain but NOT forwarded to `CreateESQueryFromFilters()`. Need to thread it through `searchClassifieds()` in [es6.go:105](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/search-http-rest/internal/domain/es6/es6.go)

## Feature 6: Frontend — Sitemap Generation (Automatic)

**No code changes needed.** The marketplace-frontend sitemap generator calls GraphQL `AvailableFilters`, which will be filtered by Feature 2. Hidden categories automatically excluded from sitemaps.

- 12-hour sitemap cache means hidden categories could persist up to 12 hours after enabling the feature flag
- Same behavior as #9

## Feature 7: Legacy Sitemap Generator (m-ksl-classifieds)

Same as #9's Feature 11 — the legacy sitemap queries Elasticsearch directly, bypassing both CAPI and GraphQL.

**Implementation** (if legacy sitemap is still running):
- Add `must_not` filter on hidden category names to ES aggregation queries in [`Sitemap.php`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds/util/sitemap/classes/Sitemap.php)
- OR: Read hidden categories from an environment variable / config file
- This is the same work regardless of #8 vs #9

## Non-Goals / Out of Scope

- MongoDB schema changes (no `visibility` field on category documents)
- CAPI changes (filtering happens downstream in GraphQL)
- Nest UI changes (no visibility toggles — managed via Remote Config / Firebase console)
- General-purpose category visibility (this is targeted at specific categories, not a reusable system)
- AI category suggestions filtering (listing-http-ai-analyze) — not in production, not needed
- listing-http-rest category tree filtering (not yet serving production traffic)
