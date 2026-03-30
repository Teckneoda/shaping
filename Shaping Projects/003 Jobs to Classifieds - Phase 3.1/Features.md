# Jobs to Classifieds - Phase 3.1: Migrate Listings — Features

> **Status**: FRAMED: OPS Approved | **Estimate**: 2 weeks web work
> **Business Impact**: $1.2M annual revenue ($80K/mo self-serve + $20K/mo direct sales), 400K monthly page views, 1,300 active monthly listings, 15K+ uploaded resumes

## Problem Statement

Legacy Jobs listings still live on the old platform, preventing full retirement. Without a safe, repeatable migration of **both active and inactive** job inventory into Classifieds Jobs category, we risk downtime, broken links, and inconsistent experiences. This also blocks saved searches, alerts, and favorites (those features depend on listings existing in the new system).

## Core Features

### 1. Migration Script

**Approach**: Direct MongoDB write from legacy `jobs` collection → new `ClassifiedListing` collection. No API calls, no PubSub events fired (avoids triggering premature alerts).

**What gets migrated**:
- [ ] **Active** listings → `Active` status
- [ ] **Expired** listings → `Expired` status
- [ ] **Inactive/deleted/hidden** listings → soft-delete state (recoverable by CX support)
- [ ] **Skip** `moderate`, `abuse`, and `inprogress` listings entirely

**ID strategy**: Generate new IDs (legacy IDs may collide with existing classifieds IDs).

**Migration tracking**:
- [ ] Create `jobListingMigrations` collection — logs every import, maps legacy job ID → new listing ID (follows same pattern as `serviceListingMigrations` from the services project)
- [ ] Add **history object** on each migrated `ClassifiedListing` indicating it was an import (not organically created)

**Field transforms**:
- [ ] Field mapping from legacy 88-field schema to new system (see planning-state.md for full gap table)
- [ ] Category mapping from legacy numeric IDs (1-43) → new category/subCategory strings
- [ ] Pay range conversion: legacy stores salary as integers (dollars) → new system stores in cents (`* 100`)

**Execution**:
- [ ] Re-runnable with **overwrite flag** — when set, re-imports and overwrites previously migrated data for a listing (keyed on legacy ID in `jobListingMigrations`); without the flag, skips already-migrated records
- [ ] Validation and error handling for malformed legacy data

### 2. Feature Flag — Hide Jobs Category & Jobs marketType (marketplace-graphql)
> **Moved out of scope** — Category feature flagging is being built as a separate, prerequisite project. This project assumes the feature flag system is already in place.

### 3. Legacy Platform Messaging

Messaging content and timing will be determined before the build. The following pages need messaging added:

- [ ] **Detail page** — individual job listing view
- [ ] **Home page** — Jobs landing page
- [ ] **Jobs SRP** — search results page
- [ ] **Jobs Post-a-listing page** — listing creation flow
- [ ] **MyAccount** — when users have selected/filtered to Jobs

### 4. Schema Gaps — Field Mapping Decisions

| Legacy Field | Decision | Details |
|---|---|---|
| `employerStatus` (ft/pt/ct/tm) | **Spec fields** | Map to existing sub-category specifications |
| `educationLevel` (0-4) | **Spec fields** | Map to existing sub-category specifications |
| `yearsOfExperience` (int) | **Spec fields** | Map to existing sub-category specifications |
| `companyName` | **Map** | Map to `BusinessName` |
| `photo` | **Map** | Non-dealer accounts only: map to `photos[0]`. Dealer accounts use existing logo from Nest dealer record |
| `responsibilities` | **Append** | Append to `Description` |
| `qualifications` | **Append** | Append to `Description` |
| `requirements` | **Append** | Append to `Description` |
| `contactNotes` | **Append** | Append to `Description` |
| `displayPhone` | **Map** | If `true`, include `"phone"` in `contactMethod` array |
| `displayEmail` | **Map** | If `true`, include `"email"` in `contactMethod` array |
| `contactPhone` | **Map** | Map to `phoneNumber` |
| `contactEmail` | **Map** | Map to `email` |
| `standardFeatured` | **Map** | Map to `standardFeaturedAd` (bool) |
| `featuredDates` | **Map** | Convert from unix timestamps to `standardFeaturedDates` ([]FeaturedDate) |
| `inlineSpotlight` | **Drop** | No classifieds equivalent (Cars-only) |
| `topJobStart` | **Drop** | Not implementing boost migration |
| `companyPerks` | **Drop** | Not implementing |
| `contract` | **Drop** | No longer used |
| `relocation` | **Drop** | No longer used |
| `investment` | **Drop** | No longer used |

## Timing Dependencies

> **Critical**: Migrating listings should align with when favorites/saved searches are actually visible in Classifieds, to avoid alerting users about listings they cannot see.

## Prerequisites
- **Category feature flagging** must be in place before migration (separate project)
- **App compatibility** with Job listings must be verified before migration begins

## Out of Scope (Future Phases)
- Saved searches & alerts migration (Phase 3.2+)
- Favorites migration (Phase 3.2+)
- Frontend re-pointing from legacy to new APIs (Phase 4+)
- Google Jobs feed compatibility
- Legacy platform decommission
