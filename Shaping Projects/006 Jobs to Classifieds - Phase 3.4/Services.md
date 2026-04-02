# Jobs to Classifieds - Phase 3.4 — Services

## Overview

This phase requires creating a new redirect service following the established pattern in marketplace-backend, plus potential infrastructure changes to route legacy Jobs traffic to the new service.

---

## New Service: `redirect-legacy-jobs-http`

**Location**: `apps/redirect/services/redirect-legacy-jobs-http/`

A new Go HTTP service following the same architecture as the existing `redirect-legacy-services-http` service.

### Architecture

```
redirect-legacy-jobs-http/
├── main.go                    # Service entry, o11y setup, graceful shutdown
├── app.go                     # HTTP server, routes, readiness/liveness
├── routes.go                  # Route definitions
├── handler/
│   └── handler.go             # HTTP handlers (redirect + canonical URL)
├── domain/
│   ├── domain.go              # URL parsing & transformation logic
│   ├── mapping_categories.go  # Jobs category → Classifieds subcategory mapping
│   ├── mapping_cities.go      # City slug → city name mapping (if needed)
│   └── mapping_listings.go    # Listing ID mapping loader (from CSV or MongoDB)
│   └── listing-mappings/
│       ├── mapping_listings.csv   # Legacy Job ID → New Listing ID pairs
│       └── README.md              # How to regenerate mappings
├── ddm-container.yml
├── Dockerfile
├── go.mod / go.sum
├── .tf/
│   └── kubernetes-deploy.tf   # K8s deployment config
└── README.md
```

### Key Design Decisions

1. **Separate service** (not extending existing redirect services) — maintains separation of concerns and independent deployment, consistent with existing pattern
2. **Listing ID mapping via embedded CSV** — same approach as `redirect-legacy-services-http`, generated from `jobListingMigrations` MongoDB collection
3. **Category mapping via hardcoded Go maps** — maps legacy Jobs categories to Classifieds Jobs subcategories
4. **301 redirects** for permanent URLs (detail pages, search), **302** for catch-all
5. **`?jobs-redirect` query parameter** appended to all redirects for analytics tracking

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/{path...}` | Catch-all redirect handler — parses legacy Jobs URL, returns 301/302 redirect |
| GET | `/jobs-redirect/canonical` | Returns JSON canonical URL without redirecting |
| GET | `/livez` | Liveness probe |
| GET | `/readyz` | Readiness probe |

### Data Sources

| Data | Source | Format |
|------|--------|--------|
| Listing ID mapping | MongoDB `jobListingMigrations` collection → exported CSV | `legacy_id,new_id` |
| Category mapping | Legacy `m-ksl-jobs` category list → hardcoded Go map | `legacySlug → classifiedsSubcategory` |
| City mapping | Reuse from `redirect-legacy-services-http` or define new | `slug → cityName` |

### Infrastructure

- **Kubernetes**: 3–5 replicas, similar resource allocation to `redirect-legacy-services-http`
- **Deployment**: GKE us-west3 cluster, `core-web` team
- **CI/CD**: New GitHub Actions workflow triggered on changes to `apps/redirect/services/redirect-legacy-jobs-http/**`

---

## Infrastructure: DNS/Ingress Routing

**Requirement**: Route `jobs.ksl.com` traffic to the new `redirect-legacy-jobs-http` service.

- **Current state**: `jobs.ksl.com` points to the legacy PHP application
- **Target state**: `jobs.ksl.com` traffic routed to the new redirect service in Kubernetes
- **DNS managed by**: Platform team — will need Platform support to coordinate the traffic cutover
- **Timing**: Post-migration cutover only — service goes live after Phases 3.1–3.3 are complete

---

## Existing Services (Reference Only — No Changes)

### `redirect-legacy-services-http`
- **Location**: `apps/redirect/services/redirect-legacy-services-http/`
- **Relevance**: Template/reference for the new Jobs redirect service
- **No changes needed**

### `listing-redirect-http`
- **Location**: `apps/listing/services/listing-redirect-http/`
- **Relevance**: Handles legacy Classifieds search URL format redirects
- **No changes needed** — Jobs URLs are a different format and domain

---

## MongoDB Collections (Reference Only)

### `jobListingMigrations`
- **Created by**: Phase 3.1 migration script
- **Schema**: `{ legacyJobId, newListingId, ... }`
- **Used by**: This phase to generate the listing ID CSV mapping file
- **No changes needed**
