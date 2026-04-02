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
- File size limit: 4MB per file
- If user is logged in, memberId is stored with the application
- If user has a Quick Apply profile, pre-fill the form fields and attach saved resume
- Rate limit application submissions to deter spam (new — legacy had no explicit limit)
- Application record stored in MongoDB with all applicant data + file references

### Legacy Reference
- **Controller**: [ApplyController.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/api/controllers/ApplyController.php)
- **Application Entity**: [Application.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/Schema/Entities/Application/Application.php)
- **MongoDB Collection**: `jobsApplication`

---

## Feature 2: Resume Upload & Virus Scanning

### Description
Secure file upload for resumes and cover letters with integrated virus scanning before storage.

### Requirements
- Files uploaded via multipart form data
- Before persisting, each file is scanned for viruses
- If virus detected, reject the upload with an error message
- Clean files stored (storage destination TBD — see open questions)
- File metadata stored: URL, storage key, original filename, extension, size in bytes
- Upload filename format: `YYYY-MM-DD_FirstName_LastName_[resume|coverletter].extension` (matching legacy convention)

### Virus Scanning — QUESTION for Trufty Team
- **Existing service**: `apps/security/services/virus-scan-http-rest/` in marketplace-backend uses ClamAV
  - Endpoint: `POST /virus-scan-http-rest/scan`, max upload: 20MB
  - Returns: `{fileClean: bool, virusSignature: string}`
- **Question**: Is it appropriate to continue using this virus scanning service, or should we implement a new one? Needs input from Trufty team.

### File Storage — QUESTION for Platform/Architecture
- Legacy stored files in S3 bucket `mplace-jobs.ksl.com`
- **Question**: Should new resume/cover letter files go to GCS (consistent with marketplace-backend's image service) or remain on S3? Need to work with Platform/Architecture team/Director to determine the right approach.
- This decision also affects migration strategy: if GCS, existing files must be re-uploaded; if S3, they may be referenceable in place.

### Legacy Reference
- **File Manager**: [FileManager.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/Schema/Entities/Application/FileManager.php)
- **Virus Scanner**: [VirusScanner.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/JobsUtils/VirusScanner.php)
- **Legacy S3 Bucket**: `mplace-jobs.ksl.com`

### Out of Scope
- Plain text resume paste (NOT migrating per Notion doc)
- Plain text cover letter paste (NOT migrating per Notion doc)

---

## Feature 3: Quick Apply Profiles

### Description
Allow logged-in users to save their contact info and resume for faster job applications. Data is managed in the Quick Apply section of MyAccount.

### Requirements
- Quick Apply profile stores: first name, last name, email, zip, education level, experience level, resume file
- CRUD operations: create/update profile, retrieve profile, delete profile, remove resume
- Resume upload follows same virus scanning flow as Apply Now
- When applying to a job, user can pre-fill from Quick Apply profile
- Quick Apply section accessible in MyAccount
- **No cover letter** in Quick Apply (matches legacy behavior — Apply Now only)

### Quick Apply Update Flow — Investigation Complete

Two approaches analyzed for how Apply Now interacts with Quick Apply:

**Option A: Button/link redirect to MyAccount**

| Layer | Changes Required |
|-------|-----------------|
| Frontend (Apply Now) | Add "Edit Quick Apply in MyAccount" button/link that navigates to MyAccount Quick Apply section (legacy route: `/profile#quick-apply-info`). Need return-URL parameter for post-save redirect back to the job listing. |
| Frontend (MyAccount) | No changes — existing Quick Apply form in MyAccount handles CRUD already |
| GraphQL | No changes — `submitJobApplication` mutation stays simple |
| Backend REST | No changes — existing Quick Apply endpoints remain as-is |

- **Pros**: Low complexity, clean separation of concerns, minimal new code
- **Cons**: Two-step UX (user leaves Apply Now, goes to MyAccount, comes back)

**Option B: Checkbox on Apply Now form (legacy behavior)**

| Layer | Changes Required |
|-------|-----------------|
| Frontend (Apply Now) | Add checkbox "Save this information to my Quick Apply profile" + confirmation modal on submit. Duplicate validation logic from legacy QuickApply component (validateEmail, validateNameV2, validateZip). |
| GraphQL | `submitJobApplication` mutation needs `updateQuickApply: Boolean` parameter. New return field `quickApplyUpdated: Boolean` in response type. |
| Backend REST | `POST /application` endpoint needs conditional logic: if `updateQuickApply=true`, also call Quick Apply upsert after saving application. Must handle partial failure (application saved but Quick Apply update fails — log but don't fail the submission). |

- **Pros**: One-step UX, more convenient for users
- **Cons**: Higher complexity, cross-service coupling, more testing needed

**Comparison**

| Aspect | Option A | Option B |
|--------|----------|----------|
| Frontend work | Minimal (add link) | Moderate (checkbox, modal, validation) |
| GraphQL changes | None | New mutation parameter + response field |
| Backend changes | None | Conditional dual-write logic |
| User experience | Two steps | One step |
| Testing complexity | Simple | Complex (cross-service) |

**Hybrid approach possible**: Ship Option A first (link to MyAccount), then add Option B checkbox later as an enhancement. The API can accept `updateQuickApply` parameter without breaking changes.

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
  - Sent to job listing's contact email address
  - Subject: "Resume from [Full Name] for [Job Title]"
  - Body includes: applicant name, email, zip, education level, experience level
  - Resume file attached to email
  - Cover letter attached (if submitted)
- **MyAccount Applications view** (employer-facing):
  - Accessible via MyAccount > Listing > Manage > Applications
  - Displays list of applicants with: name, date, email, experience, zip, education
  - Download links for resume and cover letter files
  - **NTH**: Ability to remove applicants from the list (CX-requested feature)
  - **NTH**: Standalone page instead of modal for better usability viewing application data

### Legacy Reference
- **Application Emailer**: [ApplicationEmailer.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/Schema/Entities/Application/ApplicationEmailer.php)
- **Email Template**: [recievedApplication.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/api/template/emailTemplates/application/recievedApplication.php)

---

## Feature 5: Applicant Confirmation Notification

### Description
Notify the applicant that their job application was successfully submitted.

### Requirements
- Email sent to applicant's email address after successful application submission
- Email content includes:
  - Job title
  - Company name
  - Job location (city, state)
  - Job posted date
- Subject: "Your application for [Job Title] is on its way!"

### Legacy Reference
- **Confirmation Email Template**: [senderConfirmation.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/api/template/emailTemplates/application/senderConfirmation.php)

---

## Feature 6: Legacy Data Migration

### Description
Migrate existing Quick Apply profiles and (optionally) application history from the legacy Jobs platform.

### Requirements
- **Quick Apply migration**: `jobsQuickApply` → new collection, handle resume file migration (approach depends on storage decision — see Feature 2)
- **Application history migration**: `jobsApplication` → new collection, handle file migration
- Use Phase 3.1's `jobListingMigrations` collection to map legacy jobId → new ClassifiedListing ID
- Approximately 15,000+ resumes to migrate

### Dependencies
- Phase 3.1 complete (listing migration + ID mapping)
- Storage decision (Feature 2) determines migration approach
