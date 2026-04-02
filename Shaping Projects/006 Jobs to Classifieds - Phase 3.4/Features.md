# Jobs to Classifieds - Phase 3.4 — Features

## Overview

Redirect all legacy `jobs.ksl.com` URLs to their equivalent pages on `classifieds.ksl.com` after the Jobs→Classifieds migration is complete (Phases 3.1–3.3). This preserves SEO value and ensures users landing on old URLs reach the correct content.

---

## F1: Job Listing Detail Redirects

**Priority: High**

Redirect legacy job detail pages to their new Classifieds listing pages using the `jobListingMigrations` mapping collection created in Phase 3.1.

- **Legacy URL**: `jobs.ksl.com/listing/:legacyId`
- **New URL**: `classifieds.ksl.com/listing/:newListingId`
- **Redirect type**: 301 (Moved Permanently) for SEO
- **Mapping source**: MongoDB `jobListingMigrations` collection (`legacyId → newListingId`)
- **Fallback**: If legacy ID not found in mapping, redirect to Jobs category search page on Classifieds
- **Tracking**: Append `?jobs-redirect` query parameter to identify redirected traffic

## F2: Jobs Main/Landing Page Redirects

**Priority: High**

Redirect legacy Jobs landing pages to appropriate Classifieds equivalents.

| Legacy URL | Redirect Target |
|-----------|----------------|
| `jobs.ksl.com/` (homepage) | `classifieds.ksl.com/search/cat/Jobs` |
| `jobs.ksl.com/topjobs` | `classifieds.ksl.com/search/cat/Jobs` (or featured filter if available) |
| `jobs.ksl.com/idahojobs` | `classifieds.ksl.com/search/cat/Jobs/state/ID` |
| `jobs.ksl.com/techjobs` | `classifieds.ksl.com/search/cat/Jobs/sub/Technology` |
| `jobs.ksl.com/freelistings` | `classifieds.ksl.com/search/cat/Jobs` |
| `jobs.ksl.com/3free` | `classifieds.ksl.com/search/cat/Jobs` |
| `jobs.ksl.com/whatsnew` | `classifieds.ksl.com/search/cat/Jobs` |

- **Redirect type**: 301 (Moved Permanently)

## F3: Jobs Search/Category Page Redirects

**Priority: High**

Redirect legacy Jobs search URLs (with category, location, and filter parameters) to equivalent Classifieds search URLs.

- **Legacy URL pattern**: `jobs.ksl.com/search/category/:cat/state/:state/city/:city/jobtype/:type/...`
- **New URL pattern**: `classifieds.ksl.com/search/cat/Jobs/sub/:mappedSubCategory/state/:state/city/:city/...`
- **Filter mapping required**:
  - `category` → Classifieds subcategory under Jobs (40 legacy categories, see Phase 3.1 Legacy Category Mapping)
  - `state`, `city`, `zip`, `miles` → pass through as-is
  - `keywords` → `keyword` parameter
  - `jobtype` (ft/pt/ct/tm) → subcategory specification field (per Phase 3.1 `employerStatus` mapping)
  - `experience` → subcategory specification field (per Phase 3.1 `yearsOfExperience` mapping)
  - `education` → subcategory specification field (per Phase 3.1 `educationLevel` mapping)
  - `salaryfrom`/`salaryto` → top-level price fields (legacy stores dollars, Classifieds stores cents × 100)
  - `hourlyfrom`/`hourlyto` → top-level price fields (same dollar→cents conversion)
  - `posted` → `postedTime` parameter
  - `sort` → pass through
  - `companyperks` → **dropped** (not implementing)
- **Redirect type**: 301 (Moved Permanently)

## F4: Employer/Company Page Redirects

**Priority: Medium**

Redirect legacy employer profile pages to the "More From This Seller" (MFTS) page — the SRP filtered by member ID. Employer IDs correlate directly to member IDs.

- **Legacy URL**: `jobs.ksl.com/employer/:employerId`, `jobs.ksl.com/company/:employerId`
- **New URL**: `classifieds.ksl.com/search/cat/Jobs/member/:memberId` (MFTS page)
- **Redirect type**: 301 (Moved Permanently)

## F5: User Action Page Redirects

**Priority: Medium**

Redirect legacy user-facing action pages to appropriate Classifieds equivalents.

| Legacy URL | Redirect Target |
|-----------|----------------|
| `jobs.ksl.com/myjobs` (saved jobs) | `classifieds.ksl.com/my/favorites` |
| `jobs.ksl.com/apply/:id` | `classifieds.ksl.com/listing/:newId` (detail page with apply info) |
| `jobs.ksl.com/edit/*` | `classifieds.ksl.com/my/listings` |
| `jobs.ksl.com/report/:id` | `classifieds.ksl.com/listing/:newId` |

- **Redirect type**: 301 or 302 depending on action permanence

## F6: Catch-All Redirect

**Priority: High**

Any legacy `jobs.ksl.com` URL not matched by the above rules should redirect to the Jobs category on Classifieds.

- **Default target**: `classifieds.ksl.com/search/cat/Jobs`
- **Redirect type**: 302 (Found) — temporary, since we may add specific mappings later

## F7: Canonical URL API Endpoint

**Priority: Low**

Provide a JSON API endpoint (similar to the Services redirect's `/services-redirect/canonical`) that returns the canonical URL for a given legacy Jobs URL without performing the redirect.

- **Endpoint**: `/jobs-redirect/canonical?originalUrl=...`
- **Response**: `{ "canonicalUrl": "...", "originalUrl": "..." }`
- **Use case**: Frontend or other services can look up the new URL programmatically

## Unresolved — Needs Manual Investigation

- **Widget endpoints** (`/widget/:dim`) — Embeddable iframe widgets (4 IAB ad sizes: 300x600, 300x250, 160x600, 720x90) that display featured job listings on partner/external websites. Need to determine if any partners are actively embedding these before deciding whether to redirect, serve a deprecation notice, or drop. Checking usage data.

## Out of Scope

- Feed/API endpoints (`/feed/ziprecruiter`, `/feed/recruitology`) — handled in a separate package already in progress
- GraphQL proxy routes — internal only
- Legacy admin/moderation URLs
- `companyPerks` filter — not implementing
