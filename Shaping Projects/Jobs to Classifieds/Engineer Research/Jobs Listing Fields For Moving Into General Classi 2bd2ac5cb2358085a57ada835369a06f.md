# Jobs Listing Fields For Moving Into General Classifieds

# Summary

General listing model (database, codebase, UI) will need to be updated to support Jobs [specific fields](Jobs%20Listing%20Fields%20For%20Moving%20Into%20General%20Classi%202bd2ac5cb2358085a57ada835369a06f.md).

# Original Discovery

# Fields Investigation

This document describes the Jobs fields, and proposed how we fit them within the General Classifieds listing.  A raw analysis can be found [here](https://www.notion.so/Proposed-field-mapping-2b72ac5cb23580f2b469f8012a8ce727?pvs=21).

`***` indicates no corresponding field in General Classifieds.

Need to determine which Jobs fields we need to keep, modify, ignore as we get Jobs into General Classifieds.

## Meta Fields

| Jobs Field | General Field | Notes | Need? |
| --- | --- | --- | --- |
| id | id | Listing Id | ✅ |
| memberId | memberId | Listing owner | ✅ |
| status | status | Jobs values [’active’, ‘expired’, ‘inprogress’, ‘hidden’, ‘abuse’, null].  Will need to map to General status fields. | ✅ |
| createTime | createTime | When listing was created | ✅ |
| modifyTime | modifyTime | Last time listing was modified | ✅ |
| displayTime | displayTime | General updates the displayTime when listing is renewed (every 30 days or sooner).  Jobs unknown, but seen listings with [very old displayTimes](https://jobs.ksl.com/listing/957119).  Jobs shows displayTime in `Posting Date` section on detail page. | ✅ |
| expireTime | expireTime | Jobs expireTime appears to maybe just make the listings disappear from the site, but does not delete / archive the listing like General Classifieds does. | ✅ |
| category | subCategory | In General, all Jobs listings will be going into the Jobs category.  Jobs ‘category’ value is a number, so will need to map to the General SubCategory title.  Id → name map can be found in `m-ksl-jobs://site/application/libs/BaseOptions/BaseOptions.php` | ✅ |
| userType | *** | Values like ‘Self Serve’. | ❌ |
| history | history? |  | ✅ |
| lat | lat |  | ✅ |
| lon | lon |  | ✅ |
| latLon | latLon |  | ✅ |
| feedJobId | stockNumber | Looks like not a unique value in Jobs like General requires (see feedJobIdL ‘R0023428’).  But maybe only one active at a time? | ✅ |
| onFeed | *** | Array of strings.  Values like `zipRecruiter`, `pandoLogic`, `recruitology`.  It’s possible it was for an outbound feed to those clients.  It’s fuzzy to Abe, but he thinks that might be right.  He’s pretty sure Jobs doesn’t do that now. | ❓Ask Abe what this is? |
| stats | *** | General has stats in BigQuery. | ❌ |
| statsAggregated | *** | General has stats in BigQuery | ❌ |

## Address

### Billing Address

Looks like it was storing the info when someone payed on the Sell Form.  Looks like last record with billFirstName value was 2020-08-12.  Let’s not worry about these.

| Jobs Field | General Field | Notes | Need? |
| --- | --- | --- | --- |
| billAddress1 |  |  | ❌ |
| billAddress2 |  |  | ❌ |
| billCity |  |  | ❌ |
| billFirstName |  |  | ❌ |
| billLastName |  |  | ❌ |
| billPhone |  |  | ❌ |
| billState |  |  | ❌ |
| billZip |  |  | ❌ |

### Address

| Jobs Field | General Field | Notes | Need? |
| --- | --- | --- | --- |
| city | city | Shown on detail page | ✅ |
| state | state | Shown on detail page | ✅ |
| zip | zip | Used in SRP, shown on detail page | ✅ |

### Contact

| Jobs Field | General Field | Notes | Need? |
| --- | --- | --- | --- |
| contactName | name | Can use General listing name | ✅ |
| contactEmail | email |  | ✅ |
| contactPhone | homePhone? |  | ✅ |
| displayEmail | *** | Bool to show this? Just use contactMethod? | ❌ |
| displayPhone | *** | Bool to show this? Just use contactMethod? | ❌ |
| contactMethod | contactMethod |  | ❌ |

## Job Description Fields

| Jobs Field | General Field | Notes | Need? |
| --- | --- | --- | --- |
| description | description | Shows up under `Job Description` on detail page.  Jobs field is html, would have to convert to plain text / markdown to migrate to General (General has description & descriptionMarkdown). | ✅ |
| responsibilities | description | Shows up under `Responsibilities` on detail page.  Is html like Jobs description.  Can this be put in General description? | ☑️ |
| qualifications | description | Shows up under `Qualifications` on detail page.  Is html (list items) like Jobs description.  Can this be put in General description? | ☑️ |
| contactNotes | description | Shows up under `Additional Information` on detail page.  Is html like Jobs description.  Can this be put in General description? | ☑️ |

## Additional User Provided Fields

| Jobs Field | General Field | Notes | Need? |
| --- | --- | --- | --- |
| jobTitle | title |  | ✅ |
| applicationUrl | *** | If filled, when user hits the apply button will send them to that url instead of KSL apply page. | 🛠️ |
| companyName | businessName | Jobs employer name i.e. `Harmons` | ✅ |
| employerStatus (Job Type) | *** | Job Type values [’ft’ (Full Time), ‘pt’ (Part Time), ‘ct’ (Contract), ‘temp’ (Temporary), ‘inter’ (Internship), ‘sj’ (Seasonal)]  Map can be found in `m-ksl-jobs://site/application/libs/BaseOptions/BaseOptions.php` Filterable in SRP. | 🛠️ |
| educationLevel | *** | Number value (i.e. 3 = ‘High School’).  Map can be found in `m-ksl-jobs://site/application/libs/BaseOptions/BaseOptions.php` Filterable in SRP. | 🛠️ |
| yearsOfExperience | *** | Number value (i.e. 4 = ‘1-2 years`).  Map can be found in `m-ksl-jobs://site/application/libs/BaseOptions/BaseOptions.php` Filterable in SRP. | 🛠️ |
| jobendTime (Closing Date) | *** | Timestamp in database. Has logic so user can’t select date past listing expire date.  Abe thinks there is a cron in current Jobs that inactivates the listing after that date.  Let’s create an `applicationDeadline` field.  Should it be timestamp or should it be string `YYYY-MM-DD`? | 🛠️ |
| companyPerks | *** | Shows on detail page (saved values show as icon/labels).  In database is an array field.  Filterable in SRP. | 🛠️ |

## Pay / Salary Fields

Jobs has 2 sets of to/from pay fields (with another field indicating what type of pay it is).  It looks like when you post a Job you don’t have to put in the job’s pay.

| Jobs Field | General Field | Notes | Need? |
| --- | --- | --- | --- |
| payRangeType | *** | Values [’hourly’, ‘salary’] | 🛠️ |
| hourlyFrom | *** | Will be filled in when payRangeType = ‘hourly’.  Maybe we create General Category specifications to handle this? | 🛠️ |
| hourlyTo | *** |  | 🛠️ |
| salaryFrom | *** | Will be filled in when payRangeType = ‘salary’.  Maybe we create General Category specifications to handle this? | ☑️ (just have one set of pay to/From) |
| salaryTo | *** |  | ☑️ (just have one set of pay to/From) |

## Payment Related

| Jobs Field | General Field | Notes | Need? |
| --- | --- | --- | --- |
| paid | *** | Set to ‘1’ if some kind of payment made to post the listing. | ❌ |
| autoRepost | *** | Just use General refresh tool. | ❌ |
| promocode | *** | We aren’t doing promocodes in General. |  |
| featuredDates | standardFeaturedDates | I assume these are like General’s featured dates? | ✅ |
| purchaseDates | *** | When a featuredDate value gets added to featuredDates, a entry is added in the same position into purchaseDates that has a timestamp of the today’s date (today midnight).  Likely to track when it was added (when it was purchased). | ❌ |
| allowFreeBoost | *** | TODO: Look more into this | ☑️ Use General boost stuff |
| autoBoost | *** | TODO: Look more into this | ☑️ |
| boostHistory | *** | Array of objects with boostType (example ‘free’), and timestamp. | ☑️ |
| scheduledBoosts | *** | TODO: Look more into this | ☑️ |
| standardFeatured | *** | This bool just indicates if there are featured dates on the record (will always be set in that case even after the dates have passed).  NOT the same as General’s `standardFeatured` flag which indicates it’s permanently featured. | ❌ |
| topJob | *** | Boolean to mark if it’s a top job.  Top jobs shown on homepage and have SRP filter just for them.  General doesn’t have a similar feature. | ❓Steve looking into Top Jobs |
| topJobStart | *** | Timestamp, guessing when the top job is shown? | ❓ |
| topJobTime | *** | Timestamp, not sure, maybe when top job ends? 🤷 | ❓ |
| lastPurchaseCost | *** | Not sure if we need this in General. | ❌ |

## Photos

| Jobs Field | General Field | Notes | Need? |
| --- | --- | --- | --- |
| photo | photos | String image url.  Can move into the General photos array. | ✅ |
| companyLogoDimensions | *** | Has width/height field in the object.  Not sure if it’s used? | ❌ |

## Misc

| Jobs Field | General Field | Notes | Need? |
| --- | --- | --- | --- |
| whiteLabelSource | *** | Is white label stuff still a thing in Jobs?  Mongo has values of [null, empty array, [”siliconslopes”]].  Looks like ~8417 Jobs listings with siliconslopes whiteLabelSource.  Looking at the [Silicon Slopes Jobs Page](https://www.siliconslopes.com/c/jobs/) makes it look like we aren’t doing it anymore? | ❌ |
| abuse | *** | Jobs stores flagged as abuse info on the listing record.  General stores abuse info in a separate database. | ❌ |
| moderator |  | See abuse | ❌ |
| moderatedTime |  | See abuse | ❌ |
| relocation | *** | Doesn’t appear to be used anymore? | ❌ |
| authorizedUsers | *** | List of memberIds that can edit the listing??? | ❌ |
| postedBy | *** | Object of name/email/memberId of who posted the listing.  Jobs employers apparently can have an authorized list of users that can post / modify listings in there KSL account.  General does not support this. | ❌ |
| applicationNumber | *** | TODO: Look more into this.  Maybe related to applicationUrl? | ❔Does this need to be on the listing, or can it be queried from the Application collection? |
| inlineSpotlight | *** | TODO: Look more into this.  Not sure if this is used anymore? | ❌ |
| investment | *** | Doesn’t look like it’s used anymore? | ❌ |

# Proposed General Classifieds Changes

## Add Fields To General Classifieds Listing

Currently proposing Jobs specific fields (rather than build out a more generic Category Specifications that could share fields across different categories).  Also using top-level rather than have a nested object under a `jobs` field as it may make it easier to work with (crud operations on individual items, searchability in ElasticSearch).

| Fieldname | Type | Values | Notes |
| --- | --- | --- | --- |
| jobsApplicationUrl | string | https://someclient.com/application_url/ | Client application url to forward users to if not using KSL’s application page. |
| jobsEmploymentType | string | ‘Full Time’, ‘Part Time’, ‘Contract’, ‘Temporary’, ‘Internship’, ‘Seasonal’ | Old [values](https://github.com/deseretdigital/m-ksl-jobs/blob/6c4aa64554649a4243c91f6687b33d7a6d75b224/site/application/libs/BaseOptions/BaseOptions.php#L144-L152).  Capitalization & remove hyphens from old labels (old values were shortened strings).  In jobs it’s `employerStatus`.  Asked Gemini for better name and it says `Employment Type` is a better term used by the industry. |
| jobsEducationLevel | string | ‘None’ (do we just not include a value in that case?), ‘High School’, ‘Advanced Degree’, ‘2 Year Degree’, ‘4 Year Degree’ | Old [values](https://github.com/deseretdigital/m-ksl-jobs/blob/6c4aa64554649a4243c91f6687b33d7a6d75b224/site/application/libs/BaseOptions/BaseOptions.php#L332-L338).  Capitalization & remove hyphens from old labels (old values were ints). |
| jobsYearsOfExperience | string | ‘None’ (do we just not include a value in that case?), ‘1-2 Years’, ‘3-4 Years’, ‘5-7 Years, ‘8-10 Years’, ‘>10 Years’  | Old [values](https://github.com/deseretdigital/m-ksl-jobs/blob/6c4aa64554649a4243c91f6687b33d7a6d75b224/site/application/libs/BaseOptions/BaseOptions.php#L266-L273).  Capitalization changes from old labels (old values were ints). |
| jobsCompanyPerks | array of strings | ‘Work remote’, ‘Flexible work schedule’, …  See old values. | Old [values](https://github.com/deseretdigital/m-ksl-jobs/blob/6c4aa64554649a4243c91f6687b33d7a6d75b224/site/application/libs/BaseOptions/BaseOptions.php#L316-L330). |
| jobApplicationDeadline (maybe jobsApplicationEndDate to better indicate what is in it?) | string of format `YYYY-MM-DD` | ‘2026-02-14’ | Current Jobs doesn’t let you set date later than listing expiration timeframe (30 days), but that doesn’t necessarily match real world jobs (an application window could stretch 6 months).  Maybe let it be whatever future date the user wants?  Is there any functionality beyond just showing the date on the detail page?  In old Jobs the field is `jobendTime`.  |
| jobsPayRangeType | string | ‘hourly’, ‘salary’ | Will determine what kind of fields jobsPayFrom/To represent. |
| jobsPayFrom | int | 1250 (for $12.50), 8500000 (for $85,000) | Money number in cents (to avoid float values).  Maybe 0 for not set? |
| jobsPayTo | int | 1925 (for $1925), 12000000 (for $120,000) | Maybe 0 for not set? |
| marketType | string | ‘Job’ | Not new, just adding new value `Job` |

### ❓Fields still in flux

- applicationNumber: Do we need it (for things like My Account that uses data from ElasticSearch), or can it be looked up on demand (GraphQL sees it needs Jobs applications so it adds that data).
- Top Jobs: Business needs to let us know if Top Jobs is something that needs to be supported / built out.

### Locations To Update

**Capi**

Regardless if a new Listing Service is created, we will still likely need to update Capi for backwards compatibility as lots of things make use of Capi for working with General Listings (which the new Jobs listings will be).

- Update [listing model](https://github.com/deseretdigital/m-ksl-classifieds-api/blob/master/src/Library/Model/Listing.php) with new fields.
- Add validation to updateListing endpoint?  I.e. check for allowed values and format?  Only let listings with category ‘Jobs’ set those fields?
- I believe the Get Listing endpoint should return the new data automatically when it’s added to the Mongo record.

**Mongo Connector & ElasticSearch**

- Update ElasticSearch 6 & ElasticSearch 8 General indices with the new fields.
- Update Mongo Connector, needs to be done after ES indices updates (should just need to update the schema file, will force a restart of connectors on merge which then the pods will then get updated schema from ES servers).

**GraphQL**

- Update queries, mutations & calls to Capi to include the new fields.  Unknown what all that entails.

**Saved Search**

- Frond-end where saved searches are created / edited / shown will need the searchable new fields
- The processor of saved searches will need to respect

**Front Ends**

- Sell Form (when someone select ‘Jobs’ category):
    - Show input fields for the new Jobs fields (prefilling if editing existing listing)
    - Only allow one Listing Type (marketType), ‘Job’.
    - Some fields not shown for Job listings (Condition, Price, Payment Types Accepted, Youtube Video?), Seller Type only allow ‘Business’.
- Detail page: Update to show added fields for Jobs category listings.
- Search page: Add facets to SRP for fields when user searches for ‘Jobs’ category listings.  Probably search url stuff may be affected.  Would need to update search query stuff.
- My Listings: Remove ‘Mark As Sold’ and ‘Mark As Sale Pending’ options under ‘Manage’ for listings with ‘Jobs’ category.
    - For applications epic:
        - Add ‘Applications’ option under Manage (like current Jobs)
        - Add ‘Applications’ count to performance (like current Jobs)

**Feeds**

Support for new fields would need to be added:

- Read from corresponding columns from client CSVs.
- Update getting of listing data from Capi
- Update sending of listing data to Capi