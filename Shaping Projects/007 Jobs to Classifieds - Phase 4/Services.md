# Jobs to Classifieds - Phase 4 — Services

## New Services

### 1. `application-http-rest` (marketplace-backend)
**Location**: `apps/jobs/services/application-http-rest/`

REST API service for job applications and Quick Apply profiles.

#### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/application/upload-url` | _(Options A/B only)_ Request a short-lived **signed GCS upload URL** (client then PUTs the file directly to GCS) |
| POST | `/application` | Submit job application. Shape depends on upload approach (Q18): **Option C** = multipart (JSON fields + resume/cover-letter files, scanned in-request); **Options A/B** = JSON fields + storage keys of already-uploaded files |
| GET | `/application/{id}` | Get application details |
| GET | `/application/{id}/download?type=resume\|coverLetter` | **Authorized download-proxy** — auth caller, stream file bytes from private GCS |
| GET | `/application/listing/{listingId}` | Get applications for a listing (employer view) |
| GET | `/quick-apply` | Get Quick Apply profile for authenticated user |
| PUT | `/quick-apply` | Create/update Quick Apply profile (upsert) |

> **No Quick Apply delete endpoints** — removing/deleting a Quick Apply profile or its resume is out of scope.
>
> **File transfer:**
> - **Download — DECIDED (2026-06-30)** = **authorized download-proxy** endpoint (`GET /application/{id}/download`). GCS is private and resumes are PII, so we **do NOT** hand out signed download URLs — the API authorizes the caller and streams the bytes.
> - **Upload + virus scan — DEFER TO BUILD PLANNING (Q18); leaning Option C.** Three candidate approaches: **(A/B) signed-URL upload** (`POST /application/upload-url`, scan post-upload) vs. **(C) through-API multipart + synchronous in-request scan** (the legacy model — scan before store). **Option C is likely preferred** (simplest; its synchronous flow fits the "Thank you for applying" confirmation modal — async A/B would confirm before the file is verified/stored). Full comparison + caveats in planning-state Q18.

#### Data Models

**Application** (MongoDB):
```
{
  _id: ObjectId,
  applicantFirstName: string,
  applicantLastName: string,
  applicantEmail: string,
  applicantZip: int,
  jobId: string (ClassifiedListing ID),
  memberId: int (optional),
  educationLevel: string (enum),
  experienceLevel: string (enum),
  resumeFile: {
    url: string,
    storageKey: string,
    name: string,
    extension: string,
    sizeInBytes: int
  },
  coverLetterFile: { ... } (optional, same structure),
  submissionTime: datetime,
  source: string,
  userAgent: string
}
```

**QuickApplyProfile** (MongoDB):
```
{
  memberId: int (primary key),
  firstname: string,
  lastname: string,
  email: string,
  zip: string,
  educationLevel: string (enum),
  experienceLevel: string (enum),
  resume: {
    url: string,
    storageKey: string,
    name: string,
    extension: string,
    sizeInBytes: int
  }
}
```

#### Internal Dependencies
- `virus-scan-http-rest` — scan files and reject/delete infected ones. Scan timing depends on the upload approach (Q18): **in-request before store** (Option C, legacy model) or **post-upload** (signed-URL Options A/B)
- File storage: **GCS bucket** (jobs application files) — authorized-proxy download (decided); upload approach TBD (Q18); see Features.md Feature 2
- Email service — send employer notifications and applicant confirmations

---

## Updated Services

### 2. `virus-scan-http-rest` (marketplace-backend)
**Location**: `apps/security/services/virus-scan-http-rest/`

**Status**: Already exists. **DECIDED (2026-06-30)** — keep using this service as-is; no changes expected (see Features.md Feature 2).

**Current capabilities**:
- `POST /virus-scan-http-rest/scan` — scan uploaded file
- ClamAV-based, 20MB max upload
- Returns `{fileClean: bool, virusSignature: string}`

---

### 3. marketplace-graphql

New GraphQL schema types, queries, and mutations to expose job application functionality to the frontend.

#### New Schema Types
```graphql
type JobApplication {
  id: ID!
  applicantFirstName: String!
  applicantLastName: String!
  applicantEmail: String!
  applicantZip: Int!
  educationLevel: String!
  experienceLevel: String!
  resumeFile: ApplicationFile
  coverLetterFile: ApplicationFile
  submissionTime: String!
  jobId: String!
}

type ApplicationFile {
  url: String!
  name: String!
  extension: String!
  sizeInBytes: Int!
}

type QuickApplyProfile {
  memberId: Int!
  firstname: String!
  lastname: String!
  email: String!
  zip: String!
  educationLevel: String!
  experienceLevel: String!
  resume: ApplicationFile
}
```

#### New Mutations
```graphql
# input includes updateQuickApply: Boolean — see dual-call orchestration below
submitJobApplication(input: SubmitJobApplicationInput!): JobApplication!
saveQuickApplyProfile(input: SaveQuickApplyProfileInput!): QuickApplyProfile!
```

> **No delete mutations for Quick Apply** (out of scope).
>
> **Quick-Apply-on-apply is orchestrated here, in the GraphQL resolver — not in the backend service.** When `submitJobApplication` is called with `updateQuickApply: true`, the resolver makes **two backend calls**: (1) `PUT /quick-apply` to upsert the profile (**failures logged, non-blocking** — never fail the application because of this), then (2) `POST /application` to submit. This keeps the REST endpoints single-purpose.

#### New Queries
```graphql
getQuickApplyProfile: QuickApplyProfile
getApplicationsForListing(listingId: String!): [JobApplication!]!
getMyApplications: [JobApplication!]!
```

#### Resolver Service Client
- New service client to call `application-http-rest` endpoints
- Follows existing patterns (e.g., `services/kslapi/kslapi.go` for legacy, or direct REST client for new backend services)

---

### 4. marketplace-frontend

**Only the Apply Now flow is built here** (net-new — none exists today). The Quick Apply form and Employer Applications view live in the **MyAccount app** and are re-pointed there, NOT rebuilt here (see §5 + Features.md Feature 7). marketplace-frontend has no authenticated MyAccount area — `app/profile/` is only the public read-only `[seller]` viewer.

| Area | New code | Pattern to copy |
|------|----------|-----------------|
| Apply CTA on job detail | Add to `app/listing/[id]/components/ActionButtons.tsx` (branch on `jobsApplicationUrl` presence) | existing action-button components |
| Apply Now form + upload + pre-fill + confirmation/error | **Dedicated child or sibling page** under `app/listing/[id]/` (DECIDED 2026-06-30 — page, not a modal; routing options TBD from user) | `listing/[id]/components/Contact/EmailModal.tsx`, `sell/post-a-listing/components/Photo/Photos.tsx` (+ `app/sell/[[...id]]/actions/addPhoto.ts`) |
| Opt-in "save/update my Quick Apply info" | Control on Apply Now form that sets `updateQuickApply` on the mutation | — |
| GraphQL operations | Server actions under `apps/ksl-marketplace/services/jobs/` calling new graphql ops (§3) | `services/listing/email-seller.ts` (graphql-request + Zod) |

**Stack**: Next.js 16 App Router, `@monorepo/cascade-v2`, native form + `FormData` + Zod, react-dropzone for uploads, `@monorepo/ksl-session` auth, `@monorepo/analytics` DataLayer events.

**Estimate (Notion)**: ~3 weeks web.

---

### 5. MyAccount app — [deseretdigital/m-ksl-myaccount-v2](https://github.com/deseretdigital/m-ksl-myaccount-v2) (in project.json; branch `master`)

The Quick Apply form and Employer Applications view **already exist** here as React components. Phase 4 work = **re-point their backend integration**, not a UI rebuild:

| Existing component | Change |
|--------------------|--------|
| `components/Profile/QuickApply.tsx` | Point at new `application-http-rest` Quick Apply endpoints (GET/PUT `/quick-apply`); update saved-resume download link to the new authorized download-proxy endpoint |
| `components/Listing/Manage/Modals/JobApplicationsModal.tsx` | Point at new applications endpoint; replace legacy `/apply/download-application` links with the new **authorized download-proxy** endpoint (`GET /application/{id}/download`) — no signed URLs |
| `components/Listing/Manage/JobManage.tsx` | Point the application-count source at the new backend (Applications menu entry shown when count > 0) |

**Backend integration in `application-http-rest` embeds the GCS upload directly** (shared `GCSStorage` package), per Q17. Remaining: scope the integration effort/sequencing with frontend engineers.

---

## Infrastructure Considerations

### Email Service — Pub/Sub to Mailgun

The new system uses a **pub/sub → Mailgun** pattern for sending emails. The `application-http-rest` service will publish email messages to the `Public_SendEmail` pub/sub topic. A downstream email service consumes these messages and sends via Mailgun.

**Pub/Sub Topic**: `Public_SendEmail`
**Environment Variable**: `SEND_EMAIL_TOPIC=Public_SendEmail` (or `SEND_EMAIL_PUBSUB_TOPIC`)

**Message Format**: Protobuf (`emailsv1.EmailMessage` from `ddm-protobuf`):
```go
import emailsv1 "github.com/deseretdigital/ddm-protobuf/go/gen/emails/v1"

msg := &emailsv1.EmailMessage{
    Recipients:        []*emailsv1.EmailMessage_Recipient{{Email: recipientEmail}},
    Subject:           "Resume from John Doe for Software Engineer",
    Template:          "jobs-application-employer-notification",  // Mailgun template name
    TemplateVariables: `{"applicantName":"...","jobTitle":"..."}`, // JSON string
    FromEmail:         "noreply@ksl.com",
    FromName:          "KSL Jobs",
    Tags:              []string{"jobs-application-employer-notification"},
    DeliveryTime:      time.Now().UTC().Format(time.RFC3339),
}
data, _ := proto.Marshal(msg)
topic.Publish(ctx, &pubsub.Message{Data: data})
```

**Existing examples to follow**:
- [send_email.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/pubsub/send_email.go) — listing thank-you email (template: `"classifieds thank you"`)
- [send_email.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-ps-price-drop/internal/client/send_email.go) — price drop notifications (template: `"classifieds price drop notification"`)
- [publisher.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/pubsub/publisher.go) — publisher initialization pattern

**Two new Mailgun templates needed**:
1. **Employer notification** (e.g., `"jobs-application-employer-notification"`): applicant details + resume/cover letter attachments
2. **Applicant confirmation** (e.g., `"jobs-application-confirmation"`): job title, company, location, posted date

**Attachments — RESOLVED (supported)**: The `emailsv1.EmailMessage` protobuf **does support file attachments**. It has a `repeated Attachment attachments = 7` field, where each `Attachment` is:
```proto
message Attachment {
  string filename = 1; // Filename of attachment
  string type = 2;     // MIME type of the file
  string content = 3;  // Contents of the file (base64-encoded)
}
```
Source: `ddm-protobuf/proto/emails/v1/email_message.proto` (lines 30-34); Go-generated type at `github.com/deseretdigital/ddm-protobuf/go/gen/emails/v1`.

- Employer notification emails can attach the resume (and optional cover letter) directly by populating `Attachments` — matches legacy behavior of attaching actual files.
- **No existing caller sets `Attachments`** — the listing thank-you and price-drop emails only use templates + variables. This will be the **first** pub/sub email caller in marketplace-backend to use attachments, so expect to validate end-to-end (does the downstream consumer/Mailgun handle the `content` payload as expected, and is there a practical size limit on the protobuf message / pub/sub payload for ~4MB files?).
- The application service will need to read the clean file bytes (from storage or the in-memory upload), base64-encode into `Attachment.content`, set `filename` and MIME `type`, then publish.

### File Storage — DECIDED: GCS
- Resume/cover letter files go to a **GCS bucket** (new dedicated bucket for jobs application files; name TBD with Platform).
- Follow `image-http-rest` patterns: `GCSStorage.Upload` in `services/media/shared-image-packages/storage/storage.go`, bucket name from env (cf. `HTTP_IMAGE_BUCKET`), streaming writer with 256KB chunks.
- Stored file metadata (`url`, `storageKey`, `name`, `extension`, `sizeInBytes`) references the GCS object.
- Migration: existing legacy files re-uploaded from S3 (`mplace-jobs.ksl.com`) → GCS; `legacy-bridge-s3-sync` can assist.

### Rate Limiting
- New capability for application submissions
- **DECIDED (2026-06-30)**: applicants must be logged-in members, so the throttle is **keyed on memberId** (no per-IP throttling needed — no anonymous applications).
- Reuse the existing profile-service per-member throttle pattern as reference (`apps/profile/services/profile-http-rest/` has contact throttling — per-member, 24h rolling window, Firestore-backed).

### Legacy S3 Sync (if applicable)
- `apps/legacy-bridge/services/legacy-bridge-s3-sync/` exists for S3→GCS file sync
- May be useful for migration of existing resume files if moving to GCS
