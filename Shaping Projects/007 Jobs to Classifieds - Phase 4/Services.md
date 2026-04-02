# Jobs to Classifieds - Phase 4 — Services

## New Services

### 1. `application-http-rest` (marketplace-backend)
**Location**: `apps/jobs/services/application-http-rest/`

REST API service for job applications and Quick Apply profiles.

#### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/application` | Submit job application (multipart: JSON fields + resume/cover letter files) |
| GET | `/application/{id}` | Get application details |
| GET | `/application/listing/{listingId}` | Get applications for a listing (employer view) |
| GET | `/quick-apply` | Get Quick Apply profile for authenticated user |
| PUT | `/quick-apply` | Create/update Quick Apply profile (upsert) |
| DELETE | `/quick-apply` | Delete Quick Apply profile |
| DELETE | `/quick-apply/resume` | Remove resume from Quick Apply profile |

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
- `virus-scan-http-rest` — scan uploaded files before storage
- File storage (GCS or S3 — TBD, see Features.md Feature 2)
- Email service — send employer notifications and applicant confirmations

---

## Updated Services

### 2. `virus-scan-http-rest` (marketplace-backend)
**Location**: `apps/security/services/virus-scan-http-rest/`

**Status**: Already exists. No changes expected unless Trufty team recommends a different approach (see Features.md Feature 2).

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
submitJobApplication(input: SubmitJobApplicationInput!): JobApplication!
saveQuickApplyProfile(input: SaveQuickApplyProfileInput!): QuickApplyProfile!
deleteQuickApplyProfile: Boolean!
deleteQuickApplyResume: Boolean!
```

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

**Open question — attachments**: The existing pub/sub email pattern uses Mailgun templates with variables. Employer notification emails need **resume/cover letter file attachments**. Need to determine:
- Does the current `emailsv1.EmailMessage` protobuf support attachments?
- If not, can we include a download URL in the email body instead of attaching the file directly?
- Legacy attached actual files to the email via `JobsEmailerQueue` — may need to verify the new email service supports this

### File Storage (TBD)
- **Decision needed**: GCS vs S3 for resume/cover letter storage
- If GCS: follow `image-http-rest` patterns, use existing GCS infrastructure
- If S3: may need new bucket or continue using `mplace-jobs.ksl.com`
- Consult Platform/Architecture team

### Rate Limiting
- New capability for application submissions
- Options: per-user limit, per-IP limit, or both
- Could use existing profile service rate limiting infrastructure as reference (`apps/profile/services/profile-http-rest/` has contact throttling)

### Legacy S3 Sync (if applicable)
- `apps/legacy-bridge/services/legacy-bridge-s3-sync/` exists for S3→GCS file sync
- May be useful for migration of existing resume files if moving to GCS
