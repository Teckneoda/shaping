# Legacy Jobs Category Mapping

**Source**: [`site/application/libs/BaseOptions/BaseOptions.php`](https://github.com/deseretdigital/m-ksl-jobs/blob/main/site/application/libs/BaseOptions/BaseOptions.php) — `CATEGORY_DATA` constant

## Numeric ID to Human-Readable Name

| ID | Category Name |
|---|---|
| 1 | Accounting & Finance |
| 2 | Marketing, Advertising & PR |
| 3 | Design & Creative |
| 5 | Business & Management |
| 6 | Administrative |
| 7 | Construction & Skilled Trades |
| 8 | Customer Service |
| 9 | Writing & Editorial |
| 10 | Education & Training |
| 11 | Architecture & Engineering |
| 12 | Hospitality & Travel |
| 14 | Information Technology |
| 15 | Legal |
| 16 | Healthcare |
| 17 | Manufacturing, Mechanical & Operations |
| 18 | Other |
| 19 | Civic |
| 20 | Sales |
| 21 | Biotech & Science |
| 22 | Law Enforcement & Security |
| 23 | Software Development |
| 24 | Transportation & Logistics |
| 26 | Veterinary Services |
| 27 | Automotive |
| 28 | Cosmetology & Beauty |
| 29 | Child Care & Elder Care |
| 30 | Janitorial & Housekeeping |
| 32 | Nursing |
| 33 | Real Estate |
| 35 | Sports & Media |
| 36 | Pharmaceutical |
| 37 | Government & Military |
| 38 | Human Resources |
| 39 | Insurance |
| 40 | Non-Profit & Volunteering |
| 41 | Retail |
| 42 | Telecommunications |
| 43 | Restaurant & Food Service |
| 44 | Warehouse & Distribution |
| 45 | UI/UX & Web Designer |

## Notes

- **40 categories total** — IDs 4, 13, 25, 31, 34 are missing (likely deleted/consolidated over time)
- ID range is 1-45, not 1-43 as originally documented
- Stored as integers in MongoDB `jobs.category` field
- Exposed via REST (`/category/getCategories`) and GraphQL endpoints
- Migration script needs to map these to new string-based category/subCategory values in the Classifieds system
