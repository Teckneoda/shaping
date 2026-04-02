# Planning State — Jobs to Classifieds - Phase 4

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
- **Open question**: Does `emailsv1.EmailMessage` support file attachments? Legacy attached resume/cover letter files directly. May need download URLs in email body instead.
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
- Image upload service pattern at `apps/media/services/image-http-rest/` (reference for file upload)
- Contact throttling in profile service (reference for rate limiting)
- Legacy bridge S3→GCS sync service exists

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

## Still Needs Research
- File storage destination: GCS vs S3 — need Platform/Architecture team input
- Rate limiting specifics: per-user limits, per-IP limits, thresholds (reference: ~35K apps in 6 weeks = ~800/day)
- Mobile app scope: Notion mentions 1 week of app work — need specifics
- Email attachments: Does `emailsv1.EmailMessage` protobuf support file attachments for employer notification emails?

## Unanswered Questions

### For Team Decision
1. **BMP file support**: Should we support BMP uploads? Legacy allowed it but it's uncommon for resumes
2. **Quick Apply update mechanism**: Button/redirect to MyAccount vs. checkbox on Apply Now form?
3. **Applications view format**: Modal (legacy) or standalone MyAccount page (NTH)?

### For Trufty Team
4. **Virus scanning service**: Is it appropriate to keep using the existing `virus-scan-http-rest` ClamAV service, or do we need a new/different approach?

### For Platform/Architecture Team
5. **File storage**: Should resume/cover letter files go to GCS or S3? This affects migration strategy
6. **S3 bucket**: If staying on S3, use existing `mplace-jobs.ksl.com` bucket or create new one?

### For Engineering
7. ~~**Email service**~~: Resolved — use pub/sub `Public_SendEmail` topic → Mailgun templates
8. **Employer notification opt-out**: Can employers disable application emails, or always-on?
9. ~~**Application history migration scope**~~: Resolved — in scope for Phase 4
10. **Mobile app work**: What specific endpoints/features need mobile support?
11. **Email attachments**: Does `emailsv1.EmailMessage` protobuf support file attachments? If not, should employer emails include download URLs instead?

## Research Sources Consulted
- [Notion: Jobs to Classifieds - Phase 4](https://www.notion.so/3142ac5cb23581858037c31abf7d6800) — Project scope, screenshots, flow diagrams, business metrics
- [deseretdigital/marketplace-backend](https://github.com/deseretdigital/marketplace-backend) — Existing services: virus-scan, image upload, messages, listing, profile (rate limiting), legacy-bridge-s3-sync
- [deseretdigital/marketplace-graphql](https://github.com/deseretdigital/marketplace-graphql) — Existing job types, favorites, pricing, report abuse; no application types yet
- Legacy `m-ksl-jobs` repo — ApplyController, Application entity, QuickApply entity, FileManager, VirusScanner, ApplicationEmailer, email templates
- Legacy `m-ksl-myaccount-v2` repo — QuickApply.tsx frontend component, profile page routing
- Shaping Projects 003-006 (Phases 3.1-3.4) — Prior phase scope and dependencies
- marketplace-backend pub/sub email pattern — `send_email.go` in listing-http-rest and listing-ps-price-drop services
