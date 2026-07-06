# Jobs Spec Fields Pivot — Change Summary

**Date:** 2026-06-16
**Trigger:** Pivot based on discussion with Classifieds team on June 12, 2026

## The Pivot

Three legacy Jobs listing fields were previously planned to map to **sub-category specifications**. They are now **top-level listing fields**, named and exposed the same way as the Jobs pay range fields (`jobs`-prefixed). Company Perks is **no longer being implemented**.

| Legacy field | New top-level field |
|---|---|
| `employerStatus` (ft/pt/ct/tm) | `jobsEmploymentType` |
| `educationLevel` (0-4) | `jobsEducationLevel` |
| `yearsOfExperience` (int) | `jobsYearsExperience` |
| `companyPerks` | **Not implemented** (dropped) |

Naming follows the existing pay range pattern (`jobsPayRangeType`/`jobsPayFrom`/`jobsPayTo`; PascalCase `JobsPayFrom` in backend-model contexts). These fields are exposed via **custom filter mapping** (like pay range), not the subcategory-spec AvailableFilters pipeline.

---

## Local Shaping Doc Changes

### 002 Jobs Phase 2 *(no Notion doc linked)*
- **Research.md** — Q1.1/1.3/2.1/3.2/3.5: flipped storage from `specSubCat` to top-level; field storage table updated (3 fields → Top-level, `jobsCompanyPerks` struck as "Not implementing").
- **Features.md** — §1.1 Category Manager no longer configures Jobs specs; §2.1 ES mappings add the 3 fields; §3.1/3.2/3.3 SRP filters now custom-mapped (no specSubCat); §4.1/4.3 detail page renders them as top-level.
- **Services.md** — Listing GET, SRP search service, GraphQL SRP/detail, ES index mapping table, Mongo connector, Category Manager, and frontend sections all updated to treat the 3 fields as top-level and drop Company Perks.

### 003 Jobs to Classifieds - Phase 3.1
- **Features.md** — Field-mapping table: 3 rows changed from "Spec fields / sub-category specifications" to "Map → top-level `jobs*` field".
- **Services.md** — listing-http-rest now requires **3 new top-level model fields** (was "no model changes required"); migration field-transform list updated.
- **planning-state.md** — Added dated decision note; updated Field Mapping Decisions table + Complete Field Mapping rows; bumped "Last updated" to 2026-06-16.

### 004 Jobs to Classifieds - Phase 3.2
- **Features.md** — Dropped `companyPerks` from StringFilters, EditGeneral show-list, percolation ES mapping, match expected fields, and alert array-contains config; annotated legacy `criteria_companyPerks` as "not migrated"; added notes that the 3 fields correspond to the top-level `jobs*` listing fields.
- **Services.md** — Same companyPerks removals + correspondence notes across percolation/match/alert sections.
- **planning-state.md** — Added Key Decision #7 (pivot + open question), removed "perks" from EditGeneral list, added changelog entry.
- **Note:** 004's saved-search **criteria/percolation field names were intentionally NOT renamed** (see Open Items).

### 006 Jobs to Classifieds - Phase 3.4
- **Features.md** — F3 filter mapping: `jobtype`/`experience`/`education` now map to top-level `jobs*` fields instead of subcategory specs.
- **planning-state.md** — Updated resolved question #3; added Changelog section with dated entry.

---

## Notion Sync

All Notion edits **preserve existing wording** — invalid text is struck through (`~~…~~`) and new wording is added, prepended with *"pivot based on discussion with Classifieds team on June 12, 2026"*.

### Phase 3.1 — *Migrate listings* ([page](https://app.notion.com/p/3142ac5cb2358178aac7f685e25f9e0b))
- **Field Mapping table** — the 3 rows: struck through "Spec fields" + "Map to existing sub-category specifications"; added the top-level `jobs*` field mapping.
- **Technical Details → listing-http-rest "Changes needed"** — struck through "No model changes required…sub-category specifications"; added the requirement to add 3 new top-level model fields (+ ES/Mongo connector updates).

### Phase 3.2 — *Migrate saved search* ([page](https://app.notion.com/p/3212ac5cb235808991fbd3a730bb78dd))
- **Acceptance Criteria** — struck `companyPerks` from the percolation ES mapping list; added a criterion noting Company Perks is not implemented and the 3 fields correspond to top-level `jobs*` fields.
- **F4 MyAccount** — struck `companyPerks` from the EditGeneral field list.
- **F5 Percolation** — struck `companyPerks (text)` from ES mapping; struck `array-contains for companyPerks` from Alert workers.
- **Technical Details → saved-search-alert-workers** — struck the `Add array-contains: companyPerks` line.

### Phase 3.4 — *Redirect legacy pages* ([page](https://app.notion.com/p/32e2ac5cb23580a7a772c995afc595d1))
- **F3 Search/Category filter mapping** — struck the three `→ subcategory spec` mappings; added `→ top-level jobsEmploymentType / jobsYearsExperience / jobsEducationLevel field`.

---

## Open Items / Flags

1. **007 Phase 4 — intentionally untouched.** Its `educationLevel`/`experienceLevel` are *applicant* fields on job applications, not listing spec fields, so the pivot does not apply.
2. **004 field naming not renamed.** In Phase 3.2 these are saved-search *criteria/percolation* field names, and pay range there is also bare (`salaryFrom`/`payRangeType`, not `jobsPayFrom`). Renaming only these three would create internal inconsistency. **Open question (flagged in 004 planning-state and Notion): should percolation/match/alert reference the saved-search criteria names or the `jobs`-prefixed listing field names?**
3. **002 has no `project.json`/Notion doc**, so only the local shaping docs were updated there.
