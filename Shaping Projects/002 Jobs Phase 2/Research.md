# Jobs Phase 2 — Research & Open Questions

Tracking document for all items that need research, answers, or decisions before Phase 2 build can begin.

**Status Legend:** ⬜ Open | 🟡 In Progress | ✅ Resolved

---

## 1. Specifications / Filters

The team has confirmed that replacing the subcategory-driven specs model with semantic key/value filters is **out of scope** for Phase 2. The following questions remain about how Jobs specs work within the existing system.

| # | Question | Status | Owner | Answer |
|---|----------|--------|-------|--------|
| 1.1 | What specifications/filters need to exist for Jobs on the SRP? (salary range, hourly rate, job type — are these implemented as standard subcategory specs using the existing system?) | ✅ | Chris | Jobs fields (employmentType, educationLevel, yearsOfExperience, payRangeType, payFrom/payTo, companyPerks) are top-level listing fields but will be **mapped into the existing subcategory specs system** via Category Manager so they flow through the existing AvailableFilters pipeline. |
| 1.2 | How do Jobs specs get surfaced on the SRP within the current Category Manager / specs system? Does a Jobs subcategory already exist, or does one need to be created? | ✅ | Chris | Jobs category and subcategories **need to be created** in Category Manager as part of Phase 2. A **feature flag** is required in GraphQL to filter Jobs category out of production unless the user's member ID is in the team allowlist. |
| 1.3 | What is the impact on `AvailableFilters` in the SRP GraphQL call? Do we just add Jobs-specific specs through the existing mechanism? | ✅ | Chris | Some fields move to specSubCat slots (flow through AvailableFilters automatically). Pay range fields stay top-level and need custom filter mapping. See field mapping table below. |
| 1.4 | Is the Figma SRP mockup still accurate given the specs descope, or does it need to be updated to reflect the existing specs approach? | ✅ | Design | **Needs update.** Figma was designed around the new semantic filters — needs revision to reflect the existing specs system. |

### Jobs Field Storage Decisions

| Field | Storage | Notes |
|---|---|---|
| `jobsEmploymentType` | **specSubCat (string select)** | Full Time, Part Time, Contract, Temporary, Internship, Seasonal |
| `jobsEducationLevel` | **specSubCat (string select)** | None, High School, 2 Year Degree, 4 Year Degree, Advanced Degree |
| `jobsYearsOfExperience` | **specSubCat (string select)** | None, 1-2 Years, 3-4 Years, 5-7 Years, 8-10 Years, >10 Years |
| `jobsCompanyPerks` | **specSubCat (multiple string slots)** | Each perk as a separate spec slot (boolean-like select). Work remote, Flexible schedule, etc. |
| `jobsPayRangeType` | **Top-level** | "hourly" or "salary". Controls interpretation of payFrom/payTo. |
| `jobsPayFrom` / `jobsPayTo` | **Top-level** | int (cents). Range filter — needs custom filter mapping in SRP. |
| `jobsApplicationUrl` | **Top-level** | External apply link. Not filterable — Detail Page only. |
| `jobApplicationDeadline` | **REMOVING — TODO verify** | Marked for removal. Verify with team that this field is not needed. |
| `marketType` | **Top-level (existing)** | Add "Job" as a new valid value to the existing shared field. |

---

## 2. SRP (Search Results Page)

| # | Question | Status | Owner | Answer |
|---|----------|--------|-------|--------|
| 2.1 | What Mongo fields need to sync to Elasticsearch for Jobs? Audit current Jobs data vs. what's already in ES. | ✅ | Engineering | specSubCat fields (employmentType, educationLevel, yearsOfExperience, companyPerks) should sync automatically via existing pipeline. Top-level fields (`jobsPayRangeType`, `jobsPayFrom`, `jobsPayTo`, `jobsApplicationUrl`) **need new ES mappings added** and Mongo connector updates. |
| 2.2 | How does listing type filtering work in ES today? Confirm the index structure and whether a `listingType` field exists or needs to be added. | ✅ | Chris | Yes — ES has `marketType` field which maps to "listing type" in the UI. Adding "Job" as a new `marketType` value (decided in 1.1) enables same-index filtering. No structural changes needed. |
| 2.3 | SRP display rules — who defines the frontend behavior? What does "list format" vs "grid format" look like? Is this covered in Figma? | ✅ | Frontend | **Frontend only.** Backend returns listings; frontend decides grid vs list based on selected categories. No backend display hints needed. |
| 2.4 | Is moving SRP search logic from GraphQL to a dedicated service still in scope, or was that tied to the specs redesign? | ✅ | Engineering | **Already completed.** SRP search logic has been moved to a dedicated backend service. |
| 2.5 | Frontend resource allocation — who from frontend is assigned and what is their availability? | 🟡 | PM | **Not yet assigned.** This is a blocker/risk — frontend work is required for SRP, Detail Page, and MyAccount. |
| 2.6 | How should Jobs appear as a listing type option alongside For Sale, In Search Of, and For Rent? | ✅ | Chris | **Top-level filter option.** Jobs appears as a selectable `marketType` filter alongside For Sale, In Search Of, For Rent. Users can toggle it on/off independently of category. |

---

## 3. Detail Page

| # | Question | Status | Owner | Answer |
|---|----------|--------|-------|--------|
| 3.1 | What does the Phase 1 Listing Service already provide for detail page reads vs. what's missing for Jobs? | ✅ | Engineering | Listing Service GET endpoint exists but **needs expansion** to return Jobs-specific fields (pay range, employment type, application URL, etc.). GraphQL + frontend wiring also needed. |
| 3.2 | What Jobs-specific fields need to appear on the detail page? (Reference: Jobs Listing Fields research doc) | ✅ | Chris | **Standard:** Title, Description, Company Name (businessName), Photos, Location, Contact Info. **Jobs-specific from specSubCat:** Employment Type, Education Level, Years of Experience, Company Perks. **Jobs-specific top-level:** Pay Range (type + from/to), Application URL. |
| 3.3 | What is the GraphQL endpoint structure for updating a listing? Does this build on existing Phase 1 work or require new mutations? | ✅ | Chris | **N/A for Detail Page.** Listings are not edited from the Detail Page — editing happens via the Post-A-Listing (PAL) form, which is **out of scope** for this project. Detail Page is read-only. |
| 3.4 | Legacy compatibility — the doc mentions continuing to store contact info and verification status on listing documents near-term. What is the timeline/criteria for removing this? | ✅ | Chris | **Not applicable** to Phase 2. |
| 3.5 | Are Detail Page mockups/designs needed, or does the unified detail page handle Jobs dynamically? | 🟡 | Design | **Partially dynamic.** Design input needed for Jobs top-level fields only: pay range display, Apply button (applicationUrl). specSubCat fields render through existing specs UI. |

---

## 4. MyAccount

| # | Question | Status | Owner | Answer |
|---|----------|--------|-------|--------|
| 4.1 | What existing ES queries are being reused for viewing listings in MyAccount? Identify them. | 🟡 | Engineering | **Needs investigation.** Engineering needs to audit current MyAccount ES queries to understand what exists and what needs updating for Jobs listings. |
| 4.2 | Soft Delete data model — what does it look like? (`deletedAt` timestamp? `status` field? Both?) | ✅ | Chris | **Both.** Use a status change (e.g., 'deleted') on the existing status field AND a `deletedAt` timestamp for auditing and purge scheduling. |
| 4.3 | Soft Delete retention period — what is the retention period before final purge? **Requires Legal input.** | 🟡 | Legal | **Not started.** Legal has not been contacted yet. This needs to happen before build to define retention period and purge behavior. |
| 4.4 | CX Restore tool — what is the endpoint contract? Has CX been consulted on their workflow needs? | 🟡 | CX | **Not started.** CX needs to be consulted to understand their restore workflow requirements before building the endpoint. |
| 4.5 | Does soft delete affect listing counts, search results, or billing? | ✅ | Chris | **Yes — full removal.** Soft-deleted listings are excluded from search (ES), don't count toward active listings, and billing/subscriptions stop. **Users can reactivate** within their limits, but must go through checkout flow again to pay for any canceled subscriptions. CX can also restore. |
| 4.6 | Edit flow — what fields can a user edit on a Jobs listing from MyAccount? Same as PAL or a subset? | ✅ | Chris | **No field editing in MyAccount** — editing goes through PAL (out of scope). MyAccount actions: **view, mark as sold, mark as sale pending, delete (soft delete), renew, reactivate.** Reactivate uses existing request activation endpoint. The rest (mark sold, mark sale pending, delete, renew) **need new endpoints on the Listing Service.** |

---

## 5. Saved Search Impact

The shaping doc warns: *"Take into consideration what effect this work will have on Saved Search."* There are 12,000+ saved searches that could be affected.

| # | Question | Status | Owner | Answer |
|---|----------|--------|-------|--------|
| 5.1 | How are saved searches stored today? Do they reference specs IDs, category IDs, or URL patterns? | ✅ | Chris | **Deferred to Phase 3.** Saved Search & Alerts will be handled in the next build cycle. |
| 5.2 | Will any Phase 2 changes (new listing type, ES index changes) break existing saved searches? | ✅ | Chris | **Low risk / not a concern for Phase 2.** No existing saved search should match documents with Job data. Risk exists around saving new searches from SRP, but that's Phase 3 scope. |
| 5.3 | Is this a blocking concern for Phase 2, or documentation/prep for Phase 3? | ✅ | Chris | **Not blocking.** Phase 3 will handle saved search integration with Jobs. |
| 5.4 | Review the existing Saved Search & Alerts research doc for relevant findings. | ✅ | Chris | **Deferred to Phase 3.** |

---

## 6. App Work (2-week estimate)

| # | Question | Status | Owner | Answer |
|---|----------|--------|-------|--------|
| 6.1 | When users select Jobs on app, what does "opens to pre-selected Jobs subcategories" mean? Which subcategories? | ✅ | Chris | **App-only feature.** When a user taps the Jobs tab, the app auto-selects the Jobs category and displays its subcategory list (same pattern as Services today). Jobs should also be removed from global search. |
| 6.2 | Does the unified detail page in app already support dynamic fields, or does it need modification for Jobs? | ✅ | App | **Needs modifications.** The app detail page needs changes to render Jobs-specific top-level fields (pay range, Apply button/applicationUrl). |
| 6.3 | PAL job-specific fields — what are they specifically? Who owns this list? (Reference: "hard-code fields similar to Cars") | 🟡 | App | **Needs clarification.** Confirm with App team whether PAL (posting/editing Jobs on app with hard-coded fields) is included in the 2-week app estimate or out of scope. |
| 6.4 | Does the app team have capacity within the timeline? | 🟡 | App | **Not confirmed.** App team needs to confirm 2-week availability for Phase 2 work. |

---

## 7. Cross-Cutting / Coordination

| # | Question | Status | Owner | Answer |
|---|----------|--------|-------|--------|
| 7.1 | **Legal:** Has the conversation about soft-delete retention/purge behavior been initiated? | 🟡 | Legal | **Not started.** See 4.3. Needs to be initiated before build. |
| 7.2 | **Frontend:** Who is assigned? What's their availability window? | 🟡 | PM | **Not assigned.** See 2.5. Blocker/risk for Phase 2. |
| 7.3 | **Design:** Figma SRP mockups need updates. Are Detail Page and MyAccount mockups also needed? | 🟡 | Design | SRP Figma **needs update** (see 1.4). Detail page needs design for top-level Jobs fields only (see 3.5). MyAccount TBD. |
| 7.4 | **CX:** Restore tool endpoint — has CX been consulted on their workflow? | 🟡 | CX | **Not started.** See 4.4. |
| 7.5 | **Analytics:** What events/metrics should be instrumented? Is there a measurement plan? | 🟡 | Analytics | **Not started.** Needs discussion with analytics team. |
| 7.6 | **Trust & Safety:** Any considerations for Jobs listings (spam, scam patterns)? | ✅ | T&S | **Already handled** in Phase 1 / prior work. No additional T&S work needed for Phase 2. |

---

## Research References

Existing research docs from Phase 1 (in `Shaping Projects/Jobs to Classifieds/Engineer Research/`):
- Category Sub-cat Specifications
- Job Feeds
- Jobs Favorites
- Jobs Listing Fields For Moving Into General Classifieds
- Listing API requirements for Classifieds (draft)
- Listing Stats
- Pay ranges
- Quick Apply (Phase 4 — out of scope)
- Saved Search & Alerts (Phase 3 — but impacts need to be understood)
- Top Jobs
