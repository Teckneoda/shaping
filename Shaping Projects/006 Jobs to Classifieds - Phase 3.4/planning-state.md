# Planning State — Jobs to Classifieds - Phase 3.4

## Identified So Far

### Project Scope
- Redirect all legacy `jobs.ksl.com` URLs to `classifieds.ksl.com` equivalents after Phases 3.1–3.3 complete the data migration
- **Estimate**: 1 week web work (per Notion framing doc)
- **Build Plan status**: "Needs Shaping" in Notion

### Existing Redirect Infrastructure
- **`redirect-legacy-services-http`** (`apps/redirect/services/redirect-legacy-services-http/`) — proven pattern for legacy→Classifieds redirects:
  - Uses embedded CSV for listing ID mapping (generated from MongoDB)
  - Hardcoded Go maps for category mapping (538 lines, 100+ categories)
  - City slug mapping for Utah cities
  - HTTP 302 redirects with `?services-redirect` tracking parameter
  - Canonical URL JSON API endpoint
  - K8s deployment: 3–5 replicas, GKE us-west3
- **`listing-redirect-http`** (`apps/listing/services/listing-redirect-http/`) — handles legacy Classifieds search URL format:
  - HTTP 301 redirects to `classifieds.ksl.com`
  - Parses category/subcategory/spec filters from URL path segments
  - 29 supported categories with full subcategory trees (2420-line config)

### Legacy Jobs URL Patterns (from `m-ksl-jobs` codebase)
Routes defined in `Bootstrap.php` (lines 183–386):
- **Detail**: `/listing/:id` → ListingController
- **Search**: `/search/:action/*` with filters: `category`, `state`, `city`, `zip`, `miles`, `keywords`, `jobtype`, `experience`, `education`, `companyperks`, `posted`, `salaryfrom/to`, `hourlyfrom/to`, `topjobs`, `sort`
- **Employer**: `/employer/:id`, `/company/:id` → EmployerController
- **Apply**: `/apply/:jid`, `/apply/save`, `/apply/savejson` → ApplyController
- **Edit/Manage**: `/edit/confirmation/id/:id`, `/edit/reactivate/:mid/:id`, `/edit/delete/:mid/:id`, `/edit/renew/:mid/:id` → EditController
- **Favorites**: `/myjobs`, `/favorite/:what/:jid`, `/removefavorite/:what/:mid/:sid` → FavoriteController
- **Landing pages**: `/`, `/topjobs`, `/idahojobs`, `/techjobs`, `/freelistings`, `/3free`, `/whatsnew`
- **Widgets**: `/widget/:dim` (deprecated)
- **Feeds**: `/feed/ziprecruiter`, `/feed/recruitology` (separate concern)
- **Report**: `/report/:id`

### ID Mapping
- `jobListingMigrations` MongoDB collection created in Phase 3.1 maps legacy Job IDs → new Classifieds listing IDs
- Same CSV export approach as Services redirect can be used

### Prior Phases Context
- **Phase 3.1**: Migrated 1,300+ active job listings to Classifieds; created `jobListingMigrations` mapping collection; $1.2M annual revenue, 400K monthly page views
- **Phase 3.2**: Migrated ~12,000 saved searches to Classifieds with `marketType: "Job"`
- **Phase 3.3**: Migrated favorites from `jobsFavoriteJobs` to `generalFavorites` using Phase 3.1 ID mappings

### Recommended Approach
- Create new `redirect-legacy-jobs-http` service following `redirect-legacy-services-http` pattern
- Separate service maintains deployment independence and separation of concerns
- Listing ID mapping via embedded CSV (from `jobListingMigrations`)
- Category mapping via hardcoded Go maps
- 301 redirects for SEO, with `?jobs-redirect` tracking parameter

---

## Still Needs Research

- **Jobs category→Classifieds subcategory mapping**: Need complete list of legacy Jobs categories (40 categories, see Phase 3.1 Legacy Category Mapping) and their exact Classifieds subcategory string equivalents under the Jobs parent category
- **URL mapping for categories**: The legacy URLMapper.php has custom URL slug logic — need to verify all category slug→name mappings match what the redirect service will expect
- **Widget endpoints**: Embeddable iframe widgets (`/widget/:dim`) display featured jobs on partner/external sites. Need usage data to determine if any partners are actively embedding these — **manual investigation pending**

---

## Resolved Questions

1. **Who manages DNS for `jobs.ksl.com`?** → Platform team. Will need Platform support to coordinate the traffic cutover.
2. **Is there an employer→member mapping?** → Yes, employer IDs correlate directly to member IDs. Employer pages redirect to MFTS (SRP filtered by member ID).
3. **Search filter mapping?** → `jobtype`, `experience`, `education` map to subcategory specification fields. `salaryfrom/to` and `hourlyfrom/to` map to top-level price fields (dollars→cents × 100). `companyPerks` dropped — not implementing. See Phase 3.1 field mapping for details.
4. **Are there external backlinks or SEO-critical pages beyond standard patterns?** → No, the identified patterns (detail, search, landing, employer) cover all important traffic.
5. **Should the redirect service go live before or after Phases 3.1–3.3?** → After. Post-migration cutover only.
6. **Feed endpoints?** → Handled in a separate package already in progress. Out of scope.
7. **Widget endpoints?** → Unresolved. These are embeddable iframe widgets (4 IAB ad sizes) that display featured jobs on partner/external sites. Need to check usage data before deciding. Manual investigation pending.

---

## Research Sources Consulted

- **[Notion: Jobs to Classifieds - Phase 3.4](https://www.notion.so/32e2ac5cb23580a7a772c995afc595d1)** — Framing doc with problem statement, 1-week estimate, OPS approved status
- **[Notion: BUILD Plan](https://www.notion.so/3332ac5cb235807a8e33e3744dd160cc)** — Build plan (status: Needs Shaping, template not yet filled in)
- **[deseretdigital/marketplace-backend](https://github.com/deseretdigital/marketplace-backend)** — Primary repo containing:
  - `apps/redirect/services/redirect-legacy-services-http/` — Reference redirect service (Services→Classifieds)
  - `apps/listing/services/listing-redirect-http/` — Classifieds search URL redirect service
  - `specs/007-listing-api-jobs-schema/` — Jobs listing schema spec (marketType: "Job", Jobs-specific fields)
- **Legacy codebase: `m-ksl-jobs`** (`/Users/cpies/code/shaping/Research Repos/Legacy/m-ksl-jobs/`) — Route definitions in `Bootstrap.php`, URL mapping in `URLMapper.php`, controller implementations
- **Shaping Projects 003–005** — Prior phases (3.1 Listings, 3.2 Saved Searches, 3.3 Favorites) for dependency context
