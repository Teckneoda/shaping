# Jobs to Classifieds - Phase 4 — Features

## Feature 1: Apply Now Workflow

### Description
Allow job seekers to apply to job listings through a streamlined application form. Users enter basic contact info, upload a resume (and optional cover letter), and submit the application.

### Requirements
- Application form collects: first name, last name, email, zip code, education level, experience level
- Education level options: None, Advanced Degree, 4-year Degree, 2-year Degree, High School
- Experience level options: None, 1-2 years, 3-4 years, 5-7 years, 8-10 years, >10 years
- Resume upload required (file upload only — **plain text paste is NOT being migrated**)
- Cover letter upload optional (file upload only)
- Allowed file types: doc, pdf, docx, jpg, jpeg, png
  - **QUESTION**: Should BMP be supported? Legacy allowed it, but it's uncommon for resumes. Resolve with team.
- File size limit: 4MB per file (**DECIDED 2026-06-30** — standardize on 4MB across Apply Now and Quick Apply)
- **Applicants must be logged-in members** (**DECIDED 2026-06-30** — no anonymous applications). memberId is always stored with the application.
- If user has a Quick Apply profile, pre-fill the form fields and attach saved resume
- Rate limit application submissions to deter spam (new — legacy had no explicit limit). Since applicants are always logged-in, throttle is **keyed on memberId** (reuse the profile-service per-member throttle pattern; no per-IP throttling needed — **DECIDED 2026-06-30**)
- Application record stored in MongoDB with all applicant data + file references

### Apply-Method Branching (on-site form vs. external URL)

A job listing has two apply methods. **The distinction already exists in the data model and just needs the Apply CTA wired up.**

- **Existing infrastructure (already built — not Phase 4 work):**
  - Post-a-listing captures `jobsApplicationMethod` (`BUTTON_GROUP`: `"ksl"` = "Apply Through KSL" vs `"url"` = "Apply Through Your Site") — [classified-config.tsx:476-489](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/sell/post-a-listing/config/classified-config.tsx#L476). This is **frontend-only UI state**; it is NOT persisted as a server enum.
  - When `"url"`, `jobsApplicationUrl` (full http/https URL, validated by [validateJobsApplicationUrl.ts](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/sell/post-a-listing/utils/validateJobsApplicationUrl.ts)) is required; cleared when `"ksl"`.
  - `jobsApplicationUrl` is persisted end-to-end: backend `JobsApplicationURL *string` ([listing.go:1317](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/types/listing.go#L1317)), graphql `jobsApplicationUrl: String` on `ClassifiedListing`, and it's already returned by the listing-detail query (`fetchListing.ts`).
- **The branching rule (implicit, by presence — copy legacy):**
  - **If `jobsApplicationUrl` is non-null → external apply**: Apply button links to that URL, **opens in a new tab**.
  - **If `jobsApplicationUrl` is null → on-site apply**: Apply button opens our new Apply Now form (Feature 7).
  - Mirrors legacy [`getApplicationUrl()`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site/public/js/react/src/listing/components/Connected/index.js#L362) (`applicationUrl || /apply-new/{id}`; `newTab = !!applicationUrl`).
- **Phase 4 work**: add the **Apply CTA to the job listing detail page** — there is currently **no Apply button** in marketplace-frontend (`ActionButtons` has only Favorite/Share/Print/Report); `jobsApplicationUrl` is fetched but unused. The CTA branches on `jobsApplicationUrl` presence as above.
- **Note**: there are only **two** modes (on-site form, external URL). There is no separate "apply by email" mode — see the employer-email gap in Feature 4.

### Legacy Reference
- **Controller**: [ApplyController.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/api/controllers/ApplyController.php)
- **Application Entity**: [Application.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/Schema/Entities/Application/Application.php)
- **MongoDB Collection**: `jobsApplication`

---

## Feature 2: Resume Upload & Virus Scanning

### Description
Secure file upload for resumes and cover letters with integrated virus scanning before storage.

### Requirements
- **Upload + virus-scan approach — DEFER TO BUILD PLANNING (planning-state Q18); leaning Option C.** Files are saved through `application-http-rest`, which virus-scans (`virus-scan-http-rest`) and rejects infected files. *How* the bytes reach GCS has three candidate approaches:
  - **(A/B) Signed-URL upload** — client PUTs directly to GCS, scan runs **post-upload** (quarantine+promote, or scan-in-place+delete).
  - **(C) Through-API multipart + synchronous in-request scan** — the **legacy model** (scan the upload before it ever lands in GCS). **⭐ Likely preferred**: simplest, and its synchronous scan/store/persist fits the **"Thank you for applying" confirmation modal** (async A/B would show the modal before the file is verified/stored, or need a pending/finalize step).
  - Full comparison + caveats in planning-state Q18.
- File metadata stored: URL, storage key, original filename, extension, size in bytes
- Upload filename format: `YYYY-MM-DD_FirstName_LastName_[resume|coverletter].extension` (matching legacy convention)
- **Legacy reference**: today everything is inline in one request — multipart `POST /apply/save` → validate ext/size → synchronous `clamdscan` on the temp file → store to S3 → delete temp; no quarantine, no async (this is Option C).
- **Download via authorized proxy API (DECIDED 2026-06-30)**: resume/cover-letter files are served through an authorized download-proxy endpoint that authenticates the caller and streams bytes from private GCS. **Signed URLs are NOT used for download** (resumes are PII).

### Virus Scanning — DECIDED: keep existing service
- **Decision (2026-06-30)**: continue using the existing `virus-scan-http-rest` ClamAV service — no new/different approach.
- **Service**: `apps/security/services/virus-scan-http-rest/` in marketplace-backend uses ClamAV
  - Endpoint: `POST /virus-scan-http-rest/scan`, max upload: 20MB
  - Returns: `{fileClean: bool, virusSignature: string}`

### File Storage — DECIDED: GCS
- **Decision**: New resume/cover letter files are stored in a **GCS bucket** (consistent with marketplace-backend's image service). A new dedicated bucket for jobs application files (e.g. via env var like `image-http-rest`'s `HTTP_IMAGE_BUCKET`) — exact bucket name TBD with Platform.
- Follow the `image-http-rest` storage pattern: `GCSStorage.Upload` in `services/media/shared-image-packages/storage/storage.go` (streaming writer, bucket from env).
- Legacy files currently live in S3 bucket `mplace-jobs.ksl.com`.
- **Migration impact**: existing ~15K resume files must be **re-uploaded from S3 → GCS**; `legacy-bridge-s3-sync` can assist (see Feature 6).

### Legacy Reference
- **File Manager**: [FileManager.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/Schema/Entities/Application/FileManager.php)
- **Virus Scanner**: [VirusScanner.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/JobsUtils/VirusScanner.php)
- **Legacy S3 Bucket**: `mplace-jobs.ksl.com`

### Out of Scope (Phase 4 overall — per Notion)
- Plain text resume paste (NOT migrating per Notion doc)
- Plain text cover letter paste (NOT migrating per Notion doc)
- **Favorite employers feature** (buggy on legacy — explicitly out of scope per Notion)

---

## Feature 3: Quick Apply Profiles

### Description
Allow logged-in users to save their contact info and resume for faster job applications. Data is managed in the Quick Apply section of MyAccount.

### Requirements
- Quick Apply profile stores: first name, last name, email, zip, education level, experience level, resume file
- Operations: create/update profile (upsert), retrieve profile. **No delete** — removing/deleting a Quick Apply profile is **out of scope** (no delete endpoints).
- Resume upload follows same virus scanning flow as Apply Now
- When applying to a job, user can pre-fill from Quick Apply profile
- **Quick Apply form already exists in the MyAccount app** — Phase 4 only **re-points its backend** to the new `application-http-rest` Quick Apply endpoints; the UI is **not** rebuilt in marketplace-frontend (see Feature 7 + planning-state Q5/Q16)
- **No cover letter** in Quick Apply (matches legacy behavior — Apply Now only)

### Quick Apply Update Flow — DECIDED

When applying, the user can opt in to also save/update their Quick Apply profile. **The dual-write is orchestrated in the GraphQL layer**, not in the backend application service:

- **Mechanism — DECIDED (2026-06-30)**: an opt-in **checkbox on the Apply Now form** (no button/redirect to MyAccount).
- **Apply Now form** offers an opt-in control ("save/update my Quick Apply info").
- **`submitJobApplication` mutation** takes an `updateQuickApply: Boolean` input. When `true`, the **resolver makes two backend calls**:
  1. `PUT /quick-apply` to upsert the profile — **failures are logged but do NOT block/fail the application submission**.
  2. `POST /application` to submit the application.
- This keeps `application-http-rest` endpoints single-purpose; the GraphQL resolver coordinates the two calls.
- Backend REST: no conditional dual-write logic inside `POST /application` — the two endpoints stay independent.

### Legacy Reference
- **Quick Apply Entity**: [QuickApply.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/Schema/Entities/Application/QuickApply.php)
- **MongoDB Collection**: `jobsQuickApply`
- **Key**: memberId (one profile per user, upsert behavior)

---

## Feature 4: Employer Notifications

### Description
Notify employers via email when job applications are submitted, and provide an application management view in MyAccount.

### Requirements
- **Email notification on application received** (new feature — enhanced from legacy):
  - **Always sent — DECIDED (2026-06-30)**: no employer opt-out; the application email is always sent.
  - ✅ **Email source — DECIDED (2026-06-30, resolution order)**:
    1. **General dealer email** if available, else
    2. the listing's existing contact `Email` / `EmailCanonical` field (`ClassifiedListing.Email *string` at [listing.go:1275-1276](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/types/listing.go#L1275)), else
    3. **fallback** to the posting member's account email via the member API `/members/{memberId}` (the pattern Cars' email-seller uses — [email-owner.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/email-owner.go) + [member.go `GetBasicMemberInfo`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/member/member.go#L246-L271)).
  - There is no dedicated `jobsApplicationEmail` field and we are **not** adding one. **TODO before building**: confirm `Email`/`EmailCanonical` are actually populated for job posts in the post-a-listing flow. (Note: external-URL listings apply off-site, so they don't trigger this — confirm whether they should still be notified; likely no.)
  - Subject: "Resume from [Full Name] for [Job Title]"
  - Body includes: applicant name, email, zip, education level, experience level
  - Resume file attached to email
  - Cover letter attached (if submitted)
- **MyAccount Applications view** (employer-facing):
  - Accessible via MyAccount > Listing > Manage > Applications
  - Displays list of applicants with: name, date, email, experience, zip, education
  - Download links for resume and cover letter files
  - **Format — DECIDED (2026-06-30)**: keep the **legacy modal** (not a standalone page).
  - **NTH**: Ability to remove applicants from the list (CX-requested feature)

### Legacy Reference
- **Application Emailer**: [ApplicationEmailer.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/Schema/Entities/Application/ApplicationEmailer.php)
- **Email Template**: [recievedApplication.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/api/template/emailTemplates/application/recievedApplication.php)

---

## Feature 5: Applicant Confirmation Notification — ❌ OUT OF SCOPE (DECIDED 2026-07-08)

### Decision
**No confirmation email is sent to the applicant / sender.** Instead, the applicant gets an on-screen **"Thank you for applying" confirmation modal** immediately after a successful submission (see Feature 7, screen 5). This matches the Notion shaped package (*"🚫 No email confirmations — just a modal when the user submits applications"*).

The legacy applicant/sender confirmation email is **not being migrated**.

### What this replaces
- ~~Email sent to applicant's email address after successful application submission~~
- ~~Email content: job title, company name, job location (city, state), job posted date~~
- ~~Subject: "Your application for [Job Title] is on its way!"~~
- ~~Mailgun template `jobs-application-confirmation`~~ (no longer needed — see Services.md)

### Legacy Reference (not reimplemented)
- **Confirmation Email Template**: [senderConfirmation.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/api/template/emailTemplates/application/senderConfirmation.php) — retained only as a record of legacy behavior.

---

## Feature 6: Legacy Data Migration

### Description
Migrate existing Quick Apply profiles and (optionally) application history from the legacy Jobs platform.

### Requirements
- **Quick Apply migration**: `jobsQuickApply` → new collection; **migrate resume files S3 → GCS** and rewrite file references to new GCS keys/URLs
- **Application history migration**: `jobsApplication` → new collection; same S3 → GCS file migration for resumes/cover letters
- Use Phase 3.1's `jobListingMigrations` collection to map legacy jobId → new ClassifiedListing ID
- Approximately 15,000+ resumes to migrate from `mplace-jobs.ksl.com` (S3) to the new GCS bucket
- `legacy-bridge-s3-sync` (`apps/legacy-bridge/services/legacy-bridge-s3-sync/`) can assist with the S3 → GCS file copy

### Dependencies
- Phase 3.1 complete (listing migration + ID mapping)
- Storage decided (GCS) — migration re-uploads files from S3 to GCS (see Feature 2)

---

## Feature 7: Frontend UI Recreation (marketplace-frontend)

### Description
The Jobs application UI splits across **two destinations** — get this right, it changes scope:
- **Apply Now flow → rebuilt net-new in `marketplace-frontend`.** Legacy lives in `m-ksl-jobs` as **Zend PHP `.phtml` views + jQuery** (server-rendered, no React); rebuild from scratch using the legacy templates as the visual/behavioral spec. This is the bulk of the marketplace-frontend work (screens 1–6 below).
- **Quick Apply form + Employer Applications view → stay in the MyAccount app** ([deseretdigital/m-ksl-myaccount-v2](https://github.com/deseretdigital/m-ksl-myaccount-v2), now in project.json, branch `master`), where they **already exist** as React components. Phase 4 **re-points their backend** to the new `application-http-rest` + new resume-download mechanism — these are **NOT** rebuilt in marketplace-frontend (screens 7–9 below). ⚠️ marketplace-frontend has **no authenticated MyAccount area** (its `app/profile/` is only the public read-only `[seller]` viewer; authed account features link out to `myaccount.ksl.com`).

### Target stack (marketplace-frontend)
- Next.js 16 App Router, `@monorepo/cascade-v2` design system, TailwindCSS v4
- Forms: native `<form>` + `FormData` + **Zod** validation (no Formik/react-hook-form)
- Mutations/queries: server actions calling `graphql-request` (`packages/graphql/request.ts`), defined per-operation under `apps/ksl-marketplace/services/`
- File upload: **react-dropzone** + server action pattern from `sell/post-a-listing/components/Photo/Photos.tsx`
- Auth/session: `@monorepo/ksl-session`; analytics via `@monorepo/analytics` DataLayer

### Screen-by-screen inventory (legacy → new)

| # | Screen / Component | Legacy source | New home in marketplace-frontend | Pattern to copy |
|---|--------------------|---------------|----------------------------------|-----------------|
| 1 | **Apply Now form** — first/last name, email, zip, education + experience dropdowns, resume upload (required), cover letter upload (optional) | [index-responsive.phtml](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site/application/views/scripts/apply/index-responsive.phtml) + [apply.js](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site/public/js/responsive/apply.js) | **Dedicated child or sibling page** under `listing/[id]/` (**DECIDED 2026-06-30** — page, not a modal; routing options TBD from user) | `listing/[id]/components/Contact/EmailModal.tsx` (native form + Zod + server action) |
| 2 | **Resume / cover letter upload control** — drag/drop + browse, allowed types, 4MB limit messaging, error states (wrong type, too large, **virus detected**) | apply.js file-size + extension validation | Apply form + Quick Apply | `sell/post-a-listing/components/Photo/Photos.tsx` (react-dropzone + `addPhoto` server action) |
| 3 | **Pre-fill from Quick Apply** — auto-fill fields + attach saved resume; remove resume ("X") then **"Use From Quick Apply"** to re-attach | QuickApply pre-fill in ApplyController + QuickApply.tsx saved-resume display | Apply form | QuickApply.tsx saved-resume display/remove/re-attach interaction |
| 4 | **"Update Quick Apply info" checkbox + confirmation modal** (**DECIDED 2026-06-30** — checkbox on the Apply Now form; see Feature 3) | Notion screenshots ("Update Quick Apply info" modal) | Apply form | Cascade `Modal` + checkbox |
| 5 | **Application submitted confirmation** — "Thank you for applying…", job/company/contact summary. **This modal is the applicant's only confirmation — no email is sent (Feature 5).** | [thanks.phtml](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site/application/views/scripts/apply/thanks.phtml) | Apply flow success state | Server-action success → confirmation view |
| 6 | **Apply error screen** — validation/processing errors, back link | [error.phtml](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site/application/views/scripts/apply/error.phtml) | Apply flow error state | Inline error + Zod messages |
| 7 | **MyAccount Quick Apply section** — same fields as Apply Now minus cover letter, saved-resume link, remove ("X") + "Save Info" | [QuickApply.tsx](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Profile/QuickApply.tsx) (~638 lines), mounted at `/profile#quick-apply-info` | **MyAccount app (already exists)** — NOT marketplace-frontend | **Re-point backend** to new `application-http-rest` Quick Apply endpoints + update saved-resume download link (Q3c). No UI rebuild. |
| 8 | **Employer Applications view** — applicant list: name, date, email, experience, zip, education + resume/cover letter download links; empty/loading/error states | [JobApplicationsModal.tsx](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Listing/Manage/Modals/JobApplicationsModal.tsx) (~186 lines) | **MyAccount app (already exists)** — NOT marketplace-frontend | **Re-point backend** to new applications endpoint + new resume download mechanism (Q3b). **NTH**: standalone page instead of modal. |
| 9 | **"Applications" entry in listing Manage menu** — only shown when application count > 0 | [JobManage.tsx](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Listing/Manage/JobManage.tsx) (menu config + modal wiring) | **MyAccount app (already exists)** — NOT marketplace-frontend | Re-point count source to new backend. No UI rebuild. |

### Field & validation parity (copy from legacy)
- Education: None, Advanced Degree, 4-year Degree, 2-year Degree, High School
- Experience: None, 1-2 years, 3-4 years, 5-7 years, 8-10 years, >10 years
- Validators (legacy `field-validators.ts` / apply.js): email regex, name (`^[A-Za-z \-']+$`), zip (`^\d{5}(-\d{4})?$`)
- File types: doc, pdf, docx, jpg, jpeg, png (**BMP TBD** — legacy allowed it; still an open question)
- File size: **4MB** across both Apply Now and Quick Apply (**DECIDED 2026-06-30** — standardize on 4MB; legacy MyAccount Quick Apply previously allowed 10MB).

### Intentionally NOT recreated (out of scope per Notion)
- "Copy and paste my resume" / "Copy and paste my cover letter" **plain-text fields and radio toggles** (present in both legacy Apply Now and Quick Apply UIs) — file upload only.
- Favorite employers feature.

### Open questions (frontend-specific)
- _None outstanding._ (Resume/cover-letter download mechanism resolved 2026-06-30 — see Resolved below.)

### Resolved (2026-06-30)
- ~~**Resume/cover letter download links**~~: **authorized download-proxy API** on `application-http-rest` (auth caller → stream from private GCS). **No signed URLs for download** (PII). MyAccount Applications view + Quick Apply saved-resume links point at this proxy (replacing legacy `/apply/download-application`).
- ~~**Apply page placement**~~: **dedicated child or sibling page** in marketplace-frontend (not a modal); routing options to come from user later.
- ~~**Applications view format**~~: **keep the legacy modal** (NTH standalone page dropped) — also in Feature 4.
