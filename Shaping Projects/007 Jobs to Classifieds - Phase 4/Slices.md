# Jobs to Classifieds - Phase 4 — Slices

Vertical slices of work, in Shape Up terms: each slice is one **thing** that cuts top-to-bottom (frontend + GraphQL + backend, as needed) and is **independently demoable and shippable**, ideally behind a flag. Slices are ordered so the riskiest integration and the highest-value path come first, and so each later slice has its dependencies already in place.

> **Precondition (already done before this project):** the Apply CTA on the job listing detail page and its external-URL branching (open `jobsApplicationUrl` in a new tab vs. route to the on-site flow) are already complete. These slices assume the on-site Apply entry point already exists and routes to the form built in Slice 1.

> **Auth precondition:** the Apply Now form and application submission are **logged-in only**. Unauthenticated users are routed to sign-in before reaching the form. `memberId` is therefore always present on a submission, which removes anonymous/per-IP concerns from rate limiting (Slice 4).

## Slicing philosophy applied here

- **Slice 1 is the walking skeleton + the scariest integration** — the on-site Apply Now happy path (multipart upload → virus scan → GCS → Mongo → GraphQL → form). This is where the unknowns live (first GCS upload in this service, first pub/sub attachment caller downstream, private-bucket serving). Build it first so risk is retired early.
- **Each slice ships value on its own.** The core submission (Slice 1) is shippable with no emails. Emails, Quick Apply, and the employer view layer on without rework.
- **The authorized resume-download mechanism** (private GCS) is a shared dependency for the Quick Apply saved-resume display *and* the Employer Applications view. It is built once in Slice 5 and reused.

## Dependency graph (high level)

```
Slice 1 (Apply Now core spine)    ── foundation for everything below
   ├── Slice 2 (Employer email)
   ├── Slice 3 (Applicant confirmation email)
   ├── Slice 4 (Rate limiting)
   └── Slice 5 (Authorized resume download)  ── shared by 6 + 7
Slice 6 (Quick Apply profile: backend + MyAccount re-point)  ── needs 5
   ├── Slice 7 (Apply Now pre-fill / load Quick Apply)   ── needs 1 + 6
   └── Slice 8 (Opt-in update Quick Apply on submit)     ── needs 1 + 6
Slice 9 (Employer Applications view re-point)            ── needs 1 + 5
Slice 10 (Legacy data migration)  ── needs 1 + 6 schemas + GCS bucket
Slice 11 (Mobile app integration) ── needs 1 + 6 (+ external repo, separate team)
```

---

## Slice 1 — Apply Now core submission (the spine)

**Goal:** A **logged-in** user fills the Apply Now form, uploads a resume (required) + optional cover letter, submits, and the application is persisted with files in GCS. No emails, no Quick Apply, no employer view yet. **This is the riskiest, highest-value slice — build first.**

**Repos:** marketplace-backend, marketplace-graphql, marketplace-frontend.

**Backend requirements (`apps/jobs/services/application-http-rest/`, new service)**
- Scaffold the new REST service following an existing `*-http-rest` service layout.
- `POST /application` — multipart (JSON fields + `resume` file + optional `coverLetter` file). Requires an authenticated member.
- For each uploaded file: call `virus-scan-http-rest` (`POST /scan`, field `"file"`, 20MB max, returns `{fileClean, virusSignature}`); reject the whole submission if any file is unclean.
- Stream clean files to the new **GCS bucket** by **embedding** the shared `GCSStorage.Upload` package (Q17 decided — do *not* delegate to `image-http-rest`). Pattern: [storage.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/services/media/shared-image-packages/storage/storage.go#L47-L66), bucket from env.
- Filename convention (copy legacy): `YYYY-MM-DD_FirstName_LastName_[resume|coverletter].extension`.
- Persist the `Application` document to MongoDB (schema in [Services.md](Services.md) §1): applicant fields, `jobId`, `memberId`, education/experience enums, `resumeFile`/`coverLetterFile` metadata `{url, storageKey, name, extension, sizeInBytes}`, `submissionTime`, `source`, `userAgent`.
- `GET /application/{id}` — single application (needed for downstream + testing).
- Server-side validation parity: allowed types (doc, pdf, docx, jpg, jpeg, png), 4MB/file, education + experience enum values.

**GraphQL requirements (marketplace-graphql)**
- Types `JobApplication`, `ApplicationFile` ([Services.md](Services.md) §3).
- Mutation `submitJobApplication(input: SubmitJobApplicationInput!): JobApplication!` — for this slice, just proxies `POST /application` (the `updateQuickApply` dual-call is Slice 8). Requires an authenticated session.
- New service client to call `application-http-rest`.

**Frontend requirements (marketplace-frontend)**
- **Gate the apply flow behind auth** — route unauthenticated users to sign-in before the form renders (`@monorepo/ksl-session`).
- Apply Now form: first/last name, email, zip, education dropdown, experience dropdown, resume upload (required), cover letter upload (optional). Native `<form>` + `FormData` + **Zod**; copy [Contact/EmailModal.tsx](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/%5Bid%5D/components/Contact/EmailModal.tsx).
- Upload control: **react-dropzone** + server-action pattern from [Photos.tsx](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/sell/post-a-listing/components/Photo/Photos.tsx). Surface error states for wrong type and too-large. For a rejected (unclean) file, show a **generic upload-failed message** — do **not** tell the user a virus was detected. *(TODO: confirm with Trufty what, if anything, we should surface to the user when a file is rejected by the scanner.)*
- Validators parity (legacy): email regex, name `^[A-Za-z \-']+$`, zip `^\d{5}(-\d{4})?$`.
- Server action / graphql op under `apps/ksl-marketplace/services/jobs/`, copying [email-seller.ts](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/services/listing/email-seller.ts).
- Wire the form to the existing on-site Apply entry point (CTA already built — see precondition). Decide route vs modal (TODO #6).
- **Build equivalent JSX pages in marketplace-frontend** for the legacy success and error views:
  - Success page — equivalent of legacy [thanks.phtml](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site/application/views/scripts/apply/thanks.phtml) ("Thank you for applying…" + job/company summary).
  - Error page — equivalent of legacy [error.phtml](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site/application/views/scripts/apply/error.phtml) (validation/processing error + back link).

**Done when:** A logged-in user can apply to an on-site job end-to-end; the application + both files land in Mongo/GCS; an unclean file is rejected and the user sees a generic failure (not a virus message); unauthenticated users are sent to sign-in.

**Risks / must-validate this slice:** GCS bucket must be provisioned (Platform); confirm the embedded `GCSStorage` package works from a non-media service; confirm private-by-default bucket. Trufty sign-off on reusing `virus-scan-http-rest` and on user-facing rejection messaging (TODO #3).

---

## Slice 2 — Employer notification email

**Goal:** When an on-site application succeeds, the employer receives an email with applicant details and the resume (+ cover letter) attached.

**Repos:** marketplace-backend (+ Mailgun template config).

**Backend requirements**
- On successful `POST /application` for an on-site (`ksl`) listing, publish an `emailsv1.EmailMessage` to the `Public_SendEmail` pub/sub topic. Pattern: [send_email.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/pubsub/send_email.go).
- **Resolve the employer email**: use the listing's `Email`/`EmailCanonical` ([listing.go:1275-1276](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/types/listing.go#L1275)). **TODO before building (#9):** confirm these are populated for job posts; fallback = member-API `/members/{memberId}` lookup.
- Attach files via `EmailMessage.Attachments` (`filename`, `type`, base64 `content`). **First caller in marketplace-backend to use attachments** — validate end-to-end delivery + payload size for ~4MB files.
- Subject: `Resume from [Full Name] for [Job Title]`. New Mailgun template `jobs-application-employer-notification` with applicant name, email, zip, education, experience.
- External-URL listings do **not** trigger this (they apply off-site).

**Done when:** Submitting an on-site application delivers a templated email with working resume/cover-letter attachments to the employer's address.

---

## Slice 3 — Applicant confirmation email

**Goal:** After a successful application, the applicant gets a confirmation email.

**Repos:** marketplace-backend (+ Mailgun template config).

**Backend requirements**
- On successful `POST /application`, publish a second `emailsv1.EmailMessage` to the applicant's email. Template-only (no attachments → simpler than Slice 2).
- New Mailgun template `jobs-application-confirmation` with job title, company name, location (city/state), posted date.
- Subject: `Your application for [Job Title] is on its way!`. Spec: [senderConfirmation.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/api/template/emailTemplates/application/senderConfirmation.php).

**Done when:** Applicant receives the confirmation email after submitting.

---

## Slice 4 — Application rate limiting

**Goal:** Application submissions are throttled to deter spam (new vs legacy).

**Repos:** marketplace-backend.

**Backend requirements**
- Throttle `POST /application`. Because apply is logged-in only, throttle **per `memberId`** — reuse the per-member, 24h-rolling-window, Firestore-backed pattern in `apps/profile/services/profile-http-rest/` (`contact_throttling_domain.go`, collection `phone_number_throttling`). No anonymous/per-IP path needed.
- Threshold TBD (#8) — size against Notion volumes (~5 apps/user avg).

**Done when:** A member exceeding the limit gets a clear throttle error.

---

## Slice 5 — Authorized resume download (private GCS)

**Goal:** A shared, auth-enforced mechanism to serve resume/cover-letter files from the private GCS bucket. Resumes are **PII** — must not go through the public CDN. Reused by Slices 6 (saved-resume display) and 9 (employer view).

**Repos:** marketplace-backend (+ graphql if signed-URL field chosen).

**Backend requirements**
- Build **one** of (TODO #5 — leaning authorized proxy):
  - `GET /application/{id}/download?type=resume|coverLetter` proxy endpoint that authorizes the requester (employer owns the listing, or owner of the Quick Apply profile) then streams from GCS — mirrors legacy [`/apply/download-application`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site/application/controllers/ApplyController.php#L414-L471); **or**
  - short-lived signed GCS URL ([GetProcessingSignedURL](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/services/media/shared-image-packages/storage/storage.go#L106-L123)) returned via a GraphQL field.
- Enforce authorization on every download (PII).

**Done when:** An authorized user can download a stored resume; an unauthorized request is rejected; no public URL exposes the file.

---

## Slice 6 — Quick Apply profile (backend + MyAccount re-point)

**Goal:** The existing MyAccount Quick Apply form reads/writes the new backend. A logged-in user can view and upsert their Quick Apply profile (name, email, zip, education, experience, resume — no cover letter).

**Repos:** marketplace-backend, marketplace-graphql, m-ksl-myaccount-v2. **Depends on Slice 5 for the saved-resume download link.**

**Backend requirements**
- `GET /quick-apply` — authed member's profile.
- `PUT /quick-apply` — upsert (one profile per `memberId`). Resume upload goes through the same virus-scan → GCS flow as Slice 1. **No delete endpoints** (out of scope).
- Persist `QuickApplyProfile` to MongoDB ([Services.md](Services.md) §1).

**GraphQL requirements**
- Type `QuickApplyProfile`; query `getQuickApplyProfile`; mutation `saveQuickApplyProfile`.

**MyAccount requirements (m-ksl-myaccount-v2, branch `master`)**
- Re-point [QuickApply.tsx](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Profile/QuickApply.tsx) at the new endpoints. **No UI rebuild.**
- Standardize on **4MB** upload (legacy MyAccount allowed 10MB — TODO #7).
- Update the saved-resume download link to the Slice 5 mechanism.

**Done when:** A user can save and re-load their Quick Apply profile in MyAccount, hitting the new backend, with a working saved-resume download.

---

## Slice 7 — Apply Now pre-fill (load Quick Apply)

**Goal:** A logged-in user opening Apply Now sees their saved Quick Apply info pre-filled and their saved resume attached. **Read-only consumption of the profile — no writing back.**

**Repos:** marketplace-frontend (consumes the `getQuickApplyProfile` query from Slice 6). **Depends on Slices 1, 6 (and 5 for the saved-resume display/download).**

**Frontend requirements**
- On open, fetch `getQuickApplyProfile` and pre-fill name/email/zip/education/experience.
- Attach the saved resume; allow remove ("X") → **"Use From Quick Apply"** re-attach (legacy [QuickApply.tsx:366-391](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Profile/QuickApply.tsx#L366-L391)).
- If the user has no Quick Apply profile, render the blank form (no error).

**Done when:** A logged-in user with a saved profile sees the form pre-populated and can submit (via the Slice 1 path) without re-entering data; a user without a profile sees a normal blank form.

---

## Slice 8 — Opt-in update Quick Apply on submit

**Goal:** On the Apply Now form, the user can opt in to also save/update their Quick Apply profile when they submit an application.

**Repos:** marketplace-frontend, marketplace-graphql. **Depends on Slices 1, 6.**

**Frontend requirements**
- Opt-in control ("save/update my Quick Apply info") that sets `updateQuickApply: true` on the `submitJobApplication` mutation (+ confirmation modal if the checkbox approach is chosen — TODO #2).

**GraphQL requirements**
- Add `updateQuickApply: Boolean` to `SubmitJobApplicationInput`. When true, the **resolver makes two backend calls**: `PUT /quick-apply` (**failures logged, non-blocking**) then `POST /application`. Orchestration lives in the resolver, not the backend service — the REST endpoints stay single-purpose.

**Done when:** Submitting with the opt-in checked updates the member's Quick Apply profile; the application **never fails** if the profile write fails (failure is logged only).

---

## Slice 9 — Employer Applications view re-point

**Goal:** Employers see their applicants in MyAccount, backed by the new service, with working resume/cover-letter downloads.

**Repos:** marketplace-backend, marketplace-graphql, m-ksl-myaccount-v2. **Depends on Slices 1 + 5.**

**Backend requirements**
- `GET /application/listing/{listingId}` — applications for a listing (employer view).

**GraphQL requirements**
- Queries `getApplicationsForListing(listingId)` and `getMyApplications`.

**MyAccount requirements (m-ksl-myaccount-v2)**
- Re-point [JobApplicationsModal.tsx](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Listing/Manage/Modals/JobApplicationsModal.tsx) at the new endpoint; replace legacy `/apply/download-application` links with the Slice 5 mechanism.
- Re-point the application-count source in [JobManage.tsx](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/components/Listing/Manage/JobManage.tsx) (Applications menu shown only when count > 0).
- Applicant list shows: name, date, email, experience, zip, education + download links.

**Done when:** An employer opens Listing → Manage → Applications and sees their applicants with working downloads, all from the new backend.

**NTH (not in core appetite):** standalone page instead of modal (TODO #4); remove-applicant action (CX request).

---

## Slice 10 — Legacy data migration

**Goal:** Existing Quick Apply profiles and application history move to the new collections, with resume files copied S3 → GCS and references rewritten.

**Repos:** marketplace-backend (migration tooling) / `legacy-bridge-s3-sync`. **Depends on Slices 1 + 6 schemas + provisioned GCS bucket.**

**Requirements**
- Migrate `jobsQuickApply` → new collection; `jobsApplication` → new collection.
- Copy ~15K resume/cover-letter files from S3 `mplace-jobs.ksl.com` → GCS; rewrite file references to new GCS keys/URLs. `legacy-bridge-s3-sync` can assist.
- Map legacy `jobId` → new `ClassifiedListing` ID via Phase 3.1's `jobListingMigrations` collection.

**Done when:** Migrated profiles load in MyAccount and migrated applications appear in the employer view with downloadable files.

---

## Slice 11 — Mobile app integration (separate team, ~1 week)

**Goal:** The native app uses the new endpoints. **Depends on Slices 1 + 6.** App repo is **not** in this project's `project.json` — owned by the app team.

**Requirements (per Notion)**
- Application submission (incl. resume upload).
- Load Quick Apply info; update Quick Apply info.
- Apply-on-site vs external-URL handling.
- *Not* in scope: remove Quick Apply.

---

## TODOs to answer during shaping

These must be resolved **before/while shaping is finalized** — each blocks a slice. Capture answers back into Features.md / Services.md / planning-state.md as they're decided.

- [ ] **#2 — Quick Apply update mechanism (Slice 8):** opt-in checkbox on the Apply Now form vs. redirect to MyAccount? Determines whether Slice 8 needs a confirmation modal.
- [ ] **#3 — Trufty sign-off (Slice 1):** OK to reuse `virus-scan-http-rest` (ClamAV)? And what, if anything, do we tell the user when a file is rejected by the scanner?
- [ ] **#4 — Employer Applications view format (Slice 9):** modal (legacy parity) vs. standalone MyAccount page (NTH)?
- [ ] **#5 — Resume download mechanism (Slice 5):** authorized download-proxy endpoint vs. short-lived signed GCS URL? (Leaning proxy — PII + private bucket.)
- [ ] **#6 — Apply page placement (Slice 1):** dedicated apply route (legacy was a full page) vs. modal on the listing detail page (`EmailModal` pattern)?
- [ ] **#7 — File-size parity (Slices 1/6):** standardize on 4MB everywhere? (Legacy MyAccount Quick Apply allowed 10MB.)
- [ ] **#8 — Rate-limit threshold (Slice 4):** per-member cap over the 24h window.
- [ ] **#9 — Employer email source (Slice 2):** confirm listing `Email`/`EmailCanonical` are populated for job posts; if not, fall back to member-API `/members/{memberId}` lookup.
- [ ] **#10 — Employer email opt-out (Slice 2):** can employers disable application emails, or always-on?
- [ ] **#11 — GCS bucket provisioning (Slices 1/10):** finalize the dedicated jobs-application bucket name with Platform.

## Estimates

Engineering effort per slice in **work weeks** (5-day weeks; one engineer on that layer). Web/backend slices 1–10 run with backend + frontend in parallel, so calendar time is well under the summed effort. App work (slice 11) runs in parallel with its own team.

| Slice | Repos | Estimate (work weeks) |
|-------|-------|-----------------------|
| 1 — Apply Now core submission (spine) | backend, graphql, frontend | 1–1.4 |
| 2 — Employer notification email | backend | 0.4–0.6 |
| 3 — Applicant confirmation email | backend | 0.2 |
| 4 — Application rate limiting | backend | 0.2–0.4 |
| 5 — Authorized resume download | backend (+graphql) | 0.4–0.6 |
| 6 — Quick Apply profile + MyAccount re-point | backend, graphql, myaccount | 0.6–0.8 |
| 7 — Apply Now pre-fill (load Quick Apply) | frontend | 0.2–0.4 |
| 8 — Opt-in update Quick Apply on submit | frontend, graphql | 0.2–0.4 |
| 9 — Employer Applications view re-point | backend, graphql, myaccount | 0.4–0.6 |
| 10 — Legacy data migration | backend / legacy-bridge | 0.6–1 |
| **Web/backend subtotal (1–10)** | | **~4.2–6.4 weeks** |
| 11 — Mobile app integration | app team (parallel) | ~1 |

**Overall estimate:** ~**4.2–6.4 engineer-weeks** of web/backend effort (slices 1–10). With backend + frontend engineers working in parallel down the dependency order, that lands at roughly **3 calendar weeks of web work** — consistent with the shaped 3-week web appetite — plus **~1 week of app work** (slice 11) by the app team in parallel. **Total appetite: ~3 weeks web + ~1 week app.**

## Appetite reference (from Notion)

- Web: ~3 weeks · App: ~1 week · Status: PKG: Ready for Investment.
- Slice 1 is the critical path / highest risk; 2–9 layer on; 10–11 trail (migration + app team).
