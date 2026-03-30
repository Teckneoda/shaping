# Jobs Phase 2 — Features

Required features to complete the project. Organized by area.

---

## 1. Category Manager Setup

### 1.1 Create Jobs Category & Subcategories
- Create a new Jobs category in Category Manager
- Create Jobs subcategories (matching legacy Jobs categories)
- Configure subcategory specifications for Jobs fields:
  - `specSubCatString`: Employment Type (Full Time, Part Time, Contract, Temporary, Internship, Seasonal)
  - `specSubCatString`: Education Level (None, High School, 2 Year Degree, 4 Year Degree, Advanced Degree)
  - `specSubCatString`: Years of Experience (None, 1-2 Years, 3-4 Years, 5-7 Years, 8-10 Years, >10 Years)
  - `specSubCatString` (multiple slots): Company Perks — each perk as a separate boolean-like select slot (Work remote, Flexible schedule, etc.)

### 1.2 Feature Flag for Jobs Category
- Add a feature flag in GraphQL that filters the Jobs category out of production responses
- Allow access only when the requesting user's member ID is in the team allowlist
- Flag must be removable for launch

---

## 2. Elasticsearch & Data Sync

### 2.1 ES Mapping Updates
- Add ES mappings for top-level Jobs fields:
  - `jobsPayRangeType` (keyword: "hourly" or "salary")
  - `jobsPayFrom` (integer, cents)
  - `jobsPayTo` (integer, cents)
  - `jobsApplicationUrl` (keyword — not filterable, but needed for detail page reads)
- Add "Job" as a valid `marketType` value in the ES index

### 2.2 Mongo Connector Updates
- Update Mongo connector to sync the new top-level Jobs fields to ES
- Verify specSubCat fields sync automatically via the existing pipeline

---

## 3. SRP (Search Results Page)

### 3.1 Backend — SRP Search Service
- Add support for filtering by `marketType=Job` in the SRP search service (already extracted from GraphQL)
- Add custom filter mapping for top-level pay range fields (`jobsPayRangeType`, `jobsPayFrom`, `jobsPayTo`) so they can be used as SRP range filters
- Ensure specSubCat-based filters (employment type, education, experience, perks) flow through the existing AvailableFilters pipeline

### 3.2 Backend — GraphQL
- Update SRP GraphQL query to include `marketType=Job` as a selectable filter option alongside For Sale, In Search Of, For Rent
- Ensure AvailableFilters returns Jobs-specific specSubCat filters when Jobs category/subcategory is selected
- Include pay range as an available filter with custom handling

### 3.3 Frontend — SRP (requires frontend resource)
- Add "Jobs" as a selectable listing type (marketType) filter on the SRP
- Display Jobs-specific specSubCat filters when Jobs is selected
- Display pay range filter with custom UI (hourly vs salary toggle + range inputs)
- Implement display rules:
  - Jobs mixed with other listing types → standard grid format
  - Jobs is the only selected category → Jobs list format
  - Jobs + Services selected → standard grid style
- Display logic is entirely frontend — no backend hints needed

---

## 4. Detail Page

### 4.1 Backend — Listing Service Expansion
- Expand the Listing Service GET endpoint to return Jobs-specific fields:
  - Top-level: `jobsPayRangeType`, `jobsPayFrom`, `jobsPayTo`, `jobsApplicationUrl`
  - specSubCat fields are already returned as part of the listing specs

### 4.2 Backend — GraphQL
- Update the GraphQL detail page query to pass through Jobs-specific top-level fields from the Listing Service

### 4.3 Frontend — Detail Page (requires frontend resource + design input)
- Detail Page is **read-only** (no editing — editing goes through PAL, which is out of scope)
- Render standard fields: Title, Description, Company Name (businessName), Photos, Location, Contact Info
- Render specSubCat fields through existing specs UI: Employment Type, Education Level, Years of Experience, Company Perks
- Render top-level Jobs fields (needs design input):
  - Pay Range display (formatted as hourly rate or annual salary based on `jobsPayRangeType`)
  - Apply button linking to `jobsApplicationUrl`

---

## 5. MyAccount

### 5.1 Backend — New Listing Service Endpoints
The following MyAccount actions need new endpoints on the Listing Service:
- **Mark as Sold** — update listing status
- **Mark as Sale Pending** — update listing status
- **Delete (Soft Delete)** — set status to 'deleted' + populate `deletedAt` timestamp
- **Renew** — extend listing expiration

Reactivate uses the existing request activation endpoint.

### 5.2 Backend — Soft Delete Implementation
- Add `deletedAt` timestamp field to the listing model
- Add 'deleted' as a valid status value
- On soft delete:
  - Set status to 'deleted' and populate `deletedAt`
  - Exclude from ES search results
  - Do not count toward user's active listing limits
  - Stop billing/subscriptions
- On reactivation:
  - User must go through checkout flow to re-pay for any canceled subscriptions
  - Listing must be within user's active listing limits
- Retention period and final purge behavior: **pending Legal input**

### 5.3 Backend — CX Restore Endpoint
- New endpoint for CX to restore soft-deleted listings (including photos)
- Endpoint contract: **pending CX consultation**

### 5.4 Frontend — MyAccount (requires frontend resource)
- Display Jobs listings in MyAccount listing view
- Support actions: view, mark as sold, mark as sale pending, delete (soft delete), renew, reactivate
- No inline field editing — editing redirects to PAL (out of scope)

---

## 6. App Work (2-week estimate — capacity not confirmed)

### 6.1 App — SRP / Jobs Tab
- When user taps the Jobs tab, auto-select the Jobs category and display subcategory list (same pattern as Services today)
- Remove Jobs from global search

### 6.2 App — Detail Page
- Modify the unified detail page to render Jobs-specific top-level fields:
  - Pay Range (formatted by type)
  - Apply button (applicationUrl)

### 6.3 App — PAL (scope TBD)
- **Needs clarification:** Confirm with App team whether PAL (posting/editing Jobs on app with hard-coded fields, similar to Cars) is included in the 2-week estimate or out of scope

---

## Out of Scope

- Saved Search & Alerts for Jobs (Phase 3)
- Quick Apply / Resume uploads / Virus scanning (Phase 4)
- Full migration of existing Jobs listings (Phase 5)
- Post-A-Listing (PAL) form — web or app editing/posting of Jobs listings
- Replacing the subcategory-driven specs model with semantic key/value filters
- `jobApplicationDeadline` field (marked for removal — TODO verify with team)

---

## Open Blockers

| Blocker | Owner | Status |
|---------|-------|--------|
| Frontend developer not assigned | PM | Not started |
| Legal input on soft-delete retention/purge | Legal | Not started |
| CX consultation on restore tool workflow | CX | Not started |
| App team capacity confirmation | App | Not confirmed |
| Figma SRP mockup update | Design | Not started |
| Detail Page design for top-level Jobs fields | Design | Not started |
| Analytics measurement plan | Analytics | Not started |
