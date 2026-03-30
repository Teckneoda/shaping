# Quick Apply

# Summary

General Classifieds does not have anything resembling an application system, and would have to be built out.

## Updates In General Feeds To Support Having Job Listings In General

👀 TODO: Scope out creating something similar in General.  Need verification from Business about what things (if any) need to be left out / changed.  We would have to also consider if application files & data are deleted / removed when the listing is deleted (unlike Jobs where listing data doesn’t expire / get deleted).

## Migration

The following is if business decides to create duplicate listings in General Classifieds for listings in current Jobs.

During migration (creating a ‘duplicate’ General listing for a Job listing), we could take the data about any applications submitted for the old Jobs listing and create new records in whatever database we use for the General applications (with the new listingId of course).

# Overview

## User Submitting Application

On the listing page, a user can select an `Apply Now` button.

- If the listing has a value in it’s `applicationUrl` field, the user is directed to that link (which takes them off of KSL).
- Otherwise the user is sent to the application page for that listing on KSL.

The Application Page asks the user for some info (name, email, zip, education level, years experience) which can be pre-filled with the data they may have entered on the My Account → Profile → Jobs Quick Apply Info section.

ℹ️ You do not need to be logged in to apply in KSL’s application page.

Example apply page: [https://jobs.ksl.com/apply-new/1029240](https://jobs.ksl.com/apply-new/1029240)

![image.png](Quick%20Apply/image.png)

There is a `Copy and paste my resume / cover letter` whose function is unknown.

Also `Save To Favorite` appears to favorite the listing.

![Screenshot 2025-12-03 at 11.34.56.png](Quick%20Apply/Screenshot_2025-12-03_at_11.34.56.png)

### Application Actions After User Submits

When the user submits the application, the following happens:

- The files are virus scanned.
- Files are saved to S3.
- User supplied data and probably S3 link to files are saved into Mongo.
- Email to user confirming they submitted the application.

![Screenshot 2025-12-03 at 14.54.50.png](Quick%20Apply/Screenshot_2025-12-03_at_14.54.50.png)

- Email to employer notifying them of application.  If the user submitted both a resume and cover letter, 2 emails are sent out.  Each email will be almost the same, just having the appropriate file attached and the wording change between ‘resume’ and ‘cover letter’.

![Screenshot 2025-12-03 at 11.39.13.png](Quick%20Apply/Screenshot_2025-12-03_at_11.39.13.png)

![Screenshot 2025-12-03 at 11.39.19.png](Quick%20Apply/Screenshot_2025-12-03_at_11.39.19.png)

Stats recorded (according to [mermaid doc](Quick%20Apply%202bd2ac5cb235804f8e85caeb790de0c5.md)).

⚠️ Note: There are 2 jobs application Mongo collections, unknown why.

- `classifieds.jobsApplication` Appears to have slightly more info, including `jobId`
- `classifieds.jobsQuickApply`

## Employer Seeing Applications

On the My Listings page, each Job listing has an `Applications` action under the `Manage` button.

When selected, a model pops up that gives some info (name, years experience, zip, email & date applied, looks like that data is user provided on the application form).

Clicking the `Resume` button downloads the saved resume.  I assume another button would be for the Cover Letter (if someone submitted one).

![Screenshot 2025-12-03 at 10.50.06.png](Quick%20Apply/Screenshot_2025-12-03_at_10.50.06.png)

![Screenshot 2025-12-03 at 10.48.35.png](Quick%20Apply/Screenshot_2025-12-03_at_10.48.35.png)

## **m-ksl-jobs Repository - Apply Functionality**

### **Backend - PHP / API**

| File | Key Elements | Purpose |
| --- | --- | --- |
| site-api/api/controllers/ApplyController.php | apply(), TotalUploadLimitInBytes | Main API endpoint for job applications, handles file uploads, creates Application entity |
| site-api/namespaces/Schema/Entities/Application/Application.php | resumeFile, coverLetterFile, applicantEmail, jobId, memberId | Application entity class with getters/setters, validation logic |
| site-api/namespaces/Schema/Entities/Application/ApplicationRepo.php | save(), getById(), getByJobId(), deleteByJobId() | MongoDB repository for jobsApplication collection |
| site-api/namespaces/Schema/Entities/Application/ApplicationEmailer.php | sendEmails(), sendEmployerEmail(), sendApplicantEmail() | Sends notification emails to employer and applicant with attachments |
| site-api/namespaces/Schema/Entities/Application/FileManager.php | uploadFile(), uploadRawText(), saveFile(), ALLOWED_TYPES | Handles file validation, virus scanning, S3 upload |
| site-api/namespaces/Schema/Entities/Application/QuickApply.php | get(), set(), setFromApplication() | Manages quick apply data in jobsQuickApply MongoDB collection |
| site-api/namespaces/Schema/Entities/Application/UploadedFile.php | s3Url, s3Key, extension, sizeInBytes | Data object for uploaded file metadata |
| site-api/namespaces/Schema/Entities/Application/DownloadedFile.php | getFileFromS3Key() | Retrieves files from S3 for download |
| site-api/namespaces/JobsUtils/VirusScanner.php | scan() | ClamAV virus scanning wrapper, production only |
| site-api/namespaces/JobsUtils/S3Utils.php | getS3Client(), getObjectContents(), S3_BUCKET | S3 client utilities for mplace-jobs.ksl.com bucket |
| site-api/namespaces/Schema/Entities/Job/Job.php | usesKslApplicationProcess(), getApplicationUrl() | Determines if job uses KSL or external application process |

### **Frontend - PHP Controllers & Views**

| File | Key Elements | Purpose |
| --- | --- | --- |
| site/application/controllers/ApplyController.php | indexAction(), saveAction(), savejsonAction(), getQuickApplyAction(), downloadApplicationAction() | Frontend controller for apply pages and actions |
| site/application/models/Listing.php | applyForJob() | Model method that calls API via ApiConnector |
| site/application/views/scripts/apply/index-responsive.phtml | frmApply form, resume_file, cover_file | Apply form template with file upload inputs |
| site/application/views/scripts/apply/thanks.phtml | - | Thank you page after successful application |
| site/application/views/scripts/apply/error.phtml | - | Error page for failed applications |
| site/application/Bootstrap.php | apply, apply_save, apply_savejson routes | Route definitions for /apply/:jid endpoints |

### **Frontend - JavaScript**

| File | Key Elements | Purpose |
| --- | --- | --- |
| site/public/js/responsive/apply.js | form validation, file size check, GTM events | Client-side form validation (email, zip, file types, 4MB limit) |
| site/public/js/react/src/apply.js | GtmDataLayer, gtmEvents | React entry point for apply page, GTM integration |
| site/public/js/react/src/apply/gtmEvents.js | gtmEvents() | GTM conversion tracking events |
| site/public/js/react/src/listing/components/Connected/index.js | getApplicationUrl() | Determines apply URL (external or /apply-new/:id) |
| site/public/js/react/src/listing/models/Job.js | applyNowEvent() | GTM event tracking for Apply Now button clicks |
| site/public/js/react/src/listing/components/JobDetails/JobDetails.js | applicationUrl, applyNowEvent | Apply Now button rendering in job details |

### **Storage**

| Storage Type | Location/Collection | Purpose |
| --- | --- | --- |
| MongoDB | jobsApplication | Stores submitted job applications |
| MongoDB | jobsQuickApply | Stores quick apply user preferences (by memberId) |
| Amazon S3 | mplace-jobs.ksl.com | Stores resume and cover letter files |

### **Exceptions**

| File | Exception Classes | Purpose |
| --- | --- | --- |
| site-api/namespaces/Schema/Entities/Application/Exceptions/ApplicationValidationException.php | ApplicationValidationException | Invalid application data |
| site-api/namespaces/Schema/Entities/Application/Exceptions/ApplicationSaveException.php | ApplicationSaveException | MongoDB save failures |
| site-api/namespaces/Schema/Entities/Application/Exceptions/ApplicationEmailException.php | ApplicationEmailException | Email sending failures |
| site-api/namespaces/Schema/Entities/Application/Exceptions/FileException.php | FileException | File upload/validation errors |
| site-api/namespaces/Schema/Entities/Application/Exceptions/FileSizeException.php | FileSizeException | File size limit exceeded |

Allowed document types (frontend): - pdf|doc|docx|jpg|jpeg|bmp|png

### Frontend Controller (site/application/controllers/ApplyController.php)

Key actions:

- indexAction() - Displays the apply form
- saveAction() - Handles form POST submission
- savejsonAction() - AJAX-based submission
- getQuickApplyAction() - Retrieves saved Quick Apply data
- saveQuickApplyAction() - Saves Quick Apply preferences
- downloadApplicationAction() - Downloads resume/cover letter from S3

### API Controller (site-api/api/controllers/ApplyController.php)

Main apply() method handles:

1. Session verification (lower security)
2. Job validation (usesKslApplicationProcess() check)
3. File upload processing via FileManager
4. Application entity creation
5. Saving to the database via ApplicationRepo
6. Email notifications via ApplicationEmailer
7. Stats recording
8. Quick Apply update (if enabled)

### Applications

Collection: `jobsApplication`
Fields:

- applicantFirstName *string*
- applicantLastName *string*
- applicantEmail *string*
- applicantZip *number*
- jobId *number*
- submissionTime *date*
- educationLevel *string*
- experienceLevel *string*
- resumeFile *object*
    - s3Url *string* // https://s3.amazonaws.com/mplace-jobs.ksl.com/1234abcd.docx
    - s3Key *string* // 1234abcd.docx
    - mediaServerUrl *string* // http://img.ksl.com/mx/mplace-jobs.ksl.com/1234abcd.docx
    - mediaServerPath *string* // "2019/09-25"
    - name *string* // "2025-12-02_John_Snow_resume.docx"
    - extension *string* // "docx"
- coverLetterFile *object*
    - s3Url *string* // https://s3.amazonaws.com/mplace-jobs.ksl.com/1234abcd.docx
    - s3Key *string* // 1234abcd.docx
    - mediaServerUrl *string* // http://img.ksl.com/mx/mplace-jobs.ksl.com/1234abcd.docx
    - mediaServerPath *string* // "2025/12-02"
    - name *string* // "2025-12-02_John_Snow_cover_letter.docx"
    - extension *string* // "docx"

### Quick Apply

Collection: `jobsQuickApply`

Fields:

- memberId *number*
- educationLevel *string* // "4-Year Degree"
- email *string*
- firstname *string*
- lastname *string*
- resume *object*
    - s3Url *string* // https://s3.amazonaws.com/mplace-jobs.ksl.com/1234abcd.docx
    - s3Key *string* // 1234abcd.docx
    - mediaServerUrl *string* // http://img.ksl.com/mx/mplace-jobs.ksl.com/1234abcd.docx
    - mediaServerPath *string* // "2025/12-02"
    - name *string* // "2025-12-02_John_Snow_resume.docx"
    - extension *string* // "docx"
    - sizeInBytes *number* // 12345
- yearsOfExperience *string* // "1-3 Years"
- zip *number*

## Apply Flow

```mermaid
flowchart TD
subgraph Frontend["Frontend Layer"]
A[User clicks Apply Now] --> B{job.applicationUrl exists?}
B -->|Yes| C[Redirect to external URL<br/>Opens in new tab]
B -->|No| D[Navigate to /apply-new/jobId<br/>KSL Application Process]
D --> E[Display Apply Form]
E --> F[User fills form<br/>+ uploads resume/cover letter]
F --> G[Client-side validation]
G -->|Invalid| H[Show errors]
H --> F
G -->|Valid| I[Submit form]
end

subgraph Site["Site Controller Layer"]
I --> J[ApplyController::savejsonAction]
J --> K[Prepare data & files]
K --> L[Check combined file size ≤4MB]
L -->|Too large| M[Return error]
L -->|OK| N[Listing::applyForJob]
N --> O[API Call via ApiConnector]
end

subgraph API["API Layer"]
O --> P[ApplyController::apply]
P --> Q[Session::verifyLowerSecurity]
Q --> R[JobRepo::getJob]
R --> S{Job exists?}
S -->|No| T[Throw ApplicationValidationException]
S -->|Yes| U{usesKslApplicationProcess?}
U -->|No| T
U -->|Yes| V[FileManager::uploadFile]
end

subgraph FileProcessing["File Processing"]
V --> W{Valid file type?<br/>pdf/doc/docx/jpg/jpeg/bmp/png}
W -->|No| X[Throw FileException]
W -->|Yes| Y{File size OK?}
Y -->|No| Z[Throw FileSizeException]
Y -->|Yes| AA[VirusScanner::scan]

subgraph Antivirus["Antivirus Scan"]
AA --> AB{Production env?}
AB -->|No| AC[Skip scan, return 0]
AB -->|Yes| AD[Execute clamdscan --fdpass]
AD --> AE{Scan result}
AE -->|0 = Clean| AF[Continue]
AE -->|1 = Virus| AG[Throw FileException<br/>Virus detected]
AE -->|2 = Error| AH[Throw Exception<br/>Scan failed]
end

AC --> AI[Save to S3]
AF --> AI
end

subgraph Storage["Storage Layer"]
AI --> AJ[S3Utils::putObject<br/>Bucket: [mplace-jobs.ksl.com](http://mplace-jobs.ksl.com/)]
AJ --> AK[Return UploadedFile object]
AK --> AL[Create Application entity]
AL --> AM[ApplicationRepo::save]
AM --> AN[MongoDB: jobsApplication collection]
end

subgraph Notifications["Email Notifications"]
AN --> AO[ApplicationEmailer::sendEmails]
AO --> AP[Send to Employer<br/>with resume attachment]
AO --> AQ[Send to Applicant<br/>confirmation email]
end

subgraph PostProcessing["Post Processing"]
AP --> AR[StatsController::recordStat]
AQ --> AR
AR --> AS{updateQuickApply flag?}
AS -->|Yes| AT[QuickApply::setFromApplication<br/>MongoDB: jobsQuickApply]
AS -->|No| AU[Return success response]
AT --> AU
end

AU --> AV[Redirect to Thanks page]

T --> AW[Return error response]
X --> AW
Z --> AW
AG --> AW
AH --> AW
M --> AW
AW --> AX[Show error to user]

style Antivirus fill:#ffebee
style Storage fill:#e3f2fd
style Notifications fill:#e8f5e9
```

## Virus Scanning

### Overview

The application uses **ClamAV** daemon (`clamdscan`) to scan uploaded files (resumes and cover letters) for malware before storing them in S3.

<aside>
💡

Stephen started on moving ClamAv from ksl-api to marketplace-backend as a cooldown project: [https://github.com/deseretdigital/marketplace-backend/tree/main/apps/security/services/virus-scan-http-rest](https://github.com/deseretdigital/marketplace-backend/tree/main/apps/security/services/virus-scan-http-rest)

</aside>

### Flow

1. File is uploaded by user
2. Check if running in production environment
    - **Non-production**: Skip scan, return 0 (clean)
    - **Production**: Execute `clamdscan --fdpass <filepath>`
3. Evaluate scan result:
    - `0` → Clean → Proceed to S3 upload
    - `1` → Virus found → Reject file
    - `2` → Scan error → Reject file

### Key Components

| Component | Location | Purpose |
| --- | --- | --- |
| `VirusScanner` | `site-api/namespaces/JobsUtils/VirusScanner.php` | Wrapper for ClamAV |
| `FileManager` | `site-api/namespaces/Schema/Entities/Application/FileManager.php` | Calls scanner on upload |

### Implementation Details

**When Triggered**

Called during `FileManager::uploadFile()` before saving to S3.

**Command**

```bash
clamdscan --fdpass <filepath>
```

**Return Codes**

| Code | Meaning | Action |
| --- | --- | --- |
| `0` | No virus | File proceeds to S3 storage |
| `1` | Virus found | Throws `FileException` |
| `2` | Scan error | Throws `Exception` with error details |

**Environment Restriction**

- **Production only** - scanning is skipped in dev/staging environments (returns `0` immediately)

**Error Messages**

| Scenario | User-Facing Message |
| --- | --- |
| Virus found | “A virus was detected in a resume.” |
| Scan failure | “We were unable to successfully scan for viruses, please try again.” |

### Security Considerations

- Filepath is escaped using `escapeshellarg()` before shell execution to prevent command injection
- Files are scanned on the server’s temporary storage before being uploaded to S3
- Temporary files are deleted after processing (both success and failure cases)

### Code Reference

**VirusScanner.php**

```php
public function scan(string $filePath)
{
    // Only scan in production    if(!HostEnv::isProduction()) {
        return 0;    }
    $filePath = escapeshellarg($filePath);    $output = [];    exec("clamdscan --fdpass $filePath", $output, $execReturn);    if ($execReturn === 2) {
        throw new \Exception(implode("\n", $output));    }
    return $execReturn;}
```

**FileManager.php (usage)**

```php
$scanResult = (new VirusScanner)->scan($filepathOnServer);if ($scanResult === 1) {
    throw new FileException('A virus was detected in a resume.');}
```

## Summary

The **Apply functionality is a jobs-specific feature** that enables job applications with resume uploads, email notifications, and applicant tracking. It is **tightly coupled to jobs domain logic** and **cannot be directly reused for classifieds without substantial modifications**.

When migrating to a classifieds codebase we should:
1. **Assess whether formal “applications” are needed** for classifieds or if simpler inquiry/contact forms suffice
2. **Design category-specific inquiry workflows** that match classified seller/buyer interactions
3. **Create new data models and storage** appropriate for classifieds use cases
4. **Build or adapt email notifications** for classifieds context
5. **Consider creating a unified “Contact/Inquiry” system**