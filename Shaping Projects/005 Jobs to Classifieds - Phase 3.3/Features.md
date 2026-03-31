# Jobs to Classifieds - Phase 3.3: Migrate Favorites — Features

> **Status**: FRAMED: OPS Approved | **Estimate**: 1 week web work
> **Business Impact**: $1.2M annual revenue ($80K/mo self-serve + $20K/mo direct sales), 400K monthly page views, 1,200 active monthly listings, 15K+ uploaded resumes
> **Depends on**: Phase 3.1 (listings must be migrated first for ID mappings)

## Problem Statement

As Jobs migrates to Classifieds, legacy Favorites stored in `jobsFavoriteJobs` are at risk of being lost due to platform and data-model differences. Losing Favorites breaks a core saved-items workflow for engaged users and will reduce return behavior and engagement.

## Core Features

### F1: Data Migration Script

**Goal:** One-time migration of legacy Jobs favorites from `jobsFavoriteJobs` into `generalFavorites`. Users need to see their favorited listings in the new system.

**Field Mapping:**

| Legacy (`jobsFavoriteJobs`) | Target (`generalFavorites`) | Transform |
|---|---|---|
| `memberId` (string) | `memberId` (int) | parseInt() |
| `savedId` (string) | `adId` (int) | Lookup in `jobListingMigrations`: legacy ID → new listing ID |
| (generated) | `favoriteId` (string) | `"{memberId}-{adId}"` composite key |
| (absent) | `notifyOnPriceDrop` | `{ email: false, push: false }` |
| (absent) | `notifyOnExpire` | `{ email: false, push: false }` |
| `createTime` (UTCDateTime) | `createTime` (UTCDateTime) | Preserve original |

**Alert/notification fields must all be set to `false`:** Legacy Jobs favorites have no price-drop or expiring-soon notification features. The only goal is for users to see their favorited listings — no alerts should be triggered for migrated favorites.

**Implementation:**
- [ ] Standalone Go script (no PubSub fan-out needed — favorites are simple documents)
- [ ] Read all documents from `jobsFavoriteJobs`
- [ ] For each document: lookup `savedId` in `jobListingMigrations` → get new Classifieds `adId`
- [ ] Skip if no mapping exists (listing was not migrated — e.g., moderate/abuse/inprogress)
- [ ] Skip if `memberId` is not numeric or <= 0
- [ ] Generate `favoriteId` as `"{memberId}-{adId}"` composite key
- [ ] Check idempotency: skip if `favoriteId` already exists in `generalFavorites`
- [ ] Insert into `generalFavorites` with all notification/alert prefs set to `false`
- [ ] **Elasticsearch sync (conditional):** If `listing-http-favorites-rest` is in production before this migration runs, no ES sync is needed — favorites are read directly from MongoDB. If the service is NOT yet in production, ensure the MongoDB oplog connector syncs `generalFavorites` writes to the `favorites` ES index so downstream consumers (MyAccount, search) can read the migrated data.
- [ ] Log results: total processed, successful, skipped (no mapping), skipped (duplicate), errors
- [ ] Re-runnable for retrying skipped records after more listings are migrated

**Execution:**
- Runs **after Phase 3.1** (listings must be migrated first so `jobListingMigrations` mappings exist)
- Validation: compare source count vs successfully migrated count, spot-check data accuracy

**Reference for target schema:** [GeneralFavoritesCollection.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Db/Mongo/GeneralFavoritesCollection.php) lines 169-205

---

### F2: Legacy Platform Messaging

**Goal:** Inform users on legacy Jobs favorites pages about upcoming changes.

**Pages needing messaging:**
- [ ] MyAccount favorites page (when filtered to Jobs)
- [ ] Legacy Jobs detail page favorite button area

**Timing:** Before migration begins, aligned with when Jobs listings become visible in Classifieds.

---

## Out of Scope

- **Favorite Employer** — buggy on legacy Jobs, explicitly excluded from MVP per Notion doc. Users can still do a Saved Search from the Employer profile page.
- **Implementing full CRUD on `listing-http-favorites-rest`** — a separate effort. Currently only `GET /favorites/listing-counts` is implemented; all CRUD routes return 501. The `favorites-handlers` branch has a scaffolded reset in progress.
- **Price-drop and expiring-soon notifications** — Jobs never had these features. All notification prefs are migrated as `false`. Users can opt-in via the Classifieds UI later if desired.
- **MyAccount UI changes** — migrated favorites appear under "Classifieds" section automatically; "Jobs" filter cleanup is Phase 4.
- **Legacy platform decommission** — future phase.

## Timing Dependencies

> **Critical**: Migrating favorites should align with when Jobs listings are actually visible/searchable in Classifieds, to avoid alerting users about listings they cannot see.

## Prerequisites
- **Phase 3.1** must be complete — `jobListingMigrations` collection must exist with legacy→new ID mappings
- **`listing-http-favorites-rest` (conditional):** If this service is in production before Phase 3.3, favorites are served directly from MongoDB and no ES sync is needed. If not, the oplog connector must be configured to sync `generalFavorites` writes to the `favorites` ES index.
