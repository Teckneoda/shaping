# Planning State — Jobs to Classifieds - Phase 4

## Phase 4 Walkthrough — 10 Questions Answered (2026-06-25)

Direct answers to the core implementation questions, with concrete code locations.

### 1. Where are resume files stored?
- **New (Phase 4): GCS bucket** — a new dedicated bucket for jobs application files (resumes + cover letters), name TBD with Platform. Follows the `image-http-rest` pattern (bucket from env, cf. `HTTP_IMAGE_BUCKET`).
- **Storage is private-by-default in GCS** (unlike legacy). Files are NOT public-read. See Q3 for how they're served.
- **Legacy (today)**: AWS S3 bucket `mplace-jobs.ksl.com` with `public-read` ACL ([FileManager.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/Schema/Entities/Application/FileManager.php#L68-L91), [S3Utils.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/JobsUtils/S3Utils.php)). ~15K files to migrate (Feature 6).
- File metadata stored alongside the application record in MongoDB: `{ url, storageKey, name, extension, sizeInBytes }`.

### 2. How will they be saved (which API)?
- **Upload mechanism — DEFER TO BUILD PLANNING (see Q18); currently leaning Option C.** Files are saved through the **new `application-http-rest` service** (`apps/jobs/services/application-http-rest/` in marketplace-backend), which virus-scans and persists the application + file metadata to MongoDB. *How* the bytes get to GCS is the open part — three candidate approaches in Q18: **(A/B) signed-URL upload** (client PUTs directly to GCS, scan post-upload) vs. **(C) through-API multipart + synchronous in-request scan** (the legacy model). **Option C is currently likely preferred** (simplest, and the synchronous flow fits the "Thank you for applying" confirmation modal — see Q18).
- Upload filename convention (copy legacy): `YYYY-MM-DD_FirstName_LastName_[resume|coverletter].extension`.
- **DECIDED (Q17)**: `application-http-rest` **owns the GCS interaction directly** (imports the shared `GCSStorage` storage package); it does NOT delegate to `image-http-rest`.
- ⚠️ **Virus-scan ordering**: under Option C, scan is **synchronous before store** (exactly like legacy). Under signed-URL Options A/B, scan is **post-upload** (backend pulls the GCS object → `virus-scan-http-rest` → delete/quarantine on infection). See Q18 for the full comparison + caveats.

### 3. How will they be viewed on every surface that needs them?
Three surfaces consume resume/cover-letter files:
- **(a) Employer email attachment** — files attached directly to the employer notification email via `emailsv1.EmailMessage.Attachments` (base64 `content`). No URL needed on this surface. See Q4 + Email Infrastructure section.
- **(b) Employer Applications view** (MyAccount) — download links per applicant. **Because GCS is private, we cannot use a public URL like legacy did.** **DECIDED (2026-06-30): authorized download-proxy API** — **NOT** signed URLs for download.
  - **Authorized download-proxy endpoint** on `application-http-rest` (mirrors legacy [`/apply/download-application`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site/application/controllers/ApplyController.php#L414-L471), which stream-proxied from S3 after authorizing the logged-in member owns the job). The endpoint authorizes the caller, then streams the object's bytes from GCS through the API.
  - ⚠️ Resumes are **PII** — do NOT expose via the public `image.ksldigital.com` CDN path, and (per this decision) do NOT hand out signed GCS download URLs. (Resolves Q13.)
  - Legacy employer links: [JobApplicationsModal.tsx:69-86](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Listing/Manage/Modals/JobApplicationsModal.tsx#L69-L86) → `/apply/download-application?applicationId=…&type=resumeFile|coverLetterFile`. The existing MyAccount Applications view will need these download links updated to the new mechanism.
- **(c) Quick Apply saved-resume display** (existing MyAccount Quick Apply form + Apply Now pre-fill) — shows saved resume filename as a link; legacy used the direct `s3Url` ([QuickApply.tsx:366-391](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Profile/QuickApply.tsx#L366-L391)). New: same **authorized download-proxy** mechanism as (b).

### 4. Where do we need to send an email to the client (employer) when someone applies?
- **Trigger**: on successful `POST /application` for an **on-site ("ksl") apply** listing, `application-http-rest` publishes an employer-notification email to the `Public_SendEmail` pub/sub topic (protobuf `emailsv1.EmailMessage`), resume/cover-letter as `Attachments`. New Mailgun template `jobs-application-employer-notification`. Subject: `Resume from [Full Name] for [Job Title]`.
- **Email target — DECIDED: use the listing's contact `Email` / `EmailCanonical` field.** The new `ClassifiedListing` struct already has `Email *string` ([listing.go:1275](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/types/listing.go#L1275)) and `EmailCanonical *string` (line 1276) captured on the posting form. **TODO: confirm these are actually populated for job posts** (post-a-listing flow). Fallback if not populated: resolve the posting member's account email via the member API `/members/{memberId}` (the pattern Cars' email-seller uses — [email-owner.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/email-owner.go) + [member.go `GetBasicMemberInfo`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/member/member.go#L246-L271)).
- **Note**: `emailListingOwner` is explicitly NOT implemented for `ListingTypeJob` today ([email-owner.go:127-128](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/email-owner.go#L127)) — but Phase 4 sends the employer email from the backend application service, not via that resolver.
- External-URL listings apply off-site, so they don't trigger this email (confirm whether they should be notified at all — likely no).
- Legacy: [ApplicationEmailer.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/Schema/Entities/Application/ApplicationEmailer.php).

### 5. What MyAccount updates are needed?
**Key point: the Quick Apply form and Employer Applications view already exist in the MyAccount app** (legacy `m-ksl-myaccount-v2` / its successor). They are **NOT** rebuilt in marketplace-frontend. Phase 4 work on the MyAccount side is **re-pointing the existing UI at the new backend**, not a UI port:
- **Quick Apply profile form** — already built in MyAccount ([QuickApply.tsx](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Profile/QuickApply.tsx), route `/profile#quick-apply-info`). **Update the backend it hits** to the new `application-http-rest` Quick Apply endpoints (Q7/Q8). Saved-resume download link updated to the new GCS mechanism (Q3c).
- **Employer Applications view** — already built in MyAccount ([JobApplicationsModal.tsx](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Listing/Manage/Modals/JobApplicationsModal.tsx), reached via Listing → Manage → Applications, menu in [JobManage.tsx](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Listing/Manage/JobManage.tsx), shown only when count > 0). **Update the backend it hits** to the new applications endpoint + new resume download mechanism (Q3b).
- ⚠️ The MyAccount app is **NOT in this project's repos** (project.json has only marketplace-backend/-graphql/-frontend). The backend-integration changes there need scoping with frontend engineers — **add the MyAccount repo to the project** once confirmed. See Unanswered Questions Q16.

### 6. Virus scanner availability — CONFIRMED
- **`virus-scan-http-rest` exists in marketplace-backend** (`apps/security/services/virus-scan-http-rest/`), ClamAV-based. `POST /virus-scan-http-rest/scan`, multipart field `"file"`, 20MB max, returns `{fileClean: bool, virusSignature: string}`. Reuse it to scan resumes/cover letters before GCS upload. (Trufty sign-off still pending — Q4 below.)

### 7. Where and how will we save quick apply info?
- **`application-http-rest` `PUT /quick-apply`** (upsert), authenticated by member. One profile per `memberId` (primary key), matching legacy upsert behavior. **No delete endpoints** (removing/deleting Quick Apply is out of scope — confirmed).
- Stored in **MongoDB** (new collection; legacy was `jobsQuickApply`). Fields: firstname, lastname, email, zip, educationLevel, experienceLevel, resume `{url, storageKey, name, extension, sizeInBytes}` — **no cover letter** (matches legacy).
- Resume upload goes through the same virus-scan → GCS flow as Q2.
- **Two write paths into Quick Apply**: (a) the existing MyAccount Quick Apply form (Q5); (b) **as an opt-in side effect of applying** — see Q9: the `submitJobApplication` GraphQL mutation can update Quick Apply when the applicant asks.
- Legacy: [QuickApply.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/Schema/Entities/Application/QuickApply.php).

### 8. How will quick apply info be retrieved (to load saved info)?
- **`application-http-rest` `GET /quick-apply`** for the authenticated member → exposed via GraphQL query `getQuickApplyProfile: QuickApplyProfile`.
- **Two consumers**: (a) MyAccount Quick Apply form loads it to populate the edit form; (b) **Apply Now form pre-fill** — when a logged-in user opens the apply form, fetch their profile and pre-fill name/email/zip/education/experience + attach the saved resume (with remove → "Use From Quick Apply" re-attach, per legacy [QuickApply.tsx:366-391](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Profile/QuickApply.tsx#L366-L391)).

### 9. What new APIs need to be written, and where? (marketplace-backend)
**New service `application-http-rest`** (`apps/jobs/services/application-http-rest/`):
| Method | Path | Purpose |
|--------|------|---------|
| POST | `/application` | Submit application (multipart; scans + uploads files, persists, emails employer + applicant) |
| GET | `/application/{id}` | Get one application |
| GET | `/application/listing/{listingId}` | Applications for a listing (employer view) |
| GET | `/quick-apply` | Get authed member's Quick Apply profile |
| PUT | `/quick-apply` | Upsert Quick Apply profile |
| (maybe) GET | `/application/{id}/download?type=resume\|coverLetter` | Authorized download proxy (Q3 option) |
- **No Quick Apply delete endpoints** (out of scope).
- **marketplace-graphql** layer (required, but not marketplace-backend): types `JobApplication`, `ApplicationFile`, `QuickApplyProfile`; mutations `submitJobApplication`, `saveQuickApplyProfile`; queries `getQuickApplyProfile`, `getApplicationsForListing`, `getMyApplications`. New service client to call `application-http-rest`.
- **Quick Apply update on apply — orchestrated in GraphQL, NOT in the backend service.** `submitJobApplication(input)` takes an opt-in flag (e.g. `updateQuickApply: Boolean`). When true, the **resolver makes two backend calls**: (1) `PUT /quick-apply` to update the profile — **failures here are logged but do NOT block/fail the application**; (2) `POST /application` to submit. This keeps `application-http-rest` endpoints single-purpose and puts the dual-write coordination in the GraphQL layer.
- Reuses (no new code): `virus-scan-http-rest`, shared `GCSStorage`, `Public_SendEmail` pub/sub.

### 10. Where do we create the new frontend changes in marketplace-frontend?
**In scope for marketplace-frontend (confirmed exists) — the Apply Now flow only:**
- **Apply CTA on job listing detail** — add to [ActionButtons.tsx](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/[id]/components/ActionButtons.tsx) (currently only Favorite/Share/Print/Report; `jobsApplicationUrl` is fetched but unused). Branches by `jobsApplicationUrl` presence (Feature 1).
- **Apply Now form/flow** — new route/components under `app/listing/[id]/` (apply route or modal), copying [Contact/EmailModal.tsx](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/[id]/components/Contact/EmailModal.tsx) (modal + native form + Zod + server action).
- **Resume/cover-letter upload control** — copy react-dropzone pattern from [sell/post-a-listing/components/Photo/Photos.tsx](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/sell/post-a-listing/components/Photo/Photos.tsx) + its `addPhoto` server action ([app/sell/[[...id]]/actions/addPhoto.ts](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/sell/[[...id]]/actions/addPhoto.ts)).
- **Pre-fill from Quick Apply** for logged-in users (Q8b) + an **opt-in "save/update my Quick Apply info"** control that sets the `updateQuickApply` flag on the `submitJobApplication` mutation (Q9).
- **Server actions / graphql ops** — new dir `apps/ksl-marketplace/services/jobs/`, copying [services/listing/email-seller.ts](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/services/listing/email-seller.ts) (graphql-request + Zod).
- **Apply success/error states** — confirmation + error views.

**NOT in marketplace-frontend:** Quick Apply profile form + Employer Applications view — those already live in the MyAccount app and are handled there by re-pointing the backend (Q5). marketplace-frontend has no authed MyAccount area (its `app/profile/` is only the public read-only `[seller]` viewer).

---

## Identified So Far

### Apply Now Workflow
- Legacy controller: `ApplyController.php` handles full submission flow
- Legacy data model: MongoDB `jobsApplication` collection with fields for applicant info, resume/cover letter file references, jobId, memberId
- Education levels: None, Advanced Degree, 4-year Degree, 2-year Degree, High School
- Experience levels: None, 1-2yr, 3-4yr, 5-7yr, 8-10yr, >10yr
- File types allowed: doc, pdf, docx, jpg, jpeg, png (BMP TBD)
- File size limit: 4MB per file
- Plain text resume/cover letter paste is **NOT being migrated** (confirmed in Notion doc)
- Rate limiting on submissions is new (legacy had none)

### Resume Upload & Virus Scanning
- Existing `virus-scan-http-rest` service in marketplace-backend uses ClamAV (same tech as legacy)
- Endpoint: `POST /virus-scan-http-rest/scan`, 20MB max, returns `{fileClean, virusSignature}`
- Legacy stored files in S3 bucket `mplace-jobs.ksl.com` with public-read ACL
- Legacy filename format: `YYYY-MM-DD_FirstName_LastName_[resume|coverletter].extension`

#### How legacy handles upload + virus scanning (researched 2026-06-30)
**Everything is inline in the single apply request — no pre-upload endpoint, no quarantine, no async/background scan.** Concretely:
- **Entry**: multipart `POST /apply/save` (or `/apply/savejson`) → frontend [ApplyController.php `saveAction()`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site/application/controllers/ApplyController.php#L108); files arrive as `$_FILES['resume_file']` / `$_FILES['cover_file']` and are relayed to the API `apply()` controller.
- **Order (scan-then-store)** in [FileManager.php `uploadFile()`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/Schema/Entities/Application/FileManager.php#L21): validate extension → validate size → **virus scan the PHP temp file** → only if clean, `saveFile()` uploads to S3 (`mplace-jobs.ksl.com`) → delete the local temp file.
- **Scanner** = [VirusScanner.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/JobsUtils/VirusScanner.php#L16-L32) shells out **synchronously** to `clamdscan --fdpass <tmpPath>` (ClamAV daemon). Returns `0` clean / `1` virus / `2` error. **Scan only runs in production** (non-prod returns 0 / skips). On `1`, throws `FileException('A virus was detected in a resume.')` → upload aborts, nothing reaches S3.
- **Constraints**: allowed extensions `doc, pdf, docx, jpg, jpeg, bmp, png` (note: **legacy DID allow `bmp`**); **4MB combined** limit (resume + cover together).
- **Takeaway**: legacy is exactly the "Option C" model below — multipart-through-backend with a synchronous in-request ClamAV scan before storage. The new signed-URL options (A/B) are a *departure* from legacy, driven by GCS private-by-default + not streaming bytes through the API.

### Quick Apply Profiles
- Legacy: MongoDB `jobsQuickApply` collection, keyed by memberId (upsert behavior)
- Stores same fields as application minus cover letter
- Can be populated manually in MyAccount or updated from Apply Now submission
- Two approaches identified for Apply Now → Quick Apply update: button/redirect vs. checkbox

### Email Infrastructure (Resolved)
- New system uses **pub/sub → Mailgun** pattern (not legacy `JobsEmailerQueue`)
- Pub/sub topic: `Public_SendEmail`
- Message format: protobuf `emailsv1.EmailMessage` from `ddm-protobuf` package
- Fields: Recipients, Subject, Template (Mailgun template name), TemplateVariables (JSON string), FromEmail, FromName, Tags, DeliveryTime
- Existing examples: listing thank-you email (`send_email.go`), price drop notifications
- **Attachments RESOLVED**: `emailsv1.EmailMessage` **supports attachments** via `repeated Attachment attachments = 7`. Each `Attachment` has `filename`, `type` (MIME), `content` (base64). Source: `ddm-protobuf/proto/emails/v1/email_message.proto:30-34`. Employer emails can attach resume/cover letter directly. Caveat: no existing caller sets `Attachments` (all current callers are template-only), so Phase 4 will be the first — validate end-to-end delivery and any payload-size limits for ~4MB files.
- Two new Mailgun templates needed: employer notification + applicant confirmation

### Employer Notifications
- Legacy sent resume email + optional cover letter email to employer contact email
- Subject format: "Resume from [Full Name] for [Job Title]"
- Attachments: actual resume/cover letter files from S3

### Applicant Confirmation
- Legacy sent confirmation email: "Your application for [Job Title] is on its way!"
- Includes: job title, company name, location, posted date

### Existing Infrastructure in marketplace-backend
- Jobs listing fields exist on ClassifiedListing: `jobsApplicationURL`, `jobsPayRangeType`, `jobsPayFrom`, `jobsPayTo`
- **File upload pattern** — `apps/media/services/image-http-rest/`: multipart form (field `"image"`), 20MB max, streams to GCS via `services/media/shared-image-packages/storage/storage.go` (`GCSStorage.Upload`, bucket from env `HTTP_IMAGE_BUCKET`, 256KB chunks), metadata in MongoDB. Direct reference for resume upload-to-GCS if GCS is chosen.
- **Virus scan** — `apps/security/services/virus-scan-http-rest/` confirmed present: `POST /virus-scan-http-rest/scan`, multipart field `"file"`, 20MB max, returns `{fileClean, virusSignature}`.
- **Rate limiting** — `apps/profile/services/profile-http-rest/` contact throttling: per-member, 24h rolling window, Firestore collection `phone_number_throttling`, composite doc ID `{memberID}_{listingID}`, default limit 20/verified 50. Reusable pattern for application throttle (but keyed on memberId — see open question on anonymous applicants).
- Legacy bridge S3→GCS sync service exists

### Frontend UI Recreation (marketplace-frontend) — Inventoried
- **No Jobs apply/quick-apply/applications UI exists in marketplace-frontend today — all net new.** Only existing jobs UI: `JobsCategoryList.tsx` (homepage) and `FieldPayRange.tsx` (post-a-listing). Full screen inventory in Features.md Feature 7.
- **Legacy Apply Now is NOT React** — it's Zend PHP `.phtml` + jQuery in `m-ksl-jobs` (`apply/index-responsive.phtml`, `apply/thanks.phtml`, `apply/error.phtml`, `public/js/responsive/apply.js`). Rebuild from scratch using these as the spec.
- **Legacy Quick Apply + Applications ARE React** in `m-ksl-myaccount-v2`: `components/Profile/QuickApply.tsx` (~638 lines, route `/profile#quick-apply-info`), `components/Listing/Manage/Modals/JobApplicationsModal.tsx` (~186 lines), wired via `components/Listing/Manage/JobManage.tsx` (Applications menu item shown only when count > 0).
- **marketplace-frontend patterns to copy**: `listing/[id]/components/Contact/EmailModal.tsx` (modal + native form + Zod + server action — closest analog to Apply Now); `sell/post-a-listing/components/Photo/Photos.tsx` (react-dropzone + `addPhoto` server action — resume upload); `services/listing/email-seller.ts` (graphql-request + Zod mutation); `profile/` for the Quick Apply section. Stack: Next.js 16 App Router, Cascade-v2, Zod, no Formik/react-hook-form.
- **Parity catch**: legacy MyAccount Quick Apply UI allowed a **10MB** resume + a **5500-char text-paste** option; Apply Now enforced **4MB combined** + had text-paste too. Standardize on **4MB, file-upload only** (text paste is out of scope). Both legacy UIs allowed **BMP** (still an open question).

### Apply-Method Branching (Investigated)
- Two apply methods, distinction **already in the data model**: post-a-listing `jobsApplicationMethod` BUTTON_GROUP (`"ksl"` vs `"url"`, frontend-only UI state, not a server enum) → when `"url"`, requires `jobsApplicationUrl` (full http/https, `validateJobsApplicationUrl.ts`).
- `jobsApplicationUrl` is persisted end-to-end: backend `JobsApplicationURL *string` (`listing-http-rest/internal/types/listing.go:1317`), graphql `jobsApplicationUrl: String` on `ClassifiedListing`, already returned by listing-detail `fetchListing.ts`.
- **Branching rule = by presence** (copy legacy `getApplicationUrl()`): `jobsApplicationUrl` non-null → external apply, open new tab; null → on-site Apply Now form.
- **No Apply button exists in marketplace-frontend yet** — `ActionButtons` is only Favorite/Share/Print/Report; `jobsApplicationUrl` is fetched but unused. Phase 4 must add the job-detail Apply CTA.
- **Only two modes** (on-site form, external URL) — no separate "apply by email" mode. Legacy "Apply through KSL" forwarded to an employer email captured at posting.
- **GAP**: new listing model has no `jobsApplicationEmail`/employer-email field → Feature 4 employer notification has no identified email target for on-site listings (see Unanswered Questions).

### Existing Infrastructure in marketplace-graphql
- `JOB` is a recognized `ListingType` enum value
- `MyAccountJobListing` type exists with job-specific fields
- Favorites and report abuse work for jobs
- `emailListingOwner` NOT implemented for jobs
- No application or resume GraphQL types/operations exist yet
- Product pricing exists for jobs: ACTIVE_LISTING ($49), BOOST ($15), FEATURED_LISTING ($20), TOP ($25)

### Prior Phases Status
- Phase 3.1: Listing migration (active→classifieds, ID mapping in `jobListingMigrations`)
- Phase 3.2: Saved search migration
- Phase 3.3: Favorites migration
- Phase 3.4: URL redirects from jobs.ksl.com

### Quick Apply Update Flow (Investigated)
- **Option A (redirect)**: Minimal changes — add link on Apply Now form to MyAccount Quick Apply page. No GraphQL/backend changes.
- **Option B (checkbox)**: Moderate changes — add `updateQuickApply` boolean to mutation, conditional dual-write in backend, checkbox + modal on frontend.
- **Hybrid possible**: Ship Option A first, add Option B later as enhancement.
- Legacy frontend Quick Apply component: `m-ksl-myaccount-v2/components/Profile/QuickApply.tsx` (638 lines)
- Legacy route: `/profile#quick-apply-info`

### Application History Migration
- Confirmed **in scope** for Phase 4 (not deferred)

### Mobile App Scope (Resolved from Notion)
- Appetite: **~1 week of app work**. Endpoints the app needs updated:
  - Application submission (includes resume upload)
  - Loading Quick Apply info
  - Apply Now vs. Employer URL (apply-on-site vs. external application URL)
  - Update Quick Apply info
  - ~~Remove Quick Apply~~ (struck through in Notion — not in scope)

### Appetite & Status (from Notion)
- **Web estimate: 3 weeks**, **App: 1 week**
- Notion status: **PKG: Ready for Investment**
- Business value: protects ~$1.2M/yr revenue ($80K/mo self-serve + $20K/mo direct sales), ~400K monthly page views, ~1,200 active monthly listings, ~15K resumes
- Huddle checklist still open: Analytics, App plan, CX, Trufty (Trust & Safety), Platform, Legal not yet completed; Design + Marketing + Sales done

## Still Needs Research
- GCS bucket provisioning: exact bucket name + Platform setup for the new jobs application files bucket (storage destination itself is **decided: GCS**)
- Rate limiting threshold/strategy decision: a reusable per-user, 24h-rolling-window, Firestore-backed throttle pattern exists (`apps/profile/services/profile-http-rest/domain/contact_throttling_domain.go` + `store/firestore_phone-number-throttling_store.go`, collection `phone_number_throttling`, composite doc ID `{memberID}_{listingID}`). Open: per-user vs per-IP (applications can be anonymous, so memberId may be absent → IP-based likely needed for logged-out users), and threshold. Notion supporting data (Jan 1–mid Feb): 35,118 total apps, 21,000 from logged-in users, 4,134 unique logged-in users (~5 apps/user avg); ~15,000 resumes uploaded in 2025.

## Unanswered Questions

### For Team Decision
1. **BMP file support**: Should we support BMP uploads? Legacy allowed it but it's uncommon for resumes
2. ~~**Quick Apply update mechanism**~~: **DECIDED (2026-06-30)** — **checkbox on the Apply Now form** (no redirect to MyAccount).
3. ~~**Applications view format**~~: **DECIDED (2026-06-30)** — **keep the legacy modal**.

### For Trufty Team
4. ~~**Virus scanning service**~~: **DECIDED (2026-06-30)** — **keep using the existing `virus-scan-http-rest` ClamAV service**.

### For Platform/Architecture Team
5. ~~**File storage**: GCS or S3?~~ **DECIDED: GCS.** Resume/cover letter files go to a new GCS bucket (follow `image-http-rest` pattern). Migration re-uploads ~15K legacy files from S3 → GCS.
6. ~~**S3 bucket**~~: Moot — not staying on S3. Open follow-up: provision the new GCS bucket name with Platform.

### For Engineering
7. ~~**Email service**~~: Resolved — use pub/sub `Public_SendEmail` topic → Mailgun templates
8. ~~**Employer notification opt-out**~~: **DECIDED (2026-06-30)** — no opt-out; **always send the employer email**.
8b. ~~**Employer email source (GAP)**~~: **DECIDED (2026-06-25, refined 2026-06-30)** — resolution order: (1) **general dealer email if available**, else (2) the listing's contact `Email`/`EmailCanonical` field ([listing.go:1275-1276](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/types/listing.go#L1275)), else (3) **fallback to member-API lookup** (`/members/{memberId}`).
9. ~~**Application history migration scope**~~: Resolved — in scope for Phase 4
10. ~~**Mobile app work**~~: Resolved (Notion) — ~1wk: app-side application submission (w/ resume upload), load Quick Apply, apply-vs-employer-URL handling, update Quick Apply. "Remove Quick Apply" out.
11. ~~**Email attachments**~~: Resolved — `emailsv1.EmailMessage` supports attachments (`repeated Attachment` with filename/type/content). Employer emails attach files directly; no download-URL fallback needed. Validate end-to-end since no existing caller uses attachments.
12. ~~**Anonymous-application rate limiting**~~: **RESOLVED (2026-06-30)** — moot; **applicants must be logged-in members**. No anonymous applications, so the existing memberId-keyed throttle applies directly (no per-IP throttling needed).

### For Frontend / Design
13. ~~**Resume download links**~~: **DECIDED (2026-06-30)** — build an **authorized download-proxy API** on `application-http-rest` (auth caller → stream bytes from private GCS). **Signed URLs are NOT used for download** (PII). (The *upload* mechanism is separate and still open — see Q18.)
18. **Upload + virus-scan approach** (NEW, 2026-06-30) — **DEFER TO BUILD PLANNING**. Earlier we leaned toward signed-URL upload (Options A/B), but a through-API upload (Option C, the legacy model) is also on the table — picking among these (and the upload mechanism itself) is a **build-planning decision**, not needed today. Three candidate approaches, with caveats:
    - **Option A — Signed-URL upload → quarantine bucket → promote-on-clean**: client PUTs to a separate quarantine bucket via signed URL; backend scans post-upload; on clean, **copies/moves the object to the live bucket** and records final metadata; on infection, deletes.
      - ✅ Infected files never touch the live/serving bucket; bytes don't stream through the API.
      - ⚠️ Scan is **async to the PUT**; extra GCS copy of a ~4MB object (latency + cost); needs a **second bucket** + cleanup rules for abandoned objects; storage key/URL **changes on promotion** (write metadata only after the move).
    - **Option B — Signed-URL upload → scan-in-place → delete-on-infection (single bucket)**: client PUTs straight to the live bucket via signed URL; backend scans the object where it landed; deletes if infected.
      - ✅ Simpler than A — one bucket, no copy step, stable key; bytes don't stream through the API.
      - ⚠️ Scan is **async to the PUT**; a potentially-infected file **briefly lives in the live bucket** → needs a hard **`scanStatus`/clean gate** so nothing serves, attaches-to-email, or exposes the file until the scan passes; must handle a record referencing a file that later fails the scan.
    - **Option C — Upload through the API + synchronous in-request scan (mirrors legacy) — ⭐ LIKELY PREFERRED**: client uploads the file **to `application-http-rest` directly** (multipart); the request handler scans it inline (`virus-scan-http-rest`) **before** writing to GCS; rejects the request if infected, stores if clean. This is exactly what legacy does today (see "How legacy handles upload + virus scanning" above).
      - ✅ **Simplest end-to-end / least moving parts**: one bucket, no quarantine, no async gate, no `scanStatus` — the file is verified clean **before it ever lands in GCS** (closest to legacy, lowest behavioral risk).
      - ✅ **Best fit for the "Thank you for applying" confirmation modal**: because the scan + store + persist all complete **synchronously within the submit request**, the success modal is only shown once everything has actually succeeded. Options A/B are async — the file may not be verified/stored when the submit returns, so the confirmation modal would either show prematurely or have to wait on a pending/finalize step. **This is the main reason C is likely preferred.**
      - ⚠️ File bytes stream **through the API** (memory/throughput per request; service handles ~4MB uploads); abandons the signed-URL-upload direction; synchronous scan adds latency to the submit request (scan service caps at 20MB — fine for 4MB files).
    - Cross-cutting (A & B only): decide how the submit flow waits on the async result — block on the scan, or create the application in a **pending state** and finalize once clean. (Option C has no async gap — scan is in-request, so the success modal is safe to show on return.)
14. ~~**Apply page placement**~~: **DECIDED (2026-06-30)** — a **child or sibling page in marketplace-frontend** (not a modal). Routing options to be supplied by the user later.
15. ~~**File size parity**~~: **DECIDED (2026-06-30)** — **standardize on 4MB** (combined).
16. ~~**MyAccount-side repo**~~: **RESOLVED (2026-06-25)** — target repo is **[deseretdigital/m-ksl-myaccount-v2](https://github.com/deseretdigital/m-ksl-myaccount-v2)** (active, default branch `master`; **added to project.json**). The existing Quick Apply form + Employer Applications view there just need their **backend re-pointed** to the new `application-http-rest` (Q5) + resume-download links updated — NOT rebuilt in marketplace-frontend. Remaining: scope the integration changes with frontend engineers (effort/sequencing).
17. ~~**GCS upload placement**~~: **RESOLVED (2026-06-25)** — `application-http-rest` **embeds the GCS upload** (import the shared `GCSStorage` storage package directly); does NOT delegate to `image-http-rest`.

## Research Sources Consulted
- [Notion: Jobs to Classifieds - Phase 4](https://www.notion.so/3142ac5cb23581858037c31abf7d6800) — Project scope, screenshots, flow diagrams, business metrics
- [deseretdigital/marketplace-backend](https://github.com/deseretdigital/marketplace-backend) — Existing services: virus-scan, image upload, messages, listing, profile (rate limiting), legacy-bridge-s3-sync
- [deseretdigital/marketplace-graphql](https://github.com/deseretdigital/marketplace-graphql) — Existing job types, favorites, pricing, report abuse; no application types yet
- [deseretdigital/marketplace-frontend](https://github.com/deseretdigital/marketplace-frontend) — Next.js 16 App Router, Cascade-v2, Zod, graphql-request server actions, react-dropzone. No jobs apply UI exists; analog patterns: `EmailModal.tsx`, `Photos.tsx`, `email-seller.ts`, `profile/`
- Legacy `m-ksl-jobs` repo — ApplyController, Application entity, QuickApply entity, FileManager, VirusScanner, ApplicationEmailer, email templates
- [deseretdigital/m-ksl-myaccount-v2](https://github.com/deseretdigital/m-ksl-myaccount-v2) — **active MyAccount app (Phase 4 work target, added 2026-06-25, branch `master`)**. Hosts the existing Quick Apply form (`components/Profile/QuickApply.tsx`), Employer Applications view (`components/Listing/Manage/Modals/JobApplicationsModal.tsx`), and Manage menu (`components/Listing/Manage/JobManage.tsx`) — re-pointed to the new backend, not rebuilt.
- Shaping Projects 003-006 (Phases 3.1-3.4) — Prior phase scope and dependencies
- marketplace-backend pub/sub email pattern — `send_email.go` in listing-http-rest and listing-ps-price-drop services
- `ddm-protobuf` — `proto/emails/v1/email_message.proto`: confirmed `EmailMessage.Attachment` support (filename/type/content)

## Session Log
- **2026-06-16**: Synced marketplace-backend + marketplace-graphql to origin/main (both were on feature branches; switched to main, backend fast-forwarded, graphql already current). Researched open technical questions in-repo. **Resolved email attachments** — `emailsv1.EmailMessage` supports `repeated Attachment` (filename/type/content), so employer emails attach files directly (no download-URL fallback); flagged that no existing caller uses attachments so end-to-end validation + payload size for ~4MB files is needed. Confirmed virus-scan service, captured concrete file-upload-to-GCS pattern (`image-http-rest` + `GCSStorage`), and the reusable Firestore-backed per-member throttle pattern. Added open question on per-IP throttling for anonymous applicants. Re-fetched the Notion shaped package: **resolved mobile app scope** (~1wk: app-submission/resume-upload, load Quick Apply, apply-vs-employer-URL, update Quick Apply; "remove Quick Apply" struck), captured supporting-data volumes for throttle sizing, appetite (3wk web / 1wk app), status (PKG: Ready for Investment), and added **Favorite employers** to out-of-scope. Remaining team/architecture decisions unchanged (GCS vs S3, BMP support, Quick Apply update mechanism, employer opt-out, Trufty virus-scan sign-off).
- **2026-06-16 (decision)**: Storage **decided = GCS**. Resume/cover letter files → new GCS bucket following `image-http-rest`/`GCSStorage` pattern; migration re-uploads ~15K legacy files S3 (`mplace-jobs.ksl.com`) → GCS via `legacy-bridge-s3-sync`. Closed Q5/Q6; remaining storage follow-up is just provisioning the bucket name with Platform. Updated Features.md (F2, F6), Services.md (storage sections + service dependency).
- **2026-06-16 (frontend UI)**: Added `marketplace-frontend` to project.json. Inventoried all legacy Jobs UI and confirmed **none exists in marketplace-frontend — all net new**. Legacy Apply Now is PHP/jQuery (`m-ksl-jobs`, rebuild from scratch); Quick Apply + employer Applications are React (`m-ksl-myaccount-v2`, port). Added **Feature 7: Frontend UI Recreation** to Features.md (screen-by-screen legacy→new map with patterns to copy: `EmailModal.tsx`, `Photos.tsx`, `email-seller.ts`, port of `QuickApply.tsx`/`JobApplicationsModal.tsx`/`JobManage.tsx`) and a marketplace-frontend service section to Services.md. Flagged frontend-specific opens: download-link mechanism for resumes (signed GCS URL vs proxy), apply page vs modal placement, 4MB-vs-10MB size parity. Text-paste resume/cover-letter and favorite-employers explicitly NOT recreated.
- **2026-06-23**: Synced marketplace-frontend to origin/main (fast-forward 55036a987→38e0120f8; brought in `validateJobsApplicationUrl`, jobs pay-range filters/chips, jobs-srp-lifecycle churn). Investigated apply-method branching: confirmed `jobsApplicationMethod` (ksl/url) is frontend-only, `jobsApplicationUrl` is fully persisted (backend/graphql/detail-query), and branching is by URL presence (mirrors legacy `getApplicationUrl()`). Added "Apply-Method Branching" subsection to Feature 1 — key finding: **no Apply CTA exists in marketplace-frontend yet** (must be built). Surfaced a **blocking gap**: no employer-email field on the new listing model → Feature 4 has no notification target for on-site listings (added Q8b + flagged on Feature 4).
- **2026-06-25**: Synced all three repos to origin/main (backend + graphql already current; frontend fast-forwarded — unrelated listing-description churn). Did a focused walkthrough of the user's 10 core implementation questions and added the **"Phase 4 Walkthrough — 10 Questions Answered"** section at the top of this doc with concrete code locations. Key findings/decisions this session:
  - **Employer email source DECIDED** (Q8b/Q4): use listing `Email`/`EmailCanonical` ([listing.go:1275-1276](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/types/listing.go#L1275)); TODO confirm populated for job posts, fallback = member-API `/members/{memberId}` lookup (Cars email-seller pattern in [email-owner.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/email-owner.go) + [member.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/member/member.go#L246-L271)). Noted `emailListingOwner` is explicitly unimplemented for `ListingTypeJob`.
  - **MyAccount location clarified** (Q5/Q16): marketplace-frontend has **no authed MyAccount area** (`app/profile/` is only the public `[seller]` viewer; authed features link to `myaccount.ksl.com`). Per user: **Quick Apply form already exists in MyAccount** — Phase 4 just **re-points its backend**, no UI port. Same for the Employer Applications view (re-point backend + update resume download links). The MyAccount repo is not in project.json → flagged Q16 for frontend-engineer feedback before scoping/adding it.
  - **Quick Apply scope trimmed** (Q7/Q9): **no delete endpoints** for Quick Apply (out of scope). Removed `DELETE /quick-apply` + `DELETE /quick-apply/resume` and the `deleteQuickApplyProfile`/`deleteQuickApplyResume` GraphQL mutations.
  - **Quick-Apply-on-apply orchestration** (Q9): the **GraphQL `submitJobApplication` resolver** (not the backend service) handles the opt-in Quick Apply update via **two backend calls** — `PUT /quick-apply` (failures logged, non-blocking) then `POST /application`. Replaces the earlier "Option A vs B" framing.
  - **Resume serving** (Q3): GCS is private-by-default; resumes are PII → do NOT use the public `image.ksldigital.com` CDN. Use a short-lived signed URL ([storage.go `GetProcessingSignedURL`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/services/media/shared-image-packages/storage/storage.go#L106-L123)) or (recommended) an authorized download-proxy endpoint mirroring legacy [`/apply/download-application`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site/application/controllers/ApplyController.php#L414-L471). Added Q17 (embed vs delegate GCS upload).
- **2026-06-30 (upload options + legacy research)**: Researched how **legacy** handles upload + virus scanning (added to "Resume Upload & Virus Scanning") — confirmed it's **all inline in one request**: multipart `POST /apply/save` → validate ext/size → **synchronous `clamdscan` on the PHP temp file** → store to S3 → delete temp; no quarantine, no async; legacy also allowed `bmp`, 4MB combined. Added **Option C** to Q18 (upload through the API + synchronous in-request scan = the legacy model) and **flagged it as likely preferred** — simplest, and its synchronous scan/store/persist fits the **"Thank you for applying" confirmation modal** (Options A/B are async, so the modal would show prematurely or need a pending/finalize step). Reframed Q18 as "Upload + virus-scan approach" (3 options) and **softened the earlier hard "signed-URL upload DECIDED"** — the upload mechanism is now a **build-planning decision** (download-proxy decision unchanged).
- **2026-06-30 (file upload/download mechanisms)**: User decided file-transfer mechanisms. **Download (Q13)** = build an **authorized download-proxy API** on `application-http-rest` (auth caller → stream from private GCS); **signed URLs are explicitly NOT used for download** (PII). **Upload** = use **short-lived signed URLs** — client PUTs resume/cover-letter directly to GCS, then submits the application referencing the storage key (no multipart-through-backend). Updated Walkthrough Q2/Q3 + Q13. **New open item Q18**: virus-scan now runs post-upload (backend pulls the GCS object → `virus-scan-http-rest` → delete/quarantine on infection); exact sequencing (scan-in-place vs. quarantine-bucket-then-promote) needs confirmation.
- **2026-06-30 (open questions resolved)**: User answered the remaining open questions. **Q2** = checkbox on the Apply Now form (no MyAccount redirect). **Q3** = keep the legacy modal for the Applications view. **Q4** = keep the existing `virus-scan-http-rest` ClamAV service. **Q8** = no opt-out; always send the employer email. **Q12** = moot — applicants must be logged-in members (no anonymous apply), so the memberId-keyed throttle applies directly. **Q14** = apply UI is a child or sibling page in marketplace-frontend (not a modal); routing options to come from user later. **Q15** = standardize on 4MB combined. **Q8b refined** = employer email resolution order: general dealer email → listing `Email`/`EmailCanonical` → member-API lookup. Still open: **Q1** (BMP support) and **Q13** (resume download link mechanism — signed GCS URL vs download proxy).
- **2026-06-25 (Q16/Q17 resolved + repo added)**: User decided **Q17 = embed** (`application-http-rest` imports the shared `GCSStorage` package directly, no delegation to `image-http-rest`) and confirmed **Q16 target repo = [deseretdigital/m-ksl-myaccount-v2](https://github.com/deseretdigital/m-ksl-myaccount-v2)**. Added that repo to `project.json` and synced it (active clone at `Research Repos/m-ksl-myaccount-v2`, branch `master`, clean + up to date; HEAD `d92ac8aab`). Verified the three jobs components exist there at the same paths as the Legacy copy and re-pointed all doc links from `Legacy/m-ksl-myaccount-v2` → the active `m-ksl-myaccount-v2` clone. m-ksl-myaccount-v2 is the **active** MyAccount app (a work target — re-point backend), not a legacy reference.
