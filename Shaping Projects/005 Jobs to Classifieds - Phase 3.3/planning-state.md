> ⚠️ **MERGED & ARCHIVED (2026-07-08)** — This package was folded into **003 Jobs to Classifieds - Phase 3.1 (Migrate Listings & Favorites)**. Favorites now migrate inline, per listing, inside the 3.1 migration worker. See `003 .../planning-state.md` (Favorites Migration decision + 2026-07-08 changelog) for the current source of truth.

# Planning State — Jobs to Classifieds - Phase 3.3

## Identified So Far

### Legacy System (Source)
- **Collection:** `jobsFavoriteJobs` in MongoDB
- **Fields:** `memberId` (string), `savedId` (string), `createTime` (UTCDateTime)
- **No notification preferences** — unlike Classifieds favorites, legacy Jobs favorites have no price-drop or expiry alert settings
- **API:** `FavoriteController.php` in `m-ksl-jobs` — POST `/favorite/favorite`, POST `/favorite/removefavorite`
- **GraphQL:** `myFavorites` query with pagination, keyword search, sort
- **"Favorite Employer"** exists but is buggy and OUT OF SCOPE per Notion doc

### New System (Target)
- **Collection:** `generalFavorites` in MongoDB (same collection used by Classifieds)
- **Fields:** `favoriteId` (string, `"{memberId}-{adId}"`), `adId` (int), `memberId` (int), `notifyOnPriceDrop` (object), `notifyOnExpire` (object), `createTime` (UTCDateTime)
- **CAPI** has full CRUD: POST/PUT/DELETE `/listings/{listingId}/favorites`
- **ES sync** via oplog connector — favorites appear in `favorites` ES index with `vertical: "classifieds"`

### GraphQL Layer
- `marketplace-graphql` has `FavoriteListing`, `UnfavoriteListing`, `UpdateFavoriteListing` mutations
- `ListingTypeJob` cases currently route to legacy KSL API (`addJobFavorite`, `removeJobFavorite`)
- `ListingTypeClassified` cases route to CAPI — this is the target path for Jobs post-migration
- Key file: `graph/mutationresolvers/legacy-favoritelisting.go` lines 99 (add), 187 (remove)

### Downstream Services (No Changes Needed)
- **listing-http-favorites-rest**: serves `GET /favorites/listing-counts` from `generalFavorites` (CLASSIFIED vertical) — works as-is
- **search-http-rest**: enriches search results with favorite counts from ES — works as-is
- **listing-ps-price-drop**: reads `generalFavorites` for price-drop notifications — works as-is (migrated favorites default to notifications off)
- **MyAccount**: displays favorites from ES `favorites` index — migrated favorites appear under "Classifieds" section
- **CAPI**: full CRUD on `generalFavorites` — validates listing exists in `ClassifiedListing` (migrated Jobs are there from Phase 3.1)

### Data Model Differences
- `savedId` (string) → `adId` (int): requires lookup in `jobListingMigrations` (Phase 3.1)
- `memberId` (string) → `memberId` (int): type conversion
- No notification prefs → default to `{ email: false, push: false }` for both `notifyOnPriceDrop` and `notifyOnExpire`
- Need to generate `favoriteId` as `"{memberId}-{adId}"` composite key

### Architecture Decision
- Jobs favorites go into `generalFavorites` (same as Classifieds) — follows Phase 3.2 pattern
- No new services needed beyond the migration script
- Only marketplace-graphql needs code changes (3 switch cases)

## Still Needs Research
- Exact volume of `jobsFavoriteJobs` documents to migrate (estimated tens of thousands)
- Whether any `savedId` values in `jobsFavoriteJobs` reference listings that won't be migrated in Phase 3.1 (moderate/abuse/inprogress status)
- Legacy messaging content and timing — needs PM/design input before build

## Unanswered Questions
- **Messaging content:** What exactly should the legacy platform messaging say? Needs PM approval.
- **MyAccount "Jobs" filter:** After migration, the Jobs section filter in MyAccount favorites will show empty (migrated favorites appear under Classifieds). Is this acceptable during the transition, or should we update the filter logic?
- **Favorite Employer migration:** Explicitly out of scope for MVP — but will it be addressed in a future phase?
- **ES sync status:** `listing-http-favorites-rest` CRUD routes are still returning 501 (not implemented) as of 2026-04-01. Only `GET /favorites/listing-counts` is live. Need to confirm whether the oplog connector must be configured for `generalFavorites` → ES sync, or if full CRUD will be deployed before Phase 3.3 runs.

## Research Sources Consulted

### Notion Documents
- [Jobs to Classifieds - Phase 3.3 Migrate favorites](https://www.notion.so/3262ac5cb235806fae8ce777c37287b3) — Project framing doc with problem statement, solution, business impact
- [BUILD: Jobs to Classifieds - Phase 3.3 Migrate favorites](https://www.notion.so/3332ac5cb23580a98190ca31035c9841) — Build plan (status: Needs Shaping, now shaped)

### Repositories
- [deseretdigital/marketplace-backend](https://github.com/deseretdigital/marketplace-backend) — Researched:
  - `listing-http-favorites-rest` service (routes, domain, handler, store, cache)
  - `search-http-rest` favorites integration (ES store, domain)
  - `listing-ps-price-drop` favorites store
  - `listing-http-rest` Jobs schema and types
- [marketplace-graphql](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/) — Researched:
  - `legacy-favoritelisting.go` mutation resolvers (add/remove/update)
  - Jobs `ListingTypeJob` routing in favorites

### Legacy Repos
- [m-ksl-jobs](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/) — Researched:
  - `FavoriteController.php` — Jobs favorites API (add, remove, get IDs, get count)
  - `MyFavoritesFieldObject.php` — GraphQL favorites query
  - `saveFavorite.js` — Frontend favorite toggle
- [m-ksl-classifieds-api](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/) — Researched:
  - `ListingFavoriteController.php` — CAPI favorites CRUD
  - `FavoriteHelper.php` — Favorites helper with validation
  - `GeneralFavoritesCollection.php` — Target collection schema (lines 169-205)
- [m-ksl-myaccount-v2](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/) — Researched:
  - `pages/api/v1/favorites/` — Multi-vertical favorites API
  - `services/Favorites/transform.ts` — ES document structure
  - `constants/favorites.ts` — Vertical constants and ES index names
  - `stores/favorite/FavoriteFilterStore.ts` — Filter store with Jobs section

### Prior Phases (Context)
- Phase 3.1 (Shaping Project 003) — Listings migration, `jobListingMigrations` collection, field mapping
- Phase 3.2 (Shaping Project 004) — Saved search migration, established pattern of routing Jobs through Classifieds path

---

## Session Log

### 2026-04-01
- Synced `marketplace-backend` to origin/main (pulled commits updating `listing-http-favorites-rest` go.mod/go.sum and routes.go formatting)
- Confirmed CRUD routes in `listing-http-favorites-rest` still return 501 — only `GET /favorites/listing-counts` is implemented
- Fetched Notion doc — status is "PKG: Shaping" with full shaping section filled in; content aligns with local docs
- Added unanswered question about ES sync status given CRUD routes are still not implemented
- No new scope changes or information found — planning docs are comprehensive and ready for build
