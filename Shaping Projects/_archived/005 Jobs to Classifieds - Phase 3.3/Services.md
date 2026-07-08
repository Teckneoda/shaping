# Jobs to Classifieds - Phase 3.3: Migrate Favorites — Services

## Services to Update

### 1. Legacy Jobs Platform — m-ksl-jobs (Update — Messaging Only)

**Repo**: Legacy Jobs platform
**Purpose:** Display migration messaging on legacy favorites views.

**Changes:**
- Add banner/notice components to legacy favorites pages
- MyAccount favorites page (Jobs filter)
- Jobs detail page favorite button area

**Key Files:**
- [FavoriteController.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/api/controllers/FavoriteController.php) — Legacy favorites controller
- [MyFavoritesFieldObject.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/APIGraphQL/FieldObject/MyFavoritesFieldObject.php) — GraphQL layer for favorites

---

## Services to Create

### 2. Migration Script (New)

**Repo**: `deseretdigital/marketplace-backend`
**Location**: `apps/listing/services/` (alongside Phase 3.1 migration worker)
**Purpose:** One-time migration of favorites data from `jobsFavoriteJobs` → `generalFavorites`.

**Implementation:**
- Standalone Go script — no PubSub fan-out needed (favorites are simple documents)
- Connect to MongoDB (source: `jobsFavoriteJobs`, lookup: `jobListingMigrations`, destination: `generalFavorites`)
- Batch read → transform → write with idempotency checks using `favoriteId` composite key
- All notification/alert fields set to `false` — Jobs never had price-drop or expiring-soon notifications
- Validation: compare source count vs successfully migrated count
- Runs after Phase 3.1 is live (requires `jobListingMigrations` mappings)

**Pattern to follow:** Simpler than Phase 3.1 migration (no API calls, no activation pipeline, no PubSub). Single-pass batch script sufficient.

**Elasticsearch sync (conditional):** If `listing-http-favorites-rest` is in production before this migration runs, favorites are read directly from MongoDB and no ES sync is needed. If it is NOT yet in production, the MongoDB oplog connector must sync `generalFavorites` writes to the `favorites` ES index so downstream consumers can read the migrated data.

---

## Services That Do NOT Need Changes

### CAPI — m-ksl-classifieds-api
Already has full CRUD on `generalFavorites` via `POST/PUT/DELETE /listings/{listingId}/favorites`. Validates listing exists in `ClassifiedListing` collection — migrated Jobs listings are there (from Phase 3.1). No changes needed.

**Reference:** [ListingFavoriteController.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ListingFavoriteController.php), [FavoriteHelper.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Helper/FavoriteHelper.php)

### listing-http-favorites-rest (marketplace-backend)
Serves `GET /favorites/listing-counts` from `generalFavorites` (CLASSIFIED vertical). Migrated Jobs favorites land in `generalFavorites` and are counted automatically. No changes needed.

**Reference:** [domain/favorites.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-favorites-rest/internal/domain/favorites.go)

### search-http-rest (marketplace-backend)
Favorites enrichment works via ES `favorites` index, which is synced from `generalFavorites` via oplog connector. Migrated favorites get `vertical: "classifieds"` in ES and are served by existing Classified mapping. No changes needed.

**Reference:** [domain/favorites.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/search-http-rest/internal/domain/favorites.go)

### listing-ps-price-drop (marketplace-backend)
Reads from `generalFavorites` for price-drop notifications. Migrated favorites default to `notifyOnPriceDrop: { email: false, push: false }` — they won't trigger notifications unless the user opts in post-migration. No changes needed.

**Reference:** [store/favorite.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-ps-price-drop/internal/store/favorite.go)

### MyAccount — m-ksl-myaccount-v2
Migrated favorites appear under "Classifieds" section in ES (since they're in `generalFavorites`). Users selecting "All" or "Classifieds" will see their migrated Jobs favorites. The "Jobs" section filter will show empty post-migration — acceptable behavior, cleanup in Phase 4.

**Reference:** [favorites/[vertical]/[id].ts](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-myaccount-v2/pages/api/v1/favorites/%5Bvertical%5D/%5Bid%5D.ts)

---

## Data Flow (Post-Migration)

```
Migration Script (one-time)
    │ Reads jobsFavoriteJobs
    │ Looks up jobListingMigrations for new IDs
    │ Writes to generalFavorites (all alerts = false)
    ▼
MongoDB: generalFavorites
    │
    ├──► listing-http-favorites-rest (if in production: serves favorites directly)
    │
    └──► Oplog connector (if service NOT in production: syncs to ES)
         ▼
         Elasticsearch: favorites index
         ├──► MyAccount (favorites list)
         └──► search-http-rest (SRP favorite counts)
```

## Implementation Sequence

1. **Parallel with Phase 3.1:**
   - Legacy platform messaging (Service 1)
2. **After Phase 3.1 is live:**
   - Run migration script (Service 2)
   - Verify: migrated favorites appear correctly for users
3. **Cleanup (future phase):**
   - Archive `jobsFavoriteJobs` MongoDB collection
   - Remove "Jobs" section from MyAccount favorites filter

## Legacy Services (Reference Only)

### m-ksl-jobs — Legacy Favorites
- **Collection**: `jobsFavoriteJobs` — fields: `memberId` (string), `savedId` (string), `createTime` (UTCDateTime)
- **API**: `FavoriteController.php` — POST `/favorite/favorite`, POST `/favorite/removefavorite`
- **No notification preferences** (unlike Classifieds favorites — no price-drop, no expiring-soon alerts)

### m-ksl-classifieds-api — Classifieds Favorites (Target)
- **Collection**: `generalFavorites` — fields: `favoriteId` (string), `adId` (int), `memberId` (int), `notifyOnPriceDrop` (object), `notifyOnExpire` (object), `createTime` (UTCDateTime)
- **API**: POST/PUT/DELETE `/listings/{listingId}/favorites`
- **Full notification preference support**: price-drop and expiry alerts (email + push)
