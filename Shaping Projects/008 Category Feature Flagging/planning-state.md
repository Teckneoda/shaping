# Planning State — Category Feature Flagging

## Identified So Far

### Core Concept
Instead of adding `visibility` flags to MongoDB category documents (#9's approach), use **existing Remote Config + member ID allowlist infrastructure** in marketplace-graphql and **environment variable allowlists** in search-http-rest to hide specific categories (Jobs) from non-allowlisted users.

### Existing Infrastructure That Supports This Approach

1. **Remote Config Feature Gating** (marketplace-graphql):
   - `RemoteConfigService.IsFeatureEnabled()` in `services/remoteconfig/remoteconfig.go` (line 93) already supports:
     - Boolean feature flag evaluation
     - Member ID allowlist parsing (JSON array or comma-separated)
     - Development environment override
     - Hardcoded override for emergencies
   - `FeatureConfig` pattern in `graph/queryresolvers/featureconfig.go` (line 32) — hardcoded map of allowed feature gates with `EnabledKey`, `AllowListKey`, `UseIdentifier`
   - Currently used for `ClassifiedsUnifiedPal` feature

2. **Member ID Flow** (marketplace-graphql):
   - JWT parsed in `middleware.go` (line 49) via `AddRequestToContext()`
   - Member ID set in context at line 107: `context.WithValue(ctx, memberIdKey, memberId)`
   - Available in resolvers via `ctx.Value(MemberIdKey).(int64)`
   - Example usage: `legacy-listing.go` line 358

3. **Allowlist Pattern** (marketplace-backend):
   - `listing-ps-price-drop/main.go` (lines 41-91) has `PRICE_DROP_ALLOWLIST_MEMBER_IDS` env var pattern
   - `parseAllowlistMemberIDs()` parses comma-separated member IDs into a set
   - Feature flag + allowlist combination with full rollout toggle

4. **MustNot Exclusion Pattern** (search-http-rest):
   - `isDevMember` pattern in `query.go` (line 345): `MustNot = append(MustNot, '{ "match": { "isDevMemberListing": true } }')`
   - `FilterContainer` struct (line 475) with `Must`, `MustNot`, `Filter` arrays
   - Category field in ES is `category` (string), e.g., `"Jobs"`

### Category Data Flow (Where Filtering Must Happen)

1. **AvailableFilters (category dropdowns)**: Frontend → GraphQL `AvailableFilters` → `prepareClassifiedsCategoryOptions()` → CAPI `/category-filters` → MongoDB
   - **Filter point**: `prepareClassifiedsCategoryOptions()` loop (line 641) — skip `d.Category == "Jobs"` entries
   - Cache (5-min go-cache, single key) stores full data; filtering is per-request in the resolver

2. **Specifications**: Frontend → GraphQL → `SpecificationsClient.GetSpecifications()` → CAPI `/category-filters` → MongoDB
   - **Filter point**: `GetSpecifications()` (line 138) — return nil for Jobs specs
   - Cache (60-min + singleflight) stores full data; filtering per-request

3. **Search results**: Frontend → GraphQL `SearchListings` → search-http-rest → Elasticsearch
   - **Filter point**: `getClassifiedQueryFilters()` — add `MustNot` terms filter on `category: "Jobs"`
   - **Gap**: memberID needs threading from handler through to query builder

4. **Category SEO**: Frontend → GraphQL → `GetCategorySeo()` → CAPI `/category-seo`
   - **Filter point**: `GetCategorySeo()` — return nil for Jobs

5. **Category Tree**: Frontend → GraphQL → `GetPricesForCategory()` → CAPI `/category-tree`
   - Lower priority — used for pricing info on sell flow

6. **Sitemaps**: marketplace-frontend sitemap → GraphQL `AvailableFilters` → filtered by #1 above
   - **No code change needed** — automatically excluded

7. **Legacy sitemap**: m-ksl-classifieds → Elasticsearch directly
   - **Needs separate fix** (same as #9)

### Nest Assessment
- Category Manager is **admin-only** (protected by `generalNestAccess` email allowlist)
- No public-facing category display
- **No Nest changes needed** for this approach

### CAPI Assessment
- CAPI returns all categories to marketplace-graphql
- marketplace-graphql is the **only consumer** of CAPI category endpoints
- **No CAPI changes needed** — filtering happens in GraphQL layer

---

## Comparison: #8 (Feature Flagging) vs #9 (Visibility Flags)

### Scope Comparison

| Dimension | #8 Feature Flagging | #9 Visibility Flags |
|-----------|-------------------|-------------------|
| **Services modified** | 2 (marketplace-graphql, search-http-rest) | 8 (Nest, CAPI, listing-http-rest, search-http-rest, listing-http-ai-analyze, marketplace-graphql, legacy sitemap, + optional CAPI migration) |
| **MongoDB changes** | None | New `visibility` field on category/subCategory docs |
| **CAPI changes** | None | Yes — filter on `/category-tree`, `/category-seo`; add metadata to `/category-filters` |
| **Nest UI changes** | None | New Visibility column + edit form in React frontend |
| **Configuration** | Firebase Remote Config (change via console) | MongoDB field (change via Nest Category Manager UI) |
| **Reusability** | Targeted — needs new config per category | General-purpose — any category can be flagged |
| **Who manages** | Developer (Firebase Console / env vars) | Admin (Nest Category Manager UI) |

### Effort Estimate Comparison

| Task | #8 Effort | #9 Effort |
|------|-----------|-----------|
| **Nest UI** | None | Medium (PHP + React: visibility column, edit form, changed indicator) |
| **CAPI filtering** | None | Medium-Large (3 endpoints + Memcache strategy + search filtering) |
| **GraphQL filtering** | Small-Medium (add gate config + 3 filter points) | Medium (same 3 filter points + new `CategoryVisibility` type + struct changes) |
| **Search filtering** | Small (env var + MustNot filter + memberID threading) | Small (same MustNot filter + hidden category cache from MongoDB) |
| **listing-http-rest** | None | Small-Medium (visibility struct + `GetFilteredCategoryTree()`) |
| **AI suggestions** | None (accept gap) | Small (per-request taxonomy filter) |
| **Legacy sitemap** | Small (if still running) | Small (same work) |
| **Data migration** | None | None (additive, defaults to visible) |
| **Total relative effort** | **~2-3 units** | **~8-10 units** |

### Trade-offs

**#8 Advantages**:
- ~3-4x less code to write
- No touching production-critical CAPI PHP code
- No MongoDB schema changes
- Faster to implement and deploy
- Allowlist managed via Firebase Console (instant changes, no deployment)
- Lower risk — fewer services touched

**#8 Disadvantages**:
- Not self-service for non-developers (Firebase Console, not Nest UI)
- Targeted at specific categories, not general-purpose
- If other categories need hiding later, need to extend config (though this is minor)
- Doesn't filter CAPI responses directly (acceptable since marketplace-graphql is the only consumer)
- AI suggestions gap (Jobs could be suggested but dropdown won't show it)
- No visual indicator in Nest that a category is hidden

**#9 Advantages**:
- General-purpose — any category can be flagged by admins via Nest UI
- Self-documenting — visibility state is on the category document itself
- Complete coverage (CAPI, GraphQL, search, AI, listing-http-rest)
- Prepares listing-http-rest for CAPI replacement
- Lays groundwork for future CAPI migration (Feature 12)

**#9 Disadvantages**:
- Much larger scope — 8+ services, 12 features
- Touches production-critical CAPI code
- Requires Nest UI development (PHP + React)
- Longer implementation timeline
- More risk surface area

---

### Resolved Decisions
- **Hidden category list**: Hardcoded to `"Jobs"` — no need for Remote Config configurability
- **AI suggestions**: Not in production, no need to handle
- **Direct CAPI consumers**: No direct consumers besides marketplace-graphql — CAPI filtering not needed

## Still Needs Research
- Whether `GetPricesForCategory()` (CAPI `/category-tree`) needs filtering — used in sell flow for pricing, may not be user-visible
- Whether the legacy sitemap generator (`m-ksl-classifieds/util/sitemap/`) is still running in production (user still researching)
- Whether `listing-http-extractor-rest` uses category data in a way that would expose Jobs listings

## Unanswered Questions
- Is the legacy sitemap generator still running in production? (Determines whether Feature 7 is needed — user is researching)
- Do we need to handle the case where a user directly navigates to `/search/cat/Jobs`? Search results would be empty (filtered by Feature 5), but the URL would still "work" — is that acceptable?

## Research Sources Consulted
- [deseretdigital/marketplace-graphql](https://github.com/deseretdigital/marketplace-graphql) — Explored Remote Config feature gating (`IsFeatureEnabled()`, `GateConfig`, member ID allowlist), `FeatureConfig` pattern, JWT/member ID middleware, category data flow (`prepareClassifiedsCategoryOptions`, `SpecificationsClient`, `GetCategorySeo`), caching layers (go-cache, singleflight), search client, existing rollout patterns
- [deseretdigital/nest](https://github.com/deseretdigital/nest) — Confirmed Category Manager is admin-only (no public-facing surfaces), assessed `copyInProgressToProd()` for hooks (none), confirmed no feature flag infrastructure in Nest
- [deseretdigital/marketplace-backend](https://github.com/deseretdigital/marketplace-backend) — Explored search-http-rest query builder (`getClassifiedQueryFilters`, `MustNot` pattern, `FilterContainer`), member ID flow through handler→domain→backend, `parseAllowlistMemberIDs()` pattern in listing-ps-price-drop, CategoryClient in listing-http-rest, ES model (category as string field)
- **Project #9 research** — Used as baseline for understanding the full category visibility problem space and data flow
