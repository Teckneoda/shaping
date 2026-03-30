# Jobs Phase 2 — Services

Services that will be created or updated for Phase 2 (SRP, Detail Page, MyAccount).

---

## Architecture Overview

```
Frontend (Next.js) / App (React Native)
    ↓ GraphQL queries/mutations
marketplace-graphql (GraphQL Gateway)
    ↓ REST API calls
marketplace-backend/apps/listing/services/listing-http-rest (Go REST API)
    ↓ Data operations
MongoDB → Mongo Connector → Elasticsearch
                              Redis (cache)
```

---

## 1. listing-http-rest (Go REST API)

**Location**: `marketplace-backend/apps/listing/services/listing-http-rest`

### Updates Required

#### 1.1 Listing Model / Data Layer
- Add `deletedAt` (timestamp) field to the listing model
- Add 'deleted' as a valid listing status
- Add "Job" as a valid `marketType` value
- Verify `jobsPayRangeType`, `jobsPayFrom`, `jobsPayTo`, `jobsApplicationUrl` fields exist on the model (added in Phase 1 — may need expansion for reads)

#### 1.2 Listing GET Endpoint (Detail Page)
- **Endpoint**: `GET /listings/{id}`
- **Change**: Expand response to include Jobs-specific top-level fields:
  - `jobsPayRangeType`
  - `jobsPayFrom`
  - `jobsPayTo`
  - `jobsApplicationUrl`
- specSubCat fields (employment type, education, experience, perks) should already be part of the listing response as specs

#### 1.3 Search Service (SRP)
- **Endpoint**: Search endpoint in the dedicated SRP search service (already extracted from GraphQL)
- **Changes**:
  - Support `marketType=Job` filtering
  - Add custom filter mapping for pay range fields so `jobsPayFrom`/`jobsPayTo` can be used as range filters in SRP queries
  - Ensure specSubCat-based filters are included in AvailableFilters when Jobs category/subcategory is selected

#### 1.4 New MyAccount Action Endpoints
These endpoints need to be created or verified on the Listing Service:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/listings/{id}/mark-sold` | `PUT` | Mark listing as sold |
| `/listings/{id}/mark-sale-pending` | `PUT` | Mark listing as sale pending |
| `/listings/{id}/delete` | `DELETE` | Soft delete — sets status='deleted' + populates `deletedAt` |
| `/listings/{id}/renew` | `PUT` | Renew/extend listing expiration |
| `/listings/{id}/request-activation` | `PUT` | **Already exists** — reactivate a listing |
| `/listings/{id}/restore` | `PUT` | CX-only restore of soft-deleted listing (contract TBD pending CX input) |

#### 1.5 Soft Delete Behavior
When a listing is soft-deleted via the delete endpoint:
1. Set `status` to 'deleted'
2. Populate `deletedAt` with current timestamp
3. Remove from ES search index (or filter out via status)
4. Do not count toward user's active listing limits
5. Stop billing/subscriptions for the listing
6. Retain photos and all listing data for potential restore

When restored (by CX or user reactivation):
- CX restore: direct status change back, photos intact
- User reactivation: must go through checkout flow to re-pay for subscriptions, must be within listing limits

Retention period before final hard purge: **pending Legal input**

---

## 2. marketplace-graphql (GraphQL Gateway)

**Location**: `marketplace-graphql`

### Updates Required

#### 2.1 Feature Flag — Jobs Category
- Add feature flag that filters Jobs category from production responses
- Allowlist based on member ID — only team members see Jobs category
- Flag must be removable for launch

#### 2.2 SRP Query Updates
- Add "Job" to the `marketType` filter options returned to frontend
- Pass through Jobs specSubCat filters via existing AvailableFilters pipeline
- Add custom handling for pay range filter (top-level fields, not specSubCat)
- Proxy all filter/search requests to the dedicated SRP search service

#### 2.3 Detail Page Query Updates
- Update listing detail query to pass through Jobs-specific top-level fields from the Listing Service:
  - `jobsPayRangeType`, `jobsPayFrom`, `jobsPayTo`, `jobsApplicationUrl`

#### 2.4 MyAccount Mutation Updates
- Add/verify GraphQL mutations that proxy to the new Listing Service endpoints:
  - `markListingAsSold`
  - `markListingAsSalePending`
  - `deleteListing` (soft delete)
  - `renewListing`
  - `restoreListing` (CX-only — contract TBD)

---

## 3. Elasticsearch

### Updates Required

#### 3.1 Index Mapping Changes
Add mappings for top-level Jobs fields:

| Field | ES Type | Notes |
|-------|---------|-------|
| `jobsPayRangeType` | `keyword` | "hourly" or "salary" |
| `jobsPayFrom` | `integer` | Stored in cents |
| `jobsPayTo` | `integer` | Stored in cents |
| `jobsApplicationUrl` | `keyword` | Not used for filtering — included for detail reads |

Add "Job" as a valid value for the existing `marketType` field.

#### 3.2 Soft Delete Exclusion
Ensure soft-deleted listings (status='deleted') are excluded from all search results. Either:
- Remove from ES index on soft delete, re-index on restore
- Or filter by status in all queries (existing pattern TBD)

---

## 4. MongoDB / Mongo Connector

### Updates Required

#### 4.1 Listing Document Changes
- Add `deletedAt` field (nullable timestamp) to listing documents
- Verify 'deleted' is a valid status value in the schema

#### 4.2 Mongo Connector Sync
- Update connector to sync new top-level fields to ES: `jobsPayRangeType`, `jobsPayFrom`, `jobsPayTo`, `jobsApplicationUrl`
- Verify specSubCat fields already sync via existing pipeline

---

## 5. Category Manager (Admin)

### Updates Required

- Create Jobs category
- Create Jobs subcategories (matching legacy Jobs categories)
- Configure specifications on each subcategory:
  - Employment Type (string select)
  - Education Level (string select)
  - Years of Experience (string select)
  - Company Perks (multiple string select slots, one per perk)
- Publish to production (behind feature flag in GraphQL)

---

## 6. Frontend — Web (Next.js)

**Requires frontend developer (not yet assigned)**

### Updates Required

#### 6.1 SRP
- Add "Jobs" as a `marketType` filter option
- Render Jobs specSubCat filters when Jobs is selected
- Custom pay range filter UI (hourly/salary toggle + range)
- Grid vs list display rules (frontend-only logic)

#### 6.2 Detail Page
- Render Jobs top-level fields: pay range, Apply button
- specSubCat fields render through existing specs UI

#### 6.3 MyAccount
- Display Jobs listings
- Support actions: view, mark as sold, mark as sale pending, delete, renew, reactivate
- No inline editing — editing via PAL (out of scope)

---

## 7. App (React Native) — 2-week estimate

**Capacity not confirmed with App team**

### Updates Required

- Jobs tab: auto-select Jobs category, show subcategory list (same as Services)
- Remove Jobs from global search
- Detail Page: render pay range + Apply button for Jobs listings
- PAL: **scope TBD** — confirm whether hard-coded Jobs fields in app PAL are included

---

## Services NOT Changed in Phase 2

- `listing-applications` — Quick Apply is Phase 4
- `listing-feed-parser` / `listing-feed-subscriber` — Feed ingestion unchanged
- `listing-cron-boosts` / `listing-cron-stats` — No changes needed
- Saved Search services — Phase 3
