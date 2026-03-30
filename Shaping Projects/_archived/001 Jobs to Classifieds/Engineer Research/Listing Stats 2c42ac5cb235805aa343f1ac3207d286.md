# Listing Stats

# Summary

👀 Need to confirm with business

I think most stats should be able to be handled by the existing stat stuff for General Classifieds (which uses GA/Big Query for showing stats on the My Listings page, and Memcache for the realtime detail page stats).

General does not have stats for [Job Applications (Quick Apply)](https://www.notion.so/Quick-Apply-2bd2ac5cb235804f8e85caeb790de0c5?pvs=21), but as that is a new feature for General, the stats for that will have to be determined when it is built out.

# Statistics Architecture & Migration Guide

## Part 1: Jobs Vertical Statistics Architecture

## Overview

The Jobs vertical uses a **dual-storage architecture** for statistics:

1. **Real-time tracking** via MongoDB (daily granular stats + aggregated counts)
2. **Analytics warehouse** via Google BigQuery (detailed event tracking from web and app platforms)
3. **Periodic synchronization** from BigQuery to MongoDB for dashboard reporting

This architecture enables:
- Fast real-time stat updates for immediate feedback
- Comprehensive historical analytics via BigQuery
- Efficient dashboard queries via pre-aggregated MongoDB data
- Separation of concerns between operational and analytical data

---

## Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      User Interactions                          │
│  (Page Views, Clicks, Applications, Favorites, Prints, etc.)    │
└────────────┬─────────────────────────────────────┬──────────────┘
             │                                     │
             │                                     │
    ┌────────▼─────────┐                 ┌─────────▼──────────┐
    │   Frontend GTM   │                 │   API Endpoints    │
    │   (DataLayer)    │                 │  (StatsController) │
    └────────┬─────────┘                 └─────────┬──────────┘
             │                                     │
             │                                     │
    ┌────────▼─────────────────────────────────────▼─────────┐
    │              Google Tag Manager / Analytics            │
    └────────┬───────────────────────────────────────────────┘
             │
             │
    ┌────────▼───────────┐
    │   Google BigQuery  │
    │   - job_stats.     │
    │     Web_Client_    │ 
    │     Dashboard_     │ 
    │     Stats          │
    │   - job_stats.     │
    │     App_Client_    │
    │     Dashboard_     │
    │     Stats          │
    └────────┬───────────┘
             │
             │ Daily Cron Job
             │ (getStatsFromBigQuery.php)
             │
    ┌────────▼──────────────────────────────────────────────┐
    │              MongoDB Collections                      │
    │  ┌──────────────────────────────────────────────────┐ │
    │  │  1. jobs collection                              │ │
    │  │     - stats (daily breakdown by date)            │ │
    │  │       • stats.ui.jdp.view.20231225: 48           │ │
    │  │       • stats.ui.srp.featured.view.20231225      │ │
    │  │       • stats.ui.srp.featured.click.20231225     │ │
    │  │     - statsAggregated (lifetime totals)          │ │
    │  │       • jdpViewCount                             │ │
    │  │       • featuredViewCount                        │ │
    │  │       • applicationKslApplyCount                 │ │
    │  │                                                  │ │
    │  │  2. jobsBigQueryStats collection                 │ │
    │  │     - DATE (YYYYMMDD format)                     │ │
    │  │     - listingId                                  │ │
    │  │     - sellerId                                   │ │
    │  │     - source (web/app)                           │ │
    │  │     - standard_srp_listViews                     │ │
    │  │     - featured_srp_listViews                     │ │
    │  │     - spotlight_srp_listViews                    │ │
    │  │     - detailViews                                │ │
    │  │     - client_apply                               │ │
    │  │     - ksl_apply_clicks                           │ │
    │  │     - ksl_apply_success                          │ │
    │  │     - calls, emails                              │ │
    │  └──────────────────────────────────────────────────┘ │
    └─────────┬─────────────────────────────────────────────┘
              │
              │ Query & Retrieval
              │
    ┌─────────▼─────────────────────────────────────────────┐
    │           Client-Facing Applications                  │
    │  ┌──────────────────────────┬──────────────────────┐  │
    │  │  MyAccount Dashboard     │  Email Reports       │  │
    │  │  (m-ksl-myaccount-v2)    │  (Cron Jobs)         │  │
    │  │  - JobsPerformance.ts    │  - Usage Reports     │  │
    │  │  - Analytics Charts      │  - Monthly Reports   │  │
    │  └──────────────────────────┴──────────────────────┘  │
    └───────────────────────────────────────────────────────┘
```

---

## MongoDB Collections

### 1. `jobs` Collection

The main collection for job listings also stores two types of statistics:

### Daily Stats (Granular)

Stored under `stats` field with hierarchical structure:

```jsx
{
  "id": 12345,
  "jobTitle": "Software Engineer",
  "stats": {
    "ui": {
      "jdp": {           // Job Detail Page
        "view": {
          "20231225": 48,
          "20231226": 62
        },
        "print": {
          "20231225": 2
        }
      },
      "srp": {           // Search Results Page
        "featured": {
          "view": {
            "20231225": 125,
            "20231226": 143
          },
          "click": {
            "20231225": 18,
            "20231226": 21
          }
        }
      },
      "favorite": {
        "add": {
          "20231225": 5
        }
      },
      "application": {
        "kslApply": {
          "20231225": 3
        }
      }
    }
  },
  "statsAggregated": {
    "jdpViewCount": 6234,
    "jdpPrintCount": 45,
    "srpFeaturedViewCount": 3421,
    "srpFeaturedClickCount": 342,
    "favoriteAddCount": 156,
    "applicationKslApplyCount": 89
  }
}
```

**Stat Recording Process:**
- Stats are recorded via `StatsController::recordStat()` API endpoint
- Format: `stats.{category}.{action}.{date}`
- Both daily and aggregated counters are updated atomically
- Memcache is updated for fast retrieval (5-minute TTL)

**Key Patterns:**
- `stats.ui.jdp.view` - Job Detail Page views
- `stats.ui.srp.featured.view` - Featured listing impressions on SRP
- `stats.ui.srp.featured.click` - Featured listing clicks on SRP
- `stats.ui.favorite.add` - Favorites added
- `stats.ui.application.kslApply` - Applications submitted via KSL

### 2. `jobsBigQueryStats` Collection

Stores daily statistics synced from BigQuery:

```jsx
{
  "DATE": 20231225,              // Integer: YYYYMMDD
  "listingId": 12345,            // Integer
  "sellerId": 67890,             // Integer (member ID)
  "source": "web",               // String: "web" or "app"
  
  // Search Results Page (SRP) Stats
  "standard_srp_listViews": 245,
  "standard_srp_clicks": 23,
  "featured_srp_listViews": 125,
  "featured_srp_clicks": 18,
  "spotlight_srp_listViews": 87,
  "spotlight_srp_clicks": 12,
  
  // Detail Page Stats
  "detailViews": 48,
  
  // Application/Contact Stats
  "client_apply": 2,             // External application clicks
  "ksl_apply_clicks": 5,         // KSL apply form opens
  "ksl_apply_success": 3,        // KSL apply form submissions
  "emails": 1,
  "calls": 0
}
```

**Note on Source Field:**
- `source: "web"` - Statistics from web platform
- `source: "app"` - Statistics from mobile app
- App stats have featured/spotlight fields set to 0 (not available on app)

**Data Synchronization:**
- Daily cron job runs to import yesterday’s data from BigQuery
- Records are upserted based on composite key: `{DATE, listingId, sellerId, source}`
- Handles deduplication when multiple records exist for same listing/date

---

## BigQuery Integration

### BigQuery Tables

Located in `job_stats` dataset:

1. **`Web_Client_Dashboard_Stats`**
    - Web platform analytics
    - Captured via Google Tag Manager events
    - Includes all upgrade types (featured, spotlight, etc.)
2. **`App_Client_Dashboard_Stats`**
    - Mobile app analytics
    - Standard impressions and clicks only
    - Detail page views and application events

### Data Import Process

**Script**: `crons/regular-actions/statsFromBigQuery/getStatsFromBigQuery.php`

**Worker**: `BigQueryMongoWorker.php`

**Frequency**: Daily (typically for previous day’s data)

**Process Flow:**

1. **Query BigQuery**
    
    ```sql
    SELECT * FROM `job_stats.Web_Client_Dashboard_Stats`
    WHERE DATE = '20231225'ORDER BY DATE, listingId, sellerId DESC
    ```
    
2. **Deduplication**
    - Keys by `{DATE}-{listingId}`
    - Sums stats from duplicate records
    - Prefers records with sellerId when available
3. **Seller ID Resolution**
    - If sellerId missing in BigQuery, looks up in MongoDB jobs collection
    - Skips records where listing cannot be found
4. **MongoDB Upsert**
    - Upserts to `jobsBigQueryStats` collection
    - Composite key ensures no duplicates
    - Sets featured/spotlight fields to 0 for app source

**Command Line Usage:**

```bash
# Import yesterday's stats (default)
php getStatsFromBigQuery.php

# Import specific date range
php getStatsFromBigQuery.php --startDate="20231201" --endDate="20231231"
```

**Error Handling:**
- Sends email notification if no data returned from BigQuery
- Logs failures but continues processing other tables
- DataDog tracing for monitoring and debugging

---

## Stats Recording & Tracking

### Server-Side Recording

**API Endpoint**: `/classifieds/jobs/stats/recordStat`

**Controller**: `StatsController::recordStat()`

**Location**: `site-api/api/controllers/StatsController.php`

**Method Signature:**

```php
public function recordStat($key, $id, $memberId = '', $op = 'inc', $value = 1)
```

**Parameters:**
- `$key` - Stat key (e.g., “ui.jdp.view”)
- `$id` - Listing ID
- `$memberId` - Member ID (optional, not currently used)
- `$op` - Operation: “inc” (increment) or “set”
- `$value` - Value to increment/set

**Execution:**
1. Validates input parameters
2. Constructs full keys:
- Daily key: `stats.{key}.{YYYYMMDD}`
- Aggregate key: `statsAggregated.{camelCaseName}Count`
3. Performs atomic MongoDB update on jobs collection
4. Updates memcache for listing (5-minute TTL)

**Example Recording:**

```jsx
// Record a detail page view
POST /classifieds/jobs/stats/recordStat
{
  "key": "ui.jdp.view",
  "id": 12345,
  "op": "inc",
  "value": 1
}

// Results in MongoDB update:
{
  "$inc": {
    "stats.ui.jdp.view.20231225": 1,
    "statsAggregated.jdpViewCount": 1
  }
}
```

### Client-Side Tracking (Google Tag Manager)

**Service**: `PageViewService.php`

**Library**: `GtmDataLayer.php`

**Location**: `site/library/`

### PageView ID Generation

Each page view gets a unique ID used for tracking:

```php
// PageViewService::id()
// Format: Base-36 encoded (timestamp + hostname hash)
$pageviewId = PageViewService::id(36, 'gtm');
// Example: "abc123def456"
```

**Usage:**
- Passed to Google Tag Manager
- Used for session correlation
- Enables cross-platform analytics

### DataLayer Structure

The GTM dataLayer contains structured information:

```jsx
window.dataLayer = [{
  brandDetails: {
    "Entity": "KSL - Jobs",
    "Objective": "Marketplace"
  },
  pageDetails: {
    "Seller ID": "67890",
    "Site Section": "Jobs",
    "Login State": true,
    "Site Version Number": "1.0.0",
    "Template": "detail page",
    "Job Title": "software engineer",
    "Category": "information technology",
    "Employer Name": "acme corp",
    "ddmHitID": "abc123def456",
    "ddmSessionID": "session123",
    "ddmDeviceID": "device456",
    "Content Type": "featured|top job",
    "Ad ID": "12345"
  },
  sessionDetails: {
    "Login Method": "traditional",
    "Client ID": "GA1.2.123456789.1234567890",
    "ddmSessionID": "session123"
  },
  userDetails: {
    "userId": "67890",
    "regDate": "2020-01-15"
  }
}];
```

**Key DataLayer Variables:**

| Variable | Usage | Example Values |
| --- | --- | --- |
| Template | Page type | “homepage”, “srp”, “detail page”, “apply now” |
| Ad ID | Listing ID | 12345 |
| Seller ID | Member/employer ID | 67890 |
| Content Type | Upgrades used | “featured”, “top job”, “bundle name” |
| ddmHitID | Page view ID | “abc123def456” |
| Category | Job category | “information technology” |
| Job Title | Listing title | “software engineer” |
| Login State | User logged in | true/false |

**Event Tracking:**

Events pushed to dataLayer trigger GTM tags:

```jsx
// Detail page view
dataLayer.push({
  event: 'virtualPageview',
  virtualUrl: '/jobs/listing/12345'
});

// Application click
dataLayer.push({
  event: 'job_application_click',
  listingId: '12345',
  applicationType: 'ksl'
});

// Featured listing click
dataLayer.push({
  event: 'featured_listing_click',
  listingId: '12345',
  position: 3
});
```

**Files Involved:**
- `site/library/GtmDataLayer.php` - Server-side dataLayer builder
- `site/public/js/react/src/utils/GtmDataLayer.js` - Client-side utilities
- `site/public/js/react/src/whitelabel/utils/CustomDimensions.js` - React SPA tracking

---

## Stats Retrieval & Display

### API Endpoints

All endpoints in `site-api/api/controllers/StatsController.php`:

### 1. Get JDP Views by Ad

**Endpoint**: `/classifieds/jobs/stats/getJdpViewsByAd`

**Method**: GET

**Parameters**: `id` (listing ID)

**Returns**: Total job detail page views

```php
public function getJdpViewsByAd($id)
```

**Response:**

```json
{
  "status": 1,
  "response": {
    "views": 6234
  }
}
```

### 2. Get Featured Views by Ad

**Endpoint**: `/classifieds/jobs/stats/getFeaturedViewsByAd`

**Method**: GET

**Parameters**: `id` (listing ID)

**Returns**: Total featured impressions on SRP

### 3. Get Featured Clicks by Ad

**Endpoint**: `/classifieds/jobs/stats/getFeaturedClicksByAd`

**Method**: GET

**Parameters**: `id` (listing ID)

**Returns**: Total featured clicks on SRP

### 4. Retrieve Stat (Generic)

**Endpoint**: `/classifieds/jobs/stats/retrieveStat`

**Method**: GET

**Parameters**: `key` (stat path), `id` (listing ID)

**Returns**: Daily breakdown for specific stat

```php
public function retrieveStat($key, $id)
```

**Example:**

```jsx
GET /classifieds/jobs/stats/retrieveStat?key=ui.jdp.view&id=12345

Response:
{
  "status": 1,
  "response": {
    "results": {
      "20231223": 42,
      "20231224": 56,
      "20231225": 48
    }
  }
}
```

### 5. Get Aggregated Stats

**Endpoint**: `/classifieds/jobs/stats/getAggregatedStats`

**Method**: GET

**Parameters**: `ids` (array of listing IDs)

**Returns**: Lifetime aggregated stats for multiple listings

```php
public function getAggregatedStats($ids)
```

**Response:**

```json
{
  "status": 1,
  "response": {
    "12345": {
      "jdpViewCount": 6234,
      "jdpPrintCount": 45,
      "favoriteCount": 156
    },
    "12346": {
      "jdpViewCount": 3421,
      "jdpPrintCount": 23,
      "favoriteCount": 89
    }
  }
}
```

### 6. Get Google Analytic Stats (BigQuery)

**Endpoint**: `/classifieds/jobs/stats/getGoogleAnalyticStats`

**Method**: GET

**Parameters**: `ids` (array of listing IDs)

**Returns**: Daily and total stats from BigQuery

```php
public function getGoogleAnalyticStats($ids)
```

**Response:**

```json
{
  "status": 1,
  "response": {
    "stats": {
      "12345": {
        "20231223": {
          "date": 20231223,
          "impressions": 245,
          "views": 48,
          "applicationClicks": 7,
          "applicationSubmits": 3
        },
        "20231224": {
          "date": 20231224,
          "impressions": 267,
          "views": 52,
          "applicationClicks": 8,
          "applicationSubmits": 4
        }
      }
    },
    "totals": {
      "12345": {
        "impressions": 5234,
        "views": 1023,
        "applicationClicks": 145,
        "applicationSubmits": 67
      }
    }
  }
}
```

**Calculation Logic:**
- `impressions` = standard_srp_listViews + featured_srp_listViews + spotlight_srp_listViews
- `views` = detailViews
- `applicationClicks` = client_apply + ksl_apply_clicks
- `applicationSubmits` = ksl_apply_success

### 7. Batch Retrieval Endpoints

**Get JDP Views by IDs**

```php
public function getJdpViewsByIds($ids)
// Returns daily breakdown for multiple listings
```

**Get SRP Views by IDs**

```php
public function getSrpViewsByIds($ids)
// Returns featured SRP views for multiple listings
```

**Get SRP Clicks by IDs**

```php
public function getSrpClicksByIds($ids)
// Returns featured SRP clicks for multiple listings
```

---

## Frontend Integration

### React Components

The Jobs vertical uses React for the front-end, with tracking integrated throughout:

**Location**: `site/public/js/react/src/`

### Key Tracking Points

1. **Search Results Page (SRP)**
    - Featured listing impressions
    - Featured listing clicks
    - Standard listing impressions
    - Spotlight listing impressions
    - Pagination tracking
2. **Job Detail Page (JDP)**
    - Page view tracking
    - Application button clicks (KSL vs external)
    - Print button clicks
    - Favorite/unfavorite actions
    - Email/call buttons
3. **Apply Page**
    - Application form views
    - Application submissions
    - Success/error tracking
4. **Posting/Edit Flow**
    - Listing creation events
    - Upgrade selections
    - Purchase completions

### GTM Event Examples

**JavaScript implementation:**

```jsx
// From site/public/js/react/src/whitelabel/models/Listing.js

// Track detail page view
trackEvent() {
  if (typeof window !== 'undefined' && window.dataLayer) {
    window.dataLayer.push({
      event: 'job_detail_view',
      listingId: this.id,
      jobTitle: this.jobTitle,
      category: this.category,
      sellerId: this.sellerId
    });
  }
}

// Track application click
trackApplicationClick(applicationType) {
  if (typeof window !== 'undefined' && window.dataLayer) {
    window.dataLayer.push({
      event: 'job_application_click',
      listingId: this.id,
      applicationType: applicationType // 'ksl' or 'external'
    });
  }
}

// Track favorite action
trackFavorite(action) {
  if (typeof window !== 'undefined' && window.dataLayer) {
    window.dataLayer.push({
      event: 'job_favorite_' + action, // 'add' or 'remove'
      listingId: this.id
    });
  }
}
```

---

## Email Reporting

### Client-Facing Reports

Several cron jobs generate and send email reports to employers with statistics about their job listings.

### 1. Usage Report

**Script**: `crons/email-reports/clientFacingReport/clientFacingUsageReport.php`

**Classes**: `EmployerTransactionReport`, `UsageByAuthorizedUsersReport`

**Frequency**: Monthly

**Recipients**: Employers with monthly reporting enabled

**Content:**
- Transactions by package usage
- Transactions without package
- Usage breakdown by authorized users
- Product quantities (listings, boosts, featured, top job)
- Invoice amounts

**Command:**

```bash
# Send to specific member
php clientFacingUsageReport.php --memberId=67890

# Send to specific month
php clientFacingUsageReport.php --monthDate="2023-11-01"
```

### 2. Feed Reports

**Script**: `crons/email-reports/JobsFeedReport/JobsFeedReport.php`

**Frequency**: Monthly

**Recipients**: Internal team + specific clients

**Content (CSV Attachments):**
- Employer group name
- Company name
- Transaction dates
- Job titles and locations
- Product quantities
- Package discounts
- Invoice amounts
- Promo code usage

**Clients with dedicated reports:**
- LHM (memberId: 4096)
- Ken Garff (memberId: 41066)
- Scrape Group (memberId: 41063)
- Workstream (memberId: 41069)
- Waste Management (memberId: 41075)

### 3. BBU Monthly Report

**Script**: `crons/email-reports/BbuMonthlyReport/BbuMonthlyReport.php`

**Recipients**: BBU (Business Banking Unit) team

**Content**: Business account activity and revenue metrics

### 4. Promo Code Usage Reports

**Script**: `crons/email-reports/promocodeUsage/`

**Content**: Promo code redemption statistics

### 5. Saved Searches Report

**Script**: `crons/email-reports/savedSeearches/SavedSearchesReport.php`

**Content**: User saved search activity and match notifications

---

## MyAccount Dashboard

The MyAccount v2 application provides employers with a dashboard to view their listing performance.

**Repository**: `m-ksl-myaccount-v2`

**Framework**: Next.js (React + TypeScript)

### Jobs Performance Service

**File**: `services/ListingPerformance/JobsPerformance.ts`

This service retrieves and aggregates stats for the Jobs dashboard.

**Function Signature:**

```tsx
async function JobsPerformance(
  ids: number[],
  memberId: number
): Promise<ListingPerformanceData>
```

**Data Aggregation Process:**

1. **Query BigQuery Stats** (from `jobsBigQueryStats` collection)
    
    ```tsx
    db.collection("jobsBigQueryStats").aggregate([
      {
        $match: {
          listingId: { $in: ids }
        }
      },
      {
        // Group by listing and date, sum web + app stats
        $group: {
          _id: { id: "$listingId", date: "$DATE" },
          applicationClicks: {
            $sum: { $add: ["$client_apply", "$ksl_apply_clicks"] }
          },
          applicationSubmits: { $sum: "$ksl_apply_success" },
          impressions: {
            $sum: {
              $add: [
                "$standard_srp_listViews",
                "$featured_srp_listViews",
                "$spotlight_srp_listViews"
              ]
            }
          },
          views: { $sum: "$detailViews" }
        }
      },
      {
        // Group by listing, create totals and byDay array
        $group: {
          _id: "$_id.id",
          totalApplicationClicks: { $sum: "$applicationClicks" },
          totalApplicationSubmits: { $sum: "$applicationSubmits" },
          totalImpressions: { $sum: "$impressions" },
          totalViews: { $sum: "$views" },
          byDay: {
            $addToSet: {
              date: "$_id.date",
              applicationClicks: "$applicationClicks",
              applicationSubmits: "$applicationSubmits",
              impressions: "$impressions",
              views: "$views"
            }
          }
        }
      }
    ])
    ```
    
2. **Query Listing Data** (from `jobs` collection)
    
    ```tsx
    db.collection("jobs").aggregate([
      {
        $match: {
          id: { $in: ids },
          $or: [
            { memberId: memberId },
            { authorizedUsers: memberId }
          ]
        }
      },
      {
        $project: {
          id: 1,
          type: "Jobs",
          attributes: {
            applicationUrl: "$applicationUrl",
            mongoStats: "$stats",
            boostHistory: {
              $filter: {
                input: "$boostHistory",
                cond: { $eq: ["$$boost.boostType", "free"] }
              }
            }
          },
          statsAggregated: 1
        }
      }
    ])
    ```
    
3. **Merge Data**
    - Combines BigQuery stats with listing data
    - Falls back to MongoDB aggregated stats for new listings (< 1 day old)
    - Uses heuristic: mongo views as impressions, 1/4 mongo views as detail views

**Response Structure:**

```tsx
[
  {
    id: 12345,
    type: "Jobs",
    attributes: {
      applicationUrl: "https://example.com/apply",
      boostHistory: [...],
      performanceData: {
        totals: {
          impressions: 5234,
          views: 1023,
          applicationSubmits: 67,
          applicationClicks: 145,
          mongoApplicationCount: 89  // From statsAggregated
        },
        byDay: [
          {
            date: 20231223,
            impressions: 245,
            views: 48,
            applicationClicks: 7,
            applicationSubmits: 3
          },
          // ... more days
        ]
      }
    }
  },
  // ... more listings
]
```

### GraphQL Integration

**File**: `graphql-queries/analytics-report/index.ts`

Queries for dashboard analytics:

```graphql
query getListingsReport(
  $listingType: [ListingType!]!
  $listingId: String
) {
  getListingsReport(
    listingType: $listingType
    listingId: $listingId
  ) {
    totals {
      activeListings
      activeListingsValue
      impressions
      views
      favorites
      leads
    }
    byDate {
      date
      standardImpressions
      featuredImpressions
      views
      favorites
      leads
    }
  }
}
```

**Query for multiple listings:**

```graphql
query getListingsListReport(
  $listingType: ListingType!
  $listingId: [String!]!
) {
  getListingsListReport(
    listingType: $listingType
    listingId: $listingId
  ) {
    listingId
    totals { ... }
    byDate { ... }
  }
}
```

### Dashboard Components

**Dashboard Display**:
- `components/Dashboard/` - Main dashboard components
- `components/Listing/` - Individual listing performance cards
- Chart.js integration for performance graphs
- Date range filtering
- Export functionality

**Data Transformation**:
**File**: `utils/analyticsData.ts`

```tsx
function transformAnalyticsData(
  data: AnalyticsReport.ByDateEntry[]
): AnalyticsReport.DataForCharts {
  return {
    dates: [],              // ['Dec 23', 'Dec 24', ...]
    standardImpressions: [], // [245, 267, ...]
    featuredImpressions: [], // [125, 143, ...]
    views: [],              // [48, 52, ...]
    favorites: [],          // [5, 7, ...]
    leads: []               // [7, 8, ...]
  };
}
```

---

## Key Components Reference

### MongoDB Collections

| Collection | Purpose | Key Fields | Indexed On |
| --- | --- | --- | --- |
| `jobs` | Main listing data + embedded stats | id, stats, statsAggregated, memberId | id, memberId |
| `jobsBigQueryStats` | Daily stats from BigQuery | DATE, listingId, sellerId, source | listingId, DATE, sellerId |

### BigQuery Tables

| Table | Platform | Dataset | Location |
| --- | --- | --- | --- |
| `Web_Client_Dashboard_Stats` | Web | job_stats | US |
| `App_Client_Dashboard_Stats` | Mobile App | job_stats | US |

### Key Scripts

| Script | Location | Purpose | Frequency |
| --- | --- | --- | --- |
| `getStatsFromBigQuery.php` | crons/regular-actions/statsFromBigQuery/ | Import BigQuery stats to MongoDB | Daily |
| `BigQueryMongoWorker.php` | crons/regular-actions/statsFromBigQuery/ | Worker class for BigQuery import | - |
| `clientFacingUsageReport.php` | crons/email-reports/clientFacingReport/ | Send usage reports to employers | Monthly |
| `JobsFeedReport.php` | crons/email-reports/JobsFeedReport/ | Send feed transaction reports | Monthly |

### API Controllers

| Controller | Repository | Location | Purpose |
| --- | --- | --- | --- |
| `StatsController` | m-ksl-jobs | site-api/api/controllers/ | Record and retrieve job stats |
| `BigQueryController` | ksl-api | public_html/classifieds/common/api/controllers/ | Import stats from BigQuery (Cars/Backlot) |
| `StatsController` | ksl-api | public_html/classifieds/general/api/controllers/ | General classifieds stats (memcache-based) |

### Frontend Files

| File | Repository | Purpose |
| --- | --- | --- |
| `GtmDataLayer.php` | m-ksl-jobs | Server-side GTM dataLayer builder |
| `PageViewService.php` | m-ksl-jobs | Generate unique page view IDs |
| `GtmDataLayer.js` | m-ksl-jobs | Client-side GTM utilities |
| `CustomDimensions.js` | m-ksl-jobs | React SPA GTM tracking |
| `JobsPerformance.ts` | m-ksl-myaccount-v2 | MyAccount dashboard data service |
| `analyticsData.ts` | m-ksl-myaccount-v2 | Transform data for charts |

### Stat Types Reference

### Daily Stats (in `jobs.stats`)

| Stat Key | Description | Example Value |
| --- | --- | --- |
| `ui.jdp.view` | Job detail page views | 48 |
| `ui.jdp.print` | Print button clicks | 2 |
| `ui.srp.featured.view` | Featured impressions on SRP | 125 |
| `ui.srp.featured.click` | Featured clicks on SRP | 18 |
| `ui.srp.standard.view` | Standard impressions on SRP | 245 |
| `ui.favorite.add` | Favorites added | 5 |
| `ui.favorite.remove` | Favorites removed | 1 |
| `ui.application.kslApply` | KSL applications submitted | 3 |

### Aggregated Stats (in `jobs.statsAggregated`)

| Field | Description | Type |
| --- | --- | --- |
| `jdpViewCount` | Total JDP views | Integer |
| `jdpPrintCount` | Total print clicks | Integer |
| `srpFeaturedViewCount` | Total featured impressions | Integer |
| `srpFeaturedClickCount` | Total featured clicks | Integer |
| `favoriteAddCount` | Total favorites added | Integer |
| `favoriteRemoveCount` | Total favorites removed | Integer |
| `applicationKslApplyCount` | Total KSL applications | Integer |

### BigQuery Stats Fields

| Field | Description | Source |
| --- | --- | --- |
| `standard_srp_listViews` | Standard listing impressions | Web/App |
| `standard_srp_clicks` | Standard listing clicks | Web/App |
| `featured_srp_listViews` | Featured listing impressions | Web only |
| `featured_srp_clicks` | Featured listing clicks | Web only |
| `spotlight_srp_listViews` | Spotlight impressions | Web only |
| `spotlight_srp_clicks` | Spotlight clicks | Web only |
| `detailViews` | Detail page views | Web/App |
| `client_apply` | External application clicks | Web/App |
| `ksl_apply_clicks` | KSL apply form opens | Web/App |
| `ksl_apply_success` | KSL apply submissions | Web/App |
| `emails` | Email button clicks | Web/App |
| `calls` | Call button clicks | Web/App |

---

## Data Retention & Performance

### Retention Policies

1. **MongoDB `jobs.stats`**
    - Daily stats retained indefinitely
    - Grows with each active day
    - No automatic cleanup (historical data valuable)
2. **MongoDB `jobsBigQueryStats`**
    - Records deleted before new import (daily cleanup)
    - Typically retains 60-90 days
    - Historical data can be re-imported from BigQuery
3. **BigQuery Tables**
    - Partitioned by DATE
    - Retained per Google Cloud retention policy
    - Long-term historical analytics

### Performance Considerations

1. **Memcache Layer**
    - Listing data cached for 5 minutes
    - Includes statsAggregated but NOT daily stats
    - Cache key: `{env}-jobs-getad-{listingId}`
2. **MongoDB Indexes**
    - `jobs`: Indexed on `id`, `memberId`
    - `jobsBigQueryStats`: Indexed on `listingId`, `DATE`, composite
3. **Query Optimization**
    - Use aggregated stats for totals when possible
    - Query BigQuery stats for detailed historical analysis
    - Batch requests for multiple listings
4. **BigQuery Import**
    - Runs during low-traffic hours
    - Processes in batches (LIMIT 500, OFFSET)
    - Uses upserts to handle duplicates efficiently

---

## Additional Notes

### Authorization & Security

- Listing stats only available to listing owner or authorized users
- Member authentication required for MyAccount dashboard
- Admin JWT tokens used for internal reporting
- No PII in stats data (only IDs and counts)

### Monitoring & Alerting

- DataDog APM tracing on BigQuery import
- Email alerts on BigQuery import failures
- Error logging for stats recording failures
- Monitoring metrics:
    - Import duration
    - Records processed
    - Error counts
    - Missing data alerts

---

## Part 2: Classifieds Vertical Statistics Architecture

## Stats Types & Metrics

### 1. Listing-Level Metrics

### a. **Page Views (Detail Page Views)**

- **Sources**: Web (BigQuery), App (BigQuery), Memcache (real-time aggregate)
- **Storage**:
    - Daily breakdowns in MongoDB (60-day retention)
    - Aggregate counts in Memcache (persistent but can be cleared)
    - Historical in BigQuery tables
- **Granularity**: Per listing, per day

### b. **Impressions**

- **Standard Impressions**: Listings shown in standard search results
- **Featured Impressions**: Listings shown in featured/upgraded positions
- **Total Impressions**: Combined count
- **Sources**: BigQuery (Web + App analytics)
- **Aggregation**: By listing ID and date

### c. **Favorites/Hearts**

- **Event-Based**: User clicks favorite/heart button
- **Sources**: Web + App events tracked to BigQuery
- **Storage**: MongoDB (event counts), Favorites collection (active favorites)
- **Used For**: Engagement metrics, user interest tracking

### d. **Leads**

- **Types**:
    - Email Seller clicks
    - Text Seller clicks
    - Call Seller clicks
- **Sources**: BigQuery analytics events
- e. **Clicks**
- **Search Page Clicks**: Transitions from search results to detail pages
- **Featured vs Standard**: Tracked separately for upgrade effectiveness
- **Dealer Website Clicks**: For dealers with external websites

### 2. Member-Level Metrics

All the above metrics are also aggregated at the member (seller) level for:
- **Monthly reporting emails**
- **Dealer dashboard analytics**
- **Performance comparisons**
- **Package upgrade decisions**

### 3. Additional Metrics

- **Shares**: Social sharing events
- **Active Listings**: Current count of live listings
- **Active Listings Value**: Total $ value of active inventory
- **Search Page Interactions**: Impressions and clicks at search level

---

## Data Collection & Sources

### 1. **Google Analytics (Primary Source)**

**BigQuery Tables:**
- `classifieds_stats.WebDetailPageListingReport` - Web detail page views
- `classifieds_stats.AppDetailPageListingReport` - App detail page views

- `classifieds_stats.WebFeaturedStandardImpressionsClicks` - Web search impressions/clicks
- `classifieds_stats.AppFeaturedStandardImpressionsClicks` - App search impressions/clicks
- `classifieds_stats.WebEmailSellerListingReport` - Email seller events (web)
- `classifieds_stats.AppEmailSellerListingReport` - Email seller events (app)
- `classifieds_stats.WebUserFavoriteListingReport` - Favorite events (web)
- `classifieds_stats.AppUserFavoriteListingReport` - Favorite events (app)
- `classifieds_stats.WebCallSellerListingReport` - Call seller events (web)
- `classifieds_stats.AppCallSellerListingReport` - Call seller events (app)
- `classifieds_stats.WebTextSellerListingReport` - Text seller events (web)
- `classifieds_stats.AppTextSellerListingReport` - Text seller events (app)
- `classifieds_stats.WebVisitDealerWebsite` - Dealer website visits

**Data Flow:**
1. User interactions trigger Google Analytics events
2. GA exports to BigQuery daily (batched)
3. Raw event data lands in source tables
4. Processed into report tables with daily aggregations

### 2. **Direct Pageview Tracking (Memcache)**

**Implementation:**
- Location: `m-ksl-classifieds` and legacy `ksl-api3`
- Key Pattern: `slc-{listingId}-c`
- Increment: On every listing detail page load
- Purpose: Real-time aggregate view count

**Code Reference** (`StatsController.php`):

```php
public function getGdpViewsByAd($id, $increment=false) {
    $memd = DDM_Cache_Mcache::getInstance();
    $memkey = "slc-" . $id . '-c';
    $pageviews = $memd->get($memkey);
    if ($pageviews === false) {
        $pageviews = 1;
    }
    if ($increment) {
        $memd->set($memkey, ++$pageviews, 0);
    }
    return $this->_getResponse(['views' => $pageviews]);
}
```

**Characteristics:**
- **Immediate**: Updates on every page load
- **No TTL**: Set with expiration = 0 (persistent until cleared)
- **Volatile**: Can be lost if Memcache restarts or needs memory
- **Used In**: Listing detail pages, My Listings performance graphs

### 3. **Bandwidth Analytics**

**Purpose:** Track API calls at member level
**Storage:** MongoDB `generalStats` collection
**Import:** `BandwidthStatImport.php` command
**Stat Name:** `calls`**Origin:** `bandwidth`**Use Case:** Dealer feed/API usage monitoring

### 4. **Favorites Collection**

**Purpose:** Track active favorites (not just events)
**Storage:** MongoDB `generalFavorites` collection
**Data:** Current count of users who have favorited each listing
**Stat Name:** `userFavorite` (aggregate)

---

## Data Storage Architecture

### 1. **BigQuery (Google Cloud)**

**Project:** `ddm-dbi`

### Source Tables (Raw Analytics)

- Dataset: `classifieds_stats`
- Contains: Daily event aggregations from Google Analytics
- Retention: Long-term historical data
- Updated: Daily via GA export

### Reporting Tables (30-Day Rolling)

- **Managed By:** `reports-cron-classifieds-bq-tables` (Go service)
- **Tables:**
    - Member-level 30-day stats table
    - Listing-level 30-day stats table
- **Schema:**
    
    ```sql
    Date: DATEMember_Id: INT64
    Listing_Id: INT64
    Impressions: INT64
    Impressions_Standard: INT64
    Impressions_Featured: INT64
    Clicks: INT64
    DetailPageviews: INT64
    Favorites: INT64
    Shares: INT64
    Leads: INT64
    ```
    
- **Refresh:** Daily via cron job
- **Source Query:**
    
    ```sql
    SELECT ... FROM source_table
    WHERE Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
    ```
    

### 2. **MongoDB (classifieds database)**

### `generalStats` Collection

**Purpose:** Store daily stat breakdowns for quick querying

**Schema:**

```jsx
{
  _id: ObjectId,
  createTime: UTCDateTime,
  itemId: Int32,           // Listing ID or Member ID
  itemType: String,        // "listing" or "member"
  statDate: Int32,         // YYYYMMDD format
  statName: String,        // e.g., "detailPageViews", "emailSeller"
  statValue: Int32,        // Count for that day
  statOrigin: String,      // "bq-web", "bq-app", "bandwidth"
  deleteTime: UTCDateTime  // Auto-delete after 60 days
}
```

**Indexes:**
- `{itemType, itemId, statName, statOrigin, statDate}`
- Used for efficient queries by listing/member with date ranges

**Data Import:**
- **Command:** `BigQueryStatImport` (PHP)
- **Frequency:** Daily
- **Batch Size:** 5000 records per MongoDB insert
- **Reports Config:** `BigQueryConfig.php` - defines which BQ tables to import
- **Report Groups:**
- `monthlyEmail` - Stats for dealer monthly emails
- `myListings` - Stats shown in My Account

**Retention:** 60 days
- Each record has `deleteTime` set to 60 days from `statDate`
- MongoDB TTL index handles automatic cleanup

### `generalFavorites` Collection

**Purpose:** Track which users favorited which listings

**Schema:**

```jsx
{
  _id: ObjectId,
  listingId: Int32,
  memberId: Int32,
  favoriteTime: UTCDateTime,
  // ... other metadata
}
```

**Used For:**
- Current favorite count per listing
- Aggregate stat: `userFavorite`

### `generalDealer` Collection

**Purpose:** Dealer/member information for monthly stat emails

**Fields:**
- Member ID
- Email addresses
- Dealer settings
- Monthly email opt-in status

### 3. **Memcache**

**Purpose:** Real-time aggregate statistics

**Key Patterns:**
- `slc-{listingId}-c` - Total pageview count for a listing

**Characteristics:**
- Fast read/write
- No persistence guarantee
- Used for “total views” displays
- Complementary to BigQuery daily breakdowns

---

## Data Processing Pipeline

### Pipeline 1: BigQuery → MongoDB (Legacy, still active)

**Service:** `m-ksl-classifieds-api` PHP commands

**Flow:**
1. **Cron Trigger:** Daily execution of `BigQueryStatImport` command
2. **Report Selection:**
- Can run specific reports, report groups, or all reports
- Groups: `monthlyEmail`, `myListings`
3. **BigQuery Query:**
- Queries predefined in `BigQueryConfig.php`
- Each query targets a specific stat type (e.g., detail page views)
- Parameterized with `{REPORTDATE}` placeholder
4. **Data Processing:**
- Fetches up to 10,000 results from BigQuery
- Aggregates by `itemId` (listing or member)
- Chunks into batches of 5000 for memory management
5. **MongoDB Insert:**
- Bulk `insertMany` operations
- Unordered inserts (continue on duplicate key errors)
- Sets `deleteTime` to 60 days from stat date
6. **Memory Management:**
- Explicit `gc_collect_cycles()` after each report
- Sleep intervals between batches and reports

**Command Usage:**

```bash
# Import specific report for a date
bin/console import:stats:bigQuery -r DetailPageView_WebListingReport -d 2024-01-15

# Import all reports in a group
bin/console import:stats:bigQuery -g myListings -d 2024-01-15

# Import all reports for yesterday (default)
bin/console import:stats:bigQuery --all

# List available reports
bin/console import:stats:bigQuery --listReports

# List available groups  
bin/console import:stats:bigQuery --listGroups
```

**Reports Configuration Example** (`BigQueryConfig.php`):

```php
'DetailPageView_WebListingReport' => [
    'desc' => 'Detail Page Views [Web][Listing]',
    'groups' => [BigQueryConfig::GROUP_MY_LISTINGS],
    'query' => "
        SELECT listingId as itemId, SUM(Pageviews) as statValue
        FROM `classifieds_stats.WebDetailPageListingReport`
        WHERE `date` = '{REPORTDATE}'
        GROUP BY itemId
    ",
    'saveConfig' => [
        'itemType' => self::ITEM_TYPE_LISTING,
        'statName' => 'detailPageViews',
        'statOrigin' => self::STAT_ORIGIN_BQ_WEB,
    ],
],
```

### Pipeline 2: BigQuery 30-Day Tables Refresh (Modern)

**Service:** `marketplace-backend/apps/reports/services/reports-cron-classifieds-bq-tables`

**Language:** Go

**Flow:**
1. **Cron Trigger:** Daily scheduled job (Kubernetes CronJob)
2. **Configuration:**
- Source table: Classifieds inventory table with all metrics
- Destination dataset: Reports dataset
- Destination tables:
- Member-level 30-day stats
- Listing-level 30-day stats
3. **BigQuery Query:**

```sql
SELECT
  f.Date AS Date,
  CAST(f.Seller_Id AS INT64) AS Member_Id,
  CAST(f.Listing_Id AS INT64) AS Listing_Id,
  f.Impressions AS Impressions,
  f.Impressions_Standard AS Impressions_Standard,
  f.Impressions_Featured AS Impressions_Featured,
  f.Clicks AS Clicks,
  f.DetailPageviews AS DetailPageviews,
  f.Favorites AS Favorites,
  f.Shares AS Shares,
  f.Leads AS Leads
FROM source_table AS f
WHERE f.Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
```

**Architecture:**
- Domain-driven design
- Clean separation: Domain → Repository → Infrastructure
- Testable with BigQuery client mocks
- Proper error handling and tracing

### Pipeline 4 (obsolete?): Bandwidth Stats Import

> Currently we migrate from Bandwidth to Callrail
> 

**Service:** `m-ksl-classifieds-api` - `BandwidthStatImport` command

**Purpose:** Import API/bandwidth usage stats for members

**Source:** External bandwidth/API tracking system

**Destination:** MongoDB `generalStats` collection
- `statName`: “calls”
- `statOrigin`: “bandwidth”

---

## Data Retrieval & APIs

### 1. **Classifieds API (m-ksl-classifieds-api)**

**Endpoint:** `GET /stats`

**Controller:** `StatController::getStats()`

**Purpose:** Primary API for retrieving listing/member stats

**Query Parameters:**
- `itemType` (required): “listing” or “member”
- `itemIdArray` (required): Comma-separated IDs
- `dailyStatNameArray` (optional): Filter to specific stats
- Empty = all daily stats
- Null = no daily stats
- `dailyStatOriginArray` (optional): “bq-web”, “bq-app”, “bandwidth”
- `dailyStartDate` (optional): YYYYMMDD or unix timestamp
- `dailyEndDate` (optional): YYYYMMDD or unix timestamp
- `dailyStatReturnArray` (optional): “date” (default), “aggregate”
- `aggregateStatNameArray` (optional): “detailPageViews”, “userFavorite”

**Response Structure:**

```json
  "data": {
    "dailyStats": {
      "12345": {
        "detailPageViews_bq-web": {
          "name": "detailPageViews",
          "origin": "bq-web",
          "dateArray": {
            "20240115": 45,
            "20240116": 52
          },
          "aggregateCount": 97
        }
      }
    },
    "aggregateStats": {
      "12345": {
        "detailPageViews": 1523,
        "userFavorite": 42
      }
    }
  }
}
```

**Data Sources:**
- **Daily Stats:** MongoDB `generalStats` collection
- **Aggregate Stats:**
- `detailPageViews`: Memcache (key: `slc-{listingId}-c`)
- `userFavorite`: MongoDB `generalFavorites` collection (count query)

**Implementation:**

```php
public function getStats(Request $request) {
    // Parse and validate parameters
    $itemType = $request->query->get('itemType');
    $itemIdArray = $request->query->get('itemIdArray');
    
    // Fetch daily stats from MongoDB
    if ($dailyStatNameArray !== null) {
        $returnArray['dailyStats'] = 
            $this->generalStatsCollection->getStats(
                $itemType, $itemIdArray, $dailyStatNameArray,
                $dailyStatOriginArray, $dailyStartDate, 
                $dailyEndDate, $dailyStatReturnArray
            );
    }
    
    // Fetch aggregate stats from Memcache/Mongo
    if ($aggregateStatNameArray !== null) {
        $returnArray['aggregateStats'] = 
            $this->statHelper->getAggregateStats(
                $itemType, $itemIdArray, $aggregateStatNameArray
            );
    }
    
    return $this->json(['data' => $returnArray]);
}
```

**Authentication:** Nonce-based (`NonceAuthenticatedInterface`)

### 2. **Reports HTTP REST API (marketplace-backend)**

**Service:** `marketplace-backend/apps/reports/services/reports-http-rest`

**Endpoint:** GraphQL via HTTP

**Purpose:** Fetch 30-day listing stats from BigQuery

**Query:** `GetClassifieds30DaysStatsByMember(memberId)`

**Response Structure:**

```json
{
  "totalImpressions": 15420,
  "totalViews": 8234,
  "totalFavorites": 234,
  "totalLeads": 156,
  "byDate": [
    {
      "date": "2024-01-15",
      "standardImpressions": 320,
      "featuredImpressions": 180,
      "views": 245,
      "favorites": 12,
      "leads": 8
    }
  ]
}
```

**Caching:**
- **Layer:** Memcache
- **Key Pattern:** Based on vertical, memberId, listingId
- **TTL:** 12 hours
- **Purpose:** Reduce BigQuery query costs

**Implementation** (`ListingStatsService.go`):

```go
func (s *ListingStatsService) FetchListingStats(
    ctx context.Context, 
    vertical string,
    memberId int, 
    listingId int,
) (*ListingStats, error) {
    // Try cache first
    cacheKey, _ := memcache.GetAllListingStatsKey(
        vertical, memberIdStr, listingIdStr
    )
    cachedData := s.mc.GetValue(cacheKey)
    if cachedData != nil {
        return cachedData, nil
    }
    
    // Query BigQuery
    if listingId > 0 {
        stats := s.ls_repo.GetClassifieds30DaysStatsByListing(
            ctx, listingId
        )
    } else {
        stats := s.ls_repo.GetClassifieds30DaysStatsByMember(
            ctx, memberId
        )
    }
    
    // Cache result
    s.mc.SetValue(cacheKey, stats, 12*60*60)
    
    return stats, nil
}
```

**BigQuery Query:**

```sql
SELECT  COALESCE(SUM(r.Impressions), 0) as totalImpressions,
  COALESCE(SUM(r.DetailPageviews), 0) as totalViews,
  COALESCE(SUM(r.Favorites), 0) as totalFavorites,
  COALESCE(SUM(r.Leads), 0) as totalLeads,
  (
    SELECT ARRAY(
      SELECT AS STRUCT
        s.Date,
        COALESCE(SUM(s.Impressions_Standard), 0) as standardImpressions,
        COALESCE(SUM(s.Impressions_Featured), 0) as featuredImpressions,
        COALESCE(SUM(s.DetailPageviews), 0) as views,
        COALESCE(SUM(s.Favorites), 0) as favorites,
        COALESCE(SUM(s.Leads), 0) as leads
      FROM table as s
      WHERE s.Member_Id = @member_id
      GROUP BY s.Date    )
  ) as byDate
FROM table as r
WHERE r.Member_Id = @member_id
```

**Authentication:** Member token validation

### 3. **GraphQL API (marketplace-graphql)**

**Schema:** `query.reporting.graphqls`

**Queries:**

### `getListingsReport`

```graphql
getListingsReport(
  listingType: [ListingType!]!
  listingId: String
): ListingsReport!
```

**Response Type:**

```graphql
type ListingsReport {
  totals: ListingsTotals!
  byDate: [ListingsByDate!]!
}

type ListingsTotals {
  activeListings: Int!
  activeListingsValue: Float!
  impressions: Int!
  views: Int!
  favorites: Int!
  leads: Int!
}

type ListingsByDate {
  date: Date!
  standardImpressions: Int!
  featuredImpressions: Int!
  views: Int!
  favorites: Int!
  leads: Int!
}
```

**Data Flow:**
1. GraphQL resolver extracts JWT member ID
2. Calls `reports-http-rest` service
3. Service queries BigQuery (with memcache)
4. Returns formatted response

### `getAdvancedStatsGroupedByDate`

```graphql
getAdvancedStatsGroupedByDate(
  vertical: BusinessVertical!
  start: Int!
  end: Int!
  memberId: Int
  additionalFilters: AdvancedStatsAdditionalFilters
): AdvancedStatsGroupedByDate!
```

**Purpose:** Detailed stats with custom date ranges and filters

### `getListingsListReport`

```graphql
getListingsListReport(
  listingType: ListingType!
  listingId: [String!]!
): [ListingsReport]!
```

**Purpose:** Batch fetch stats for multiple specific listings

### 4. **Legacy KSL API (ksl-api3)**

**Endpoint:** `/classifieds/general/stats/getStats`

**Similar to Classifieds API but older implementation**

**Endpoint:** `/classifieds/general/stats/getGdpViewsByAd`

**Purpose:** Get/increment pageview count for a listing

**Parameters:**
- `id`: Listing ID
- `increment`: Boolean (whether to increment the counter)

**Returns:**

```json
{
  "response": {
    "views": 1523
  }
}
```

**Used By:** Detail page views in legacy classifieds app

---

## Frontend Display & User Experience

### 1. **My Account v2 (m-ksl-myaccount-v2)**

**Purpose:** Primary interface for users to view their listing performance

### **Performance Graphs**

**Components:**
- `PerformanceGraph.tsx` - Base graph component
- `GeneralsPerformance.tsx` - Service for fetching classifieds stats
- `AnalyticsReportDash.tsx` - Dashboard with charts
- `StatCard.tsx` - Individual metric cards

**Data Flow:**
1. **User Opens Listing:** Listing card in My Account
2. **Click “Performance”:** Opens performance modal/section
3. **API Call:**

```tsx
GET /api/v1/listings/performance
// or
POST /api/v1/analytics-report/get-listings-report
```

4. **Backend Calls:**
- For Classifieds: `GET https://classifieds-api.ksl.com/stats`
- Fetches both daily and aggregate stats

5. **Data Transformation:**

```tsx
// GeneralsPerformance.ts
const bqData = /* daily stats by date */
const memcacheData = /* aggregate totals */

const combinedData = {
  id: listingId,
  type: LISTING_TYPE.Classifieds,
  attributes: {
    performanceData: {
      byDay: bqData.byDay, // Array of {date, views, favorites, emails}
      totals: {
        views: memcacheData.views,
        favorites: memcacheData.favorites,
        emails: bqData.totals.emails
      }
    }
  }
}
```

6. **Graph Rendering:**

- Line charts showing daily trends
- Stat cards showing totals
- Charts.js or similar library

**Metrics Displayed:**

- **Views:** Total pageviews (from Memcache)
- **Favorites:** Current favorite count
- **Emails:** Email seller clicks (from BigQuery)
- **By-Day Breakdown:** Line graphs for each metric over time

**Example UI:**

```
┌─────────────────────────────────────────┐
│  Listing #12345 - Performance           │
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  │
│  │ Views   │  │Favorites│  │ Emails  │  │
│  │  1,523  │  │   42    │  │   18    │  │
│  └─────────┘  └─────────┘  └─────────┘  │
│                                         │
│  Performance Over Time                  │
│  ┌────────────────────────────────────┐ │
│  │        /\      /\                  │ │
│  │       /  \    /  \    /\           │ │
│  │  /\  /    \__/    \__/  \__        │ │
│  │ /  \/                      \_      │ │
│  └────────────────────────────────────┘ │
│   Jan 1  Jan 8  Jan 15  Jan 22  Jan 29  │
│                                         │
│  Legend: — Views  — Favorites — Emails  │
└─────────────────────────────────────────┘
```

### **Analytics Dashboard (Dealers)**

**Component:** `AnalyticsDash/AnalyticsReportDash.tsx`

**Purpose:** High-level dashboard for dealers with multiple listings

**Features:**
- Aggregate stats across all listings
- Date range selector
- Export/download capabilities
- Drill-down into specific listings

**Data Source:**

```graphql
query getListingsReport($listingType: [ListingType!]!) {
  getListingsReport(listingType: $listingType) {
    totals {
      activeListings
      activeListingsValue
      impressions
      views
      favorites
      leads
    }
    byDate {
      date
      standardImpressions
      featuredImpressions
      views
      favorites
      leads
    }
  }
}
```

**GraphQL Call:**

```tsx
// pages/api/v1/analytics-report/get-listings-report.ts
const response = await fetch(DDM_GRAPHQL_MARKETPLACE_URL, {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${accessToken}`,
  },
  body: JSON.stringify({
    query: getListingsReport,
    variables: { listingType: ['CLASSIFIED'] }
  })
});
```

**Display:**
- Total active listings count
- Total inventory value
- 30-day trends
- Comparison charts (standard vs featured impressions)

### 2. **(legacy) Classifieds Frontend (m-ksl-classifieds)**

### **Detail Page View Counter**

**Location:** Listing detail page

**Display:** “Views: 1,523” near listing title or metadata

**Implementation:**

```jsx
// On page load
fetch('/api/stats/getGdpViewsByAd?id=12345&increment=true')
  .then(res => res.json())
  .then(data => {
    document.getElementById('view-count').textContent = 
      `Views: ${data.response.views.toLocaleString()}`;
  });
```

**Server-Side:**

```php
// IndexController.php or ListingController.php
$statsResponse = $this->apiConnector->fetch(
    '/classifieds/general/stats/getGdpViewsByAd',
    ['id' => $listingId, 'increment' => true]
);
```

**Characteristics:**
- Increments on every page load (including bots/crawlers)
- Shows aggregate count from Memcache
- No breakdown or details on public page

### 3. **Marketplace Frontend (marketplace-frontend)**

**Purpose:** Next.js-based marketplace pages

**Analytics Integration:**
- `packages/analytics` - DataLayer provider and GTM integration
- Event tracking for impressions, clicks, favorites
- Feeds data to Google Analytics → BigQuery

**Components:**
- Search results impression tracking
- Listing click tracking
- Favorite button interaction tracking

**DataLayer Events:**

```tsx
// Example event structure
{
  event: 'listing_view',
  listing_id: '12345',
  vertical: 'classifieds',
  page_type: 'detail',
  seller_id: '67890'
}
```

---

## Reporting Systems

### 1. **Monthly Dealer Stat Emails**

**Purpose:** Automated monthly performance reports sent to dealers

**Service:** `m-ksl-classifieds-api` - `DealerMonthlyStatEmail` command

**Trigger:** Monthly cron job (typically 1st of each month)

**Flow:**
1. **Fetch Dealers:**
- Query MongoDB `generalDealer` collection
- Filter for dealers with:
- Active listings in previous month
- Valid email address
- Opt-in to monthly emails (if applicable)
2. **Fetch Stats:**
- Query MongoDB `generalStats` for previous month date range
- Stat types:
- `detailPageViews` (web + app)
- `searchPageFeaturedClicks`
- `searchPageStandardClicks`
- `callSeller`
- `emailSeller`
- `textSeller`
- `userFavorite`
- `dealerWebsite`
- Group by member ID
- Aggregate totals and daily breakdowns
3. **Fetch Listing Data:**
- Get listing titles, images, categories
- Calculate inventory value
- Get package/upgrade information
4. **Generate Email:**
- Template: Twig templates in `templates/emails/`
- Includes:
- Summary stats (totals)
- Top performing listings
- Comparison to previous month (if available)
- Charts/graphs (embedded images)
- Call-to-action for upgrades
5. **Send via Email Service:**
- Mandrill/SendGrid integration
- Track email opens/clicks

**Command Usage:**

```bash
# Send to all eligible dealers for last month
bin/console email:dealer:monthlyStats --run

# Send to specific dealers
bin/console email:dealer:monthlyStats --run --memberId=12345,67890

# Custom date range
bin/console email:dealer:monthlyStats --run \
  --startDate=2024-01-01 --endDate=2024-01-31

# Test mode (override email)
bin/console email:dealer:monthlyStats --run --toEmail=test@example.com
```

**Email Template Structure:**

```
Subject: Your January 2024 KSL Classifieds Performance Report

Hello [Dealer Name],

Here's how your listings performed in January 2024:

┌──────────────────────────────┐
│  Monthly Summary             │
├──────────────────────────────┤
│  Detail Page Views:   8,234  │
│  Search Impressions: 45,123  │
│  Favorites:             234  │
│  Leads:                 156  │
│  - Email:                98  │
│  - Call:                 42  │
│  - Text:                 16  │
└──────────────────────────────┘

Top Performing Listings:
1. 2020 Toyota Camry - 1,234 views, 45 leads
2. 2019 Honda Accord - 987 views, 32 leads
3. ...

[Chart: Daily Views Over Time]

Upgrade Your Listings
Featured listings receive 3x more impressions!
[CTA Button: Upgrade Now]

---
Questions? Contact us at ...
```

### 2. **Pubsub Monthly Email (Modern)**

**Service:** `marketplace-backend/apps/reports/services/reports-ps-monthly-email`

**Purpose:** Event-driven monthly report generation (newer architecture)

**Trigger:** Pubsub message published on monthly schedule

**Handler:** `handler/reports.go`

**Flow:**
1. **Receive Pubsub Message:**
- Topic: Dealer monthly report request
- Payload: `{ "memberId": 12345, "startDate": "2024-01-01", "endDate": "2024-01-31" }`
2. **Domain Service:**
- `domain/listingstats.go` - Fetch stats from BigQuery
- `domain/listingsummary.go` - Fetch listing metadata
- `domain/interservice.go` - Call other services (email, inventory)
3. **Generate Report:**
- Aggregate stats by member
- Format data for email template
4. **Send Email:**
- Call email service API
- Store sent status in database

**Benefits:**
- Asynchronous processing
- Scalable (parallel processing)
- Retry logic built-in
- Better observability

### 3. **On-Demand Reports (GraphQL)**

**Endpoint:** GraphQL queries in My Account and admin tools

**Queries:**
- `getListingsReport` - 30-day snapshot
- `getAdvancedStatsGroupedByDate` - Custom date range
- `getAdvancedStatsGroupedByListing` - Per-listing breakdown

**Use Cases:**
- Dealers checking performance in My Account dashboard
- Support team investigating dealer questions
- Sales team demonstrating value during upsell

**Features:**
- Real-time data (with caching)
- Flexible date ranges
- Multiple groupings (by date, by listing)
- Filterable by vertical, category, package

---

## Architecture Flow Diagrams

### High-Level Data Flow

```
┌───────────────────────────────────────────────────────────────────┐
│                          Data Sources                             │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │   User       │  │  Google      │  │  Bandwidth   │             │
│  │  Interactions│  │  Analytics   │  │   Tracking   │             │
│  │              │  │              │  │              │             │
│  │ • Page views │  │ • Events     │  │ • API calls  │             │
│  │ • Clicks     │  │ • Pageviews  │  │ • Feed usage │             │
│  │ • Favorites  │  │ • Impressions│  │              │             │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘             │
│         │                 │                 │                     │
└─────────┼─────────────────┼─────────────────┼─────────────────────┘
          │                 │                 │
          ▼                 ▼                 ▼
┌───────────────────────────────────────────────────────────────────┐
│                    Ingestion & Storage                            │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐       ┌──────────────┐       ┌──────────────┐   │
│  │  Memcache    │       │   BigQuery   │       │   MongoDB    │   │
│  │              │       │              │       │              │   │
│  │ • Real-time  │       │ • Historical │       │ • Daily      │   │
│  │   pageviews  │◄──────│   analytics  │──────►│   breakdowns │   │
│  │ • Aggregate  │       │ • 30-day     │       │ • 60-day     │   │
│  │   totals     │       │   tables     │       │   retention  │   │
│  └──────────────┘       └──────────────┘       └──────────────┘   │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
          │                 │                 │
          │                 │                 │
          └─────────┬───────┴─────────────────┘
                    ▼
┌───────────────────────────────────────────────────────────────────┐
│                     Processing Layer                              │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌───────────────────┐  ┌───────────────────┐  ┌──────────────┐   │
│  │ BigQueryStatImport│  │  BQ Tables Cron   │  │ Cars Stats   │   │
│  │                   │  │                   │  │   Cron       │   │
│  │ PHP Command       │  │ Go Service        │  │              │   │
│  │ • Daily import    │  │ • 30-day refresh  │  │ Go Service   │   │
│  │ • BQ → MongoDB    │  │ • Member/Listing  │  │ • Dealer     │   │
│  │ • 16 report types │  │   tables          │  │   aggregates │   │
│  └───────────────────┘  └───────────────────┘  └──────────────┘   │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
          │                 │                 │
          │                 │                 │
          └─────────┬───────┴─────────────────┘
                    ▼
┌───────────────────────────────────────────────────────────────────┐
│                        API Layer                                  │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │ Classifieds  │  │   Reports    │  │   GraphQL    │             │
│  │     API      │  │   HTTP API   │  │     API      │             │
│  │              │  │              │  │              │             │
│  │ /stats       │  │ BigQuery     │  │ getListings  │             │
│  │ endpoint     │  │ queries      │  │   Report     │             │
│  │              │  │ + Memcache   │  │              │             │
│  └──────────────┘  └──────────────┘  └──────────────┘             │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
          │                 │                 │
          │                 │                 │
          └─────────┬───────┴─────────────────┘
                    ▼
┌───────────────────────────────────────────────────────────────────┐
│                    Presentation Layer                             │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │  My Account  │  │ Detail Pages │  │ Monthly      │             │
│  │  Dashboard   │  │              │  │ Emails       │             │
│  │              │  │ • View count │  │              │             │
│  │ • Performance│  │ • Public     │  │ • PDF report │             │
│  │   graphs     │  │   display    │  │ • Charts     │             │
│  │ • Analytics  │  │              │  │ • Top lists  │             │
│  └──────────────┘  └──────────────┘  └──────────────┘             │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

### Detailed Stats Collection Flow

```
User Action                    Event Tracking                Storage
───────────                    ──────────────                ───────

View Listing Detail Page
        │
        ├─────────────────────► Increment Memcache ─────────► slc-{id}-c
        │                       (real-time)
        │
        ├─────────────────────► Google Analytics Event ─────► BigQuery
        │                       (batched daily)               (next day)
        │                                                      │
        │                                                      ▼
        │                                              WebDetailPageListing
        │                                                    Report
        │                                                      │
        │                                                      ▼
        │                                              BigQueryStatImport
        │                                                   command
        │                                                      │
        │                                                      ▼
        │                                              MongoDB generalStats
        │                                              statName: detailPageViews
        │                                              statOrigin: bq-web
        │
Click Favorite Button
        │
        ├─────────────────────► Insert Favorite Record ─────► MongoDB
        │                       (immediate)                   generalFavorites
        │
        ├─────────────────────► Google Analytics Event ─────► BigQuery
        │                       (batched daily)               (next day)
        │                                                      │
        │                                                      ▼
        │                                              WebUserFavorite
        │                                                 ListingReport
        │                                                      │
        │                                                      ▼
        │                                              MongoDB generalStats
        │                                              statName: userFavorite
        │                                              statOrigin: bq-web
        │
Click Email Seller
        │
        ├─────────────────────► Send Email ─────────────────► Email Service
        │                       (immediate)
        │
        ├─────────────────────► Google Analytics Event ─────► BigQuery
        │                       (batched daily)               (next day)
        │                                                      │
        │                                                      ▼
        │                                              WebEmailSellerListing
        │                                                    Report
        │                                                      │
        │                                                      ▼
        │                                              MongoDB generalStats
        │                                              statName: emailSeller
        │                                              statOrigin: bq-web
        │
View Search Results
        │
        ├─────────────────────► Google Analytics ──────────► BigQuery
        │                       Impressions Event             (next day)
        │                                                      │
        │                                                      ▼
        │                                              WebFeaturedStandard
        │                                              ImpressionsClicks
        │                                                      │
        │                                                      ▼
        │                                              MongoDB generalStats
        │                                              statName: searchPage
        │                                                FeaturedClicks
        │                                              statOrigin: bq-web
```

### Stats Query Flow (User Viewing Performance)

```
User                My Account           API Gateway         Classifieds API
                    Frontend
  │                    │                     │                     │
  ├─ View Performance ─►                     │                     │
  │    for Listing     │                     │                     │
  │                    │                     │                     │
  │                    ├──── GET /api/v1 ────►                     │
  │                    │   /listings/        │                     │
  │                    │    performance      │                     │
  │                    │   ?ids=12345        │                     │
  │                    │                     │                     │
  │                    │                     ├─── GET /stats ──────►
  │                    │                     │  ?itemType=listing  │
  │                    │                     │  &itemIdArray=12345 │
  │                    │                     │  &dailyStatNameArray│
  │                    │                     │    =detailPageViews,│
  │                    │                     │     emailSeller     │
  │                    │                     │  &aggregateStatName │
  │                    │                     │    Array=detail     │
  │                    │                     │    PageViews,       │
  │                    │                     │    userFavorite     │
  │                    │                     │                     │
  │                    │                     │                     ├──┐
  │                    │                     │                     │  │
  │                    │                     │          Query MongoDB │
  │                    │                     │        generalStats for│
  │                    │                     │         daily breakdown│
  │                    │                     │                     │◄─┘
  │                    │                     │                     │
  │                    │                     │                     ├──┐
  │                    │                     │                     │  │
  │                    │                     │          Query Memcache│
  │                    │                     │        slc-12345-c for │
  │                    │                     │         aggregate views│
  │                    │                     │                     │◄─┘
  │                    │                     │                     │
  │                    │                     │                     ├──┐
  │                    │                     │                     │  │
  │                    │                     │     Query MongoDB   │  │
  │                    │                     │   generalFavorites  │  │
  │                    │                     │   for favorite count│  │
  │                    │                     │                     │◄─┘
  │                    │                     │                     │
  │                    │                     │◄── JSON Response ───┤
  │                    │                     │   {                 │
  │                    │                     │     dailyStats: {   │
  │                    │                     │       12345: {...}  │
  │                    │                     │     },              │
  │                    │                     │     aggregateStats: │
  │                    │                     │       {             │
  │                    │                     │         12345: {    │
  │                    │                     │           detail    │
  │                    │                     │           PageViews │
  │                    │                     │           : 1523    │
  │                    │                     │         }           │
  │                    │                     │       }             │
  │                    │                     │   }                 │
  │                    │                     │                     │
  │                    │◄─── JSON Response ──┤                     │
  │                    │  (transformed)      │                     │
  │                    │                     │                     │
  │◄─── Render Chart ──┤                     │                     │
  │     • Totals       │                     │                     │
  │     • Line Graph   │                     │                     │
  │     • Date Range   │                     │                     │
  │                    │                     │                     │
```

---

## Repository Responsibilities

### 1. **m-ksl-classifieds** (legacy)

**Purpose:** Main classifieds web application (PHP/Zend)

**Stats Responsibilities:**
- Increment Memcache pageview counter on detail page loads
- Trigger Google Analytics events for user interactions
- Display view counts on detail pages
- Legacy stats API integration

**Key Files:**
- `application/controllers/IndexController.php` - Homepage, initializes GTM
- `application/controllers/ListingController.php` - Detail pages, pageview tracking
- `library/GtmDataLayer.php` - DataLayer for Google Tag Manager
- `ksl-api3/public_html/classifieds/general/api/controllers/StatsController.php`

### 2. **m-ksl-classifieds-api**

**Purpose:** Symfony-based API for classifieds data and stats

**Stats Responsibilities:**
- Primary stats API endpoint (`/stats`)
- BigQuery → MongoDB import commands
- Bandwidth stats import
- Monthly dealer stat email generation
- Stats aggregation and formatting

**Key Files:**
- `src/Controller/StatController.php` - HTTP API endpoint
- `src/Helper/StatHelper.php` - Aggregate stats from Memcache/Mongo
- `src/Db/Mongo/GeneralStatsCollection.php` - MongoDB queries
- `src/Command/BigQueryStatImport.php` - Daily BQ import
- `src/Command/BandwidthStatImport.php` - Bandwidth import
- `src/Command/DealerMonthlyStatEmail.php` - Monthly emails
- `src/Command/Config/BigQueryConfig.php` - Report definitions

### 3. **m-ksl-myaccount-v2**

**Purpose:** Next.js user account dashboard

**Stats Responsibilities:**
- Display listing performance graphs
- Analytics dashboard for dealers
- Aggregate reporting across multiple listings
- Export/download capabilities

**Key Files:**
- `services/ListingPerformance/GeneralsPerformance.ts` - Fetch classifieds stats
- `services/ListingPerformance/CarsPerformance.ts` - Fetch cars stats
- `components/Listing/PerformanceGraph/` - Graph components
- `components/Dashboard/AnalyticsDash/` - Dashboard components
- `pages/api/v1/listings/performance.ts` - Next.js API route
- `pages/api/v1/analytics-report/get-listings-report.ts` - GraphQL proxy
- `graphql-queries/analytics-report/index.ts` - GraphQL queries
- `utils/analyticsData.ts` - Data transformation

### 4. **marketplace-graphql**

**Purpose:** Go-based GraphQL API gateway

**Stats Responsibilities:**
- GraphQL queries for listing reports
- Advanced stats queries with filtering
- Aggregate stats across verticals
- JWT-based member authentication

**Key Files:**
- `graph/schema/query.reporting.graphqls` - GraphQL schema definitions
- `graph/queryresolvers/` - Query resolvers (likely)
- GraphQL resolver implementation (not shown in grep results)

### 5. **marketplace-frontend**

**Purpose:** Next.js marketplace application

**Stats Responsibilities:**
- Google Analytics event tracking
- DataLayer management
- Impression tracking on search results
- Click tracking on listings
- Favorite button interactions

**Key Files:**
- `packages/analytics/` - Analytics package
- `DataLayerProvider.tsx` - Context provider
- `TagManager.tsx` - GTM integration
- `hooks/` - Analytics hooks
- `utils/` - Helper functions
- `apps/ksl-marketplace/app/listing/[id]/analytics/` - Listing page analytics
- `apps/ksl-marketplace/services/favorites/` - Favorite tracking

### 6. **marketplace-backend**

**Purpose:** Go microservices for marketplace operations

**Stats Responsibilities:**
- BigQuery 30-day tables refresh (cron)
- Cars dealer stats aggregation (cron)
- Reports HTTP REST API (queries BigQuery)
- Monthly email pubsub handler
- Listing stats retrieval with caching

**Key Services:**

### `listing-cron-stats`

- **Path:** `apps/listing/services/listing-cron-stats/`
- **Purpose:** Aggregate car dealer stats
- **Files:**
    - `app.go` - Main application setup
    - `model/bigquery.go` - BigQuery client and queries
    - `model/kslapi/` - KSL API integration

### `reports-cron-classifieds-bq-tables`

- **Path:** `apps/reports/services/reports-cron-classifieds-bq-tables/`
- **Purpose:** Refresh 30-day BigQuery tables
- **Files:**
    - `app.go` - Application setup
    - `config.go` - Environment configuration
    - `domain/reports.go` - Business logic
    - `infrastructure/bigquery/bigquery_repo.go` - BigQuery operations

### `reports-http-rest`

- **Path:** `apps/reports/services/reports-http-rest/`
- **Purpose:** HTTP API for fetching stats
- **Files:**
    - `app.go` - Server setup
    - `routes.go` - HTTP routes
    - `handler/reports.go` - HTTP handlers
    - `domain/listing-stats/service/listing-stats.go` - Business logic
    - `infrastructure/bigquery/listingstats_repo.go` - BigQuery queries
    - `infrastructure/memcache/memcache.go` - Caching layer

### `reports-ps-monthly-email`

- **Path:** `apps/reports/services/reports-ps-monthly-email/`
- **Purpose:** Pubsub-triggered monthly emails
- **Files:**
    - `app.go` - Pubsub subscriber setup
    - `handler/reports.go` - Message handler
    - `domain/listingstats.go` - Stats fetching
    - `domain/listingsummary.go` - Listing metadata
    - `domain/interservice.go` - Service communication

---

## Key Technologies

### Storage

- **BigQuery**: Google Cloud data warehouse
    - Project: `ddm-dbi`
    - Datasets: `classifieds_stats`, `cars_stats`
    - SQL queries, partitioned tables, scheduled queries
- **MongoDB**: Document database
    - Database: `classifieds`
    - Collections: `generalStats`, `generalFavorites`, `generalDealer`
    - Replica set for high availability
    - TTL indexes for automatic data expiration
- **Memcache**: In-memory key-value store
    - Real-time aggregate counters
    - No persistence guarantee
    - Fast read/write operations

### Backend Languages & Frameworks

- **PHP 7.4+**:
    - Symfony 5 (`m-ksl-classifieds-api`)
    - Zend Framework 1 (`m-ksl-classifieds`)
    - Composer for dependencies
- **Go 1.21+**:
    - `marketplace-backend` microservices
    - Standard library + external packages
    - Domain-driven design patterns
- **Node.js / TypeScript**:
    - Next.js 13+ (`m-ksl-myaccount-v2`, `marketplace-frontend`)
    - React 18 for UI components

### Frontend

- **Next.js**: React framework with SSR/SSG
- **React**: Component library
- **TypeScript**: Type-safe JavaScript
- **Charts.js** (or similar): Graph rendering
- **TailwindCSS**: Styling

### APIs & Integration

- **GraphQL**: Query language for APIs
    - `marketplace-graphql` server
    - Type-safe queries and mutations
- **REST**: Traditional HTTP APIs
    - `/stats` endpoint
    - JSON responses
- **Pubsub**: Google Cloud Pub/Sub
    - Event-driven architecture
    - Asynchronous processing

### Analytics & Tracking

- **Google Analytics 4**: Event tracking
- **Google Tag Manager**: Tag management
- **DataLayer**: Structured event data
- **BigQuery Export**: GA4 → BigQuery daily export

### DevOps & Infrastructure

- **Docker**: Containerization
- **Kubernetes**: Orchestration (likely GKE)
- **CronJobs**: Scheduled tasks
- **Cloud Build**: CI/CD (likely)
- **DataDog**: Observability (tracing, logging, metrics)

### Data Processing

- **Batch Processing**: Daily cron jobs
- **Stream Processing**: Pubsub handlers
- **ETL Pipelines**: BigQuery → MongoDB, BigQuery → BigQuery

---

## Data Retention Policies

### BigQuery

**Source Tables (Raw Analytics):**
- **Retention:** Long-term (years)
- **Purpose:** Historical analysis, compliance
- **Cost Optimization:** Partitioned by date, older partitions archived

**Reporting Tables (30-Day Rolling):**
- **Retention:** 30 days (rolling window)
- **Refresh:** Daily (full truncate + reload)
- **Purpose:** Fast queries for My Account and APIs
- **Tables:**
- Member-level 30-day stats
- Listing-level 30-day stats

**Cars Stats Tables:**
- **`ListingPageViews`:** Current snapshot (truncate + refresh)
- **`DealerPageViewsByDate`:** Last 61 days (truncate + refresh)

### MongoDB

**`generalStats` Collection:**
- **Retention:** 60 days
- **Mechanism:** TTL index on `deleteTime` field
- **deleteTime Calculation:** `statDate + 60 days + random(0-24 hours)`
- **Purpose:** Distribute delete operations over time

**`generalFavorites` Collection:**
- **Retention:** Until user unfavorites
- **Active Data:** No automatic expiration
- **Purpose:** Current favorite state

**`generalDealer` Collection:**
- **Retention:** Indefinite (member records)
- **Updates:** Manual or via member updates

### Memcache

**Pageview Counters:**
- **Retention:** No TTL (expiration = 0)
- **Volatility:** Can be cleared on server restart or memory pressure
- **Persistence:** NOT guaranteed
- **Recovery:** No automatic recovery (starts from 0 if cleared)

**Reports Cache:**
- **Retention:** 12 hours
- **Purpose:** Reduce BigQuery query costs
- **Invalidation:** Automatic after TTL

---

## Part 3: Jobs to Classifieds Migration Proposal

### Visual Architecture Comparison

```
JOBS ARCHITECTURE (Before)
══════════════════════════
┌────────────────────────────────────┐
│   jobs Collection                  │
│                                    │
│   { id: 12345,                     │
│     stats: {                       │
│       ui: {                        │
│         jdp: {                     │
│           view: {                  │
│             "20231225": 48 ←─────────── Stat embedded in doc
│           }                        │
│         }                          │
│       }                            │
│     },                             │
│     statsAggregated: {             │
│       jdpViewCount: 6234 ←───────────── Pre-calculated total
│     }                              │
│   }                                │
└────────────────────────────────────┘

CLASSIFIEDS ARCHITECTURE (After)
═════════════════════════════════
┌────────────────────────────────────┐
│   generalStats Collection          │
│                                    │
│   [                                │
│     { itemId: 12345,               │
│       statDate: 20231225,          │
│       statName: "detailPageViews", │
│       statValue: 48 } ←───────────────── Each stat is separate doc
│     ...                            │
│   ]                                │
└────────────────────────────────────┘
                │
                ├────────────────────────┐
                │                        │
┌───────────────▼──────┐   ┌─────────────▼──────────┐
│   Memcache           │   │  generalFavorites      │
│                      │   │                        │
│   slc-12345-c: 6234 ←┼───│  { listingId: 12345 }  │
│   (pageviews only)   │   │  (favorite tracking)   │
└──────────────────────┘   └────────────────────────┘
```

---

## Architecture Comparison

### Jobs Stats Architecture (Source System)

### Storage Model: Embedded Documents

Jobs uses an **embedded document model** where all stats are stored directly within the listing document. This provides atomic updates and fast single-document reads but has scalability limitations.

**1. MongoDB `jobs` Collection - Embedded Stats**

```jsx
{
  "_id": ObjectId("507f1f77bcf86cd799439011"),
  "id": 12345,
  "jobTitle": "Software Engineer",
  "memberId": 67890,
  "status": "active",
  
  // DAILY GRANULAR STATS
  // Hierarchical structure: category.subcategory.action.date
  // Indefinite retention - all historical data preserved
  "stats": {
    "ui": {
      "jdp": {                    // Job Detail Page
        "view": {
          "20231201": 35,
          "20231202": 41,
          "20231203": 38,
          // ... 100+ date entries
          "20231223": 42,
          "20231224": 56,
          "20231225": 48,
          "20231226": 62
        },
        "print": {
          "20231210": 1,
          "20231225": 2,
          "20231226": 1
        }
      },
      "srp": {                    // Search Results Page
        "featured": {
          "view": {
            "20231201": 98,
            "20231202": 104,
            // ... many dates
            "20231225": 125,
            "20231226": 143
          },
          "click": {
            "20231201": 12,
            "20231225": 18,
            "20231226": 21
          }
        },
        "standard": {
          "view": {
            "20231225": 245,
            "20231226": 267
          }
        },
        "spotlight": {
          "view": {
            "20231225": 87,
            "20231226": 92
          }
        }
      },
      "favorite": {
        "add": {
          "20231215": 2,
          "20231225": 5,
          "20231226": 3
        },
        "remove": {
          "20231220": 1,
          "20231225": 1
        }
      },
      "application": {
        "kslApply": {
          "20231220": 2,
          "20231225": 3,
          "20231226": 4
        }
      }
    }
  },
  
  // LIFETIME AGGREGATE TOTALS
  // Pre-calculated sums updated atomically with daily stats
  // Fast retrieval - no calculation needed
  "statsAggregated": {
    "jdpViewCount": 6234,              // Sum of all stats.ui.jdp.view.*
    "jdpPrintCount": 45,               // Sum of all stats.ui.jdp.print.*
    "srpFeaturedViewCount": 3421,      // Sum of all stats.ui.srp.featured.view.*
    "srpFeaturedClickCount": 342,      // Sum of all stats.ui.srp.featured.click.*
    "srpStandardViewCount": 5891,
    "srpSpotlightViewCount": 1234,
    "favoriteAddCount": 156,
    "favoriteRemoveCount": 23,
    "applicationKslApplyCount": 89
  }
}
```

**Stat Recording Example (Jobs):**

When a user views a job detail page:

```php
// StatsController::recordStat('ui.jdp.view', 12345)

// MongoDB Update Operation:
{
  "$inc": {
    "stats.ui.jdp.view.20231226": 1,      // Increment daily count
    "statsAggregated.jdpViewCount": 1      // Increment lifetime total
  }
}

// Result: Both daily and aggregate updated in single atomic operationnd aggregate updated in single atomic operation
```

**2. MongoDB `jobsBigQueryStats` Collection**

```jsx
{
  "DATE": 20231225,              // YYYYMMDD
  "listingId": 12345,
  "sellerId": 67890,
  "source": "web",               // "web" or "app"
  
  // Search results stats
  "standard_srp_listViews": 245,
  "featured_srp_listViews": 125,
  "spotlight_srp_listViews": 87,
  
  // Detail page stats
  "detailViews": 48,
  
  // Application stats
  "client_apply": 2,
  "ksl_apply_clicks": 5,
  "ksl_apply_success": 3,
  "emails": 1,
  "calls": 0
}
```

**3. BigQuery Tables**
- `job_stats.Web_Client_Dashboard_Stats`
- `job_stats.App_Client_Dashboard_Stats`

### API Endpoints

- `/classifieds/jobs/stats/recordStat` - Record new stat
- `/classifieds/jobs/stats/getJdpViewsByAd` - Get detail page views
- `/classifieds/jobs/stats/getFeaturedViewsByAd` - Get featured impressions
- `/classifieds/jobs/stats/getGoogleAnalyticStats` - Get BigQuery stats

### Classifieds Stats Architecture (Target System)

### Storage Model: Separate Collections

Classifieds uses a **normalized data model** with stats in separate collections. This enables efficient querying across listings, automatic data expiration, and better scalability at the cost of more complex queries.

**1. MongoDB `generalStats` Collection - Normalized Stats**

Each stat is a separate document:

```jsx
// Example: Multiple documents for listing 12345

// Document 1: Detail page views from web on Dec 25
{
  "_id": ObjectId("507f191e810c19729de860ea"),
  "createTime": ISODate("2023-12-25T00:00:00Z"),
  "itemId": 12345,
  "itemType": "listing",
  "statDate": 20231225,
  "statName": "detailPageViews",
  "statValue": 48,
  "statOrigin": "bq-web",
  "deleteTime": ISODate("2024-02-23T00:00:00Z")  // 60 days later
}

// Document 2: Detail page views from app on Dec 25
{
  "_id": ObjectId("507f191e810c19729de860eb"),
  "createTime": ISODate("2023-12-25T00:00:00Z"),
  "itemId": 12345,
  "itemType": "listing",
  "statDate": 20231225,
  "statName": "detailPageViews",
  "statValue": 12,
  "statOrigin": "bq-app",
  "deleteTime": ISODate("2024-02-23T00:00:00Z")
}

// Document 3: Featured impressions on Dec 25
{
  "_id": ObjectId("507f191e810c19729de860ec"),
  "createTime": ISODate("2023-12-25T00:00:00Z"),
  "itemId": 12345,
  "itemType": "listing",
  "statDate": 20231225,
  "statName": "searchPageFeaturedImpressions",
  "statValue": 125,
  "statOrigin": "bq-web",
  "deleteTime": ISODate("2024-02-23T00:00:00Z")
}

// Document 4: Detail page views from web on Dec 26
{
  "_id": ObjectId("507f191e810c19729de860ed"),
  "createTime": ISODate("2023-12-26T00:00:00Z"),
  "itemId": 12345,
  "itemType": "listing",
  "statDate": 20231226,
  "statName": "detailPageViews",
  "statValue": 62,
  "statOrigin": "bq-web",
  "deleteTime": ISODate("2024-02-24T00:00:00Z")
}

// ... many more documents
```

**Query Examples:**

```jsx
// Get all stats for listing 12345 on Dec 25
db.generalStats.find({
  itemType: "listing",
  itemId: 12345,
  statDate: 20231225
})

// Get detail page views for last 30 days
db.generalStats.find({
  itemType: "listing",
  itemId: 12345,
  statName: "detailPageViews",
  statDate: { $gte: 20231126, $lte: 20231225 }
})

// Get all stats for multiple listings
db.generalStats.find({
  itemType: "listing",
  itemId: { $in: [12345, 12346, 12347] },
  statDate: { $gte: 20231201 }
})
```

**2. Memcache - Real-Time Aggregates**

```jsx
// Key pattern: slc-{listingId}-c
// Example: slc-12345-c

// Value: Simple integer counter
6234  // Total pageviews

// Operations:
memcache.get("slc-12345-c")        // Returns: 6234
memcache.increment("slc-12345-c")  // Returns: 6235
memcache.set("slc-12345-c", 6234, 0)  // TTL=0 (no expiration)
```

**Purpose:**
- Store aggregate pageview count only (not all stats)
- Instant retrieval for display on listing detail pages
- Updated in real-time on each pageview
- No backup or persistence guarantee

**3. MongoDB `generalFavorites` Collection**

Tracks which users have favorited which listings:

```jsx
// Each document represents an active favorite
{
  "_id": ObjectId("507f1f77bcf86cd799439012"),
  "listingId": 12345,
  "memberId": 50001,
  "favoriteTime": ISODate("2023-12-25T14:30:00Z"),
  "vertical": "classifieds"  // or "jobs" after migration
}

// To get favorite count:
db.generalFavorites.countDocuments({ listingId: 12345 })
// Returns: 42
```

**4. BigQuery Reporting Tables**

30-day rolling window tables refreshed daily:

```sql
-- Table: classifieds_stats_30day_by_listing
CREATE TABLE classifieds_stats_30day_by_listing (
  Date DATE,
  Listing_Id INT64,
  Member_Id INT64,
  Vertical STRING,  -- 'classifieds', 'jobs', 'cars', etc.
  Impressions INT64,
  Impressions_Standard INT64,
  Impressions_Featured INT64,
  Clicks INT64,
  DetailPageviews INT64,
  Favorites INT64,
  Shares INT64,
  Leads INT64
)
PARTITION BY Date
OPTIONS(
  partition_expiration_days=30
);
```

**Example Query:**

```sql
SELECT 
  Date,
  SUM(DetailPageviews) as total_views,
  SUM(Impressions) as total_impressions
FROM classifieds_stats_30day_by_listing
WHERE Listing_Id = 12345
  AND Date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY Date
ORDER BY Date;
```

### API Endpoints

**Unified Stats API:**

```
GET /stats?itemType=listing&itemIdArray=12345,12346&dailyStatNameArray=detailPageViews&aggregateStatNameArray=detailPageViews,userFavorite
```

**Response Format:**

```json
{
  "data": {
    "dailyStats": {
      "12345": {
        "detailPageViews_bq-web": {
          "name": "detailPageViews",
          "origin": "bq-web",
          "dateArray": {
            "20231223": 42,
            "20231224": 56,
            "20231225": 48,
            "20231226": 62
          },
          "aggregateCount": 208
        },
        "detailPageViews_bq-app": {
          "name": "detailPageViews",
          "origin": "bq-app",
          "dateArray": {
            "20231223": 10,
            "20231224": 14,
            "20231225": 12,
            "20231226": 15
          },
          "aggregateCount": 51
        }
      }
    },
    "aggregateStats": {
      "12345": {
        "detailPageViews": 6234,  // From Memcache
        "userFavorite": 42         // From generalFavorites count
      }
    }
  }
}
```

---

## Detailed Differences with Examples

### 1. Data Structure & Storage Pattern

### Jobs: Embedded Document Pattern

**Example: Recording a Pageview**

```php
// Jobs approach - Update listing document
db.jobs.updateOne(
  { "id": 12345 },
  {
    "$inc": {
      "stats.ui.jdp.view.20231226": 1,
      "statsAggregated.jdpViewCount": 1
    }
  }
)
```

**Result:** Single document updated atomically

**Pros:**
- One write operation
- Consistent view of all stats
- Fast reads (single document)

**Cons:**
- Document grows forever
- Cannot query “all listings with >1000 views”
- Difficult to aggregate across listings

### Classifieds: Normalized Collection Pattern

**Example: Recording the Same Pageview**

```php
// Classifieds approach - Insert/update in generalStats
db.generalStats.updateOne(
  {
    "itemType": "listing",
    "itemId": 12345,
    "statDate": 20231226,
    "statName": "detailPageViews",
    "statOrigin": "bq-web"
  },
  {
    "$inc": { "statValue": 1 },
    "$setOnInsert": {
      "createTime": new Date(),
      "itemType": "listing",
      "deleteTime": new Date(+new Date() + 60*24*60*60*1000)
    }
  },
  { "upsert": true }
)

// Also update Memcache
memcache.increment("slc-12345-c", 1)
```

**Result:** Two operations (MongoDB + Memcache)

**Pros:**
- Can query across listings
- Automatic expiration
- Bounded document size

**Cons:**
- Two-phase update (eventual consistency)
- Requires join for complete picture
- More complex queries

### Migration Challenge

**Problem:** Transform from:

```jsx
// ONE document with nested stats
{
  "id": 12345,
  "stats": {
    "ui": {
      "jdp": {
        "view": {
          "20231201": 35,
          "20231202": 41,
          // ... 100 more dates
        }
      },
      "srp": {
        "featured": {
          "view": { "20231201": 98, "20231202": 104, ... },
          "click": { "20231201": 12, "20231202": 15, ... }
        }
      },
      // ... more stat types
    }
  }
}
```

To:

```jsx
// HUNDREDS of separate documents
[
  { itemId: 12345, statDate: 20231201, statName: "detailPageViews", statValue: 35, statOrigin: "jobs" },
  { itemId: 12345, statDate: 20231202, statName: "detailPageViews", statValue: 41, statOrigin: "jobs" },
  // ... 100 more for detail page views
  { itemId: 12345, statDate: 20231201, statName: "searchPageFeaturedImpressions", statValue: 98, statOrigin: "jobs" },
  { itemId: 12345, statDate: 20231202, statName: "searchPageFeaturedImpressions", statValue: 104, statOrigin: "jobs" },
  // ... 100 more for featured impressions
  // ... etc for all stat types
]
```

**Transformation Logic:**

```jsx
function transformJobsToClassifieds(jobsListing) {
  const records = [];
  
  function traverse(obj, path) {
    for (const [key, value] of Object.entries(obj)) {
      const currentPath = path ? `${path}.${key}` : key;
      
      if (isDateKey(key)) {
        // Found a stat: path is the stat type, key is the date, value is the count
        const mapping = getStatMapping(path);
        if (mapping) {
          records.push({
            itemId: jobsListing.id,
            itemType: "listing",
            statDate: parseInt(key),
            statName: mapping.statName,
            statValue: value,
            statOrigin: mapping.statOrigin,
            createTime: new Date(),
            deleteTime: calculateDeleteTime(key)
          });
        }
      } else if (typeof value === 'object') {
        traverse(value, currentPath);
      }
    }
  }
  
  traverse(jobsListing.stats, '');
  return records;
}

function isDateKey(key) {
  return /^\d{8}$/.test(key);
}
```

### 2. Stat Naming & Key Mapping

### Complete Mapping Table

| Jobs Hierarchical Path | Classifieds Flat Name | Origin | Aggregate Mapping |
| --- | --- | --- | --- |
| `ui.jdp.view` | `detailPageViews` | `jobs` | Memcache: `slc-{id}-c` |
| `ui.jdp.print` | `detailPagePrints` | `jobs` | Sum from generalStats |
| `ui.srp.featured.view` | `searchPageFeaturedImpressions` | `jobs` | Sum from generalStats |
| `ui.srp.featured.click` | `searchPageFeaturedClicks` | `jobs` | Sum from generalStats |
| `ui.srp.standard.view` | `searchPageStandardImpressions` | `jobs` | Sum from generalStats |
| `ui.srp.spotlight.view` | `searchPageSpotlightImpressions` | `jobs` | Sum from generalStats |
| `ui.favorite.add` | `userFavorite` | `jobs` | Count from generalFavorites |
| `ui.favorite.remove` | `userFavoriteRemove` | `jobs` | Sum from generalStats |
| `ui.application.kslApply` | `applicationSubmits` | `jobs` | Sum from generalStats |

### Mapping Examples

**Example 1: Simple Rename**

```jsx
// Jobs stat path
"stats.ui.jdp.view.20231225": 48

// Becomes Classifieds record
{
  itemId: 12345,
  statDate: 20231225,
  statName: "detailPageViews",  // ← Renamed
  statValue: 48,
  statOrigin: "jobs"
}
```

**Example 2: Multi-Level Path Flattening**

```jsx
// Jobs stat path
"stats.ui.srp.featured.view.20231225": 125

// Becomes Classifieds record
{
  itemId: 12345,
  statDate: 20231225,
  statName: "searchPageFeaturedImpressions",  // ← Path flattened + renamed
  statValue: 125,
  statOrigin: "jobs"
}
```

**Example 3: Aggregate Transformation**

```jsx
// Jobs aggregate
{
  "statsAggregated": {
    "jdpViewCount": 6234
  }
}

// Becomes Memcache entry
Key: "slc-12345-c"
Value: 6234

// NOT stored in generalStats (except as sum of daily values)
```

### 3. Date Format Transformation

### Jobs: Date as Object Key (String)

```jsx
{
  "stats": {
    "ui": {
      "jdp": {
        "view": {
          "20231225": 48,  // ← String key
          "20231226": 62   // ← String key
        }
      }
    }
  }
}

// Traversal:
for (const [date, count] of Object.entries(stats.ui.jdp.view)) {
  console.log(date, count);  // "20231225" 48
}
```

**Query for date range (DIFFICULT):**

```jsx
// Cannot efficiently query: "get all dates between 20231201 and 20231231"
// Must fetch entire document and filter in application code

const listing = db.jobs.findOne({ id: 12345 });
const views = listing.stats.ui.jdp.view;
const filtered = Object.entries(views)
  .filter(([date]) => date >= "20231201" && date <= "20231231")
  .reduce((sum, [_, count]) => sum + count, 0);
```

### Classifieds: Date as Integer Field

```jsx
{
  "itemId": 12345,
  "statDate": 20231225,  // ← Integer field (indexed)
  "statName": "detailPageViews",
  "statValue": 48
}
```

**Query for date range (EASY):**

```jsx
// Efficient MongoDB query using index
db.generalStats.find({
  itemId: 12345,
  statName: "detailPageViews",
  statDate: { $gte: 20231201, $lte: 20231231 }
})
```

### Migration Challenge

**Parsing Date Strings:**

```jsx
function parseJobsDateToInt(dateStr) {
  // "20231225" → 20231225
  const parsed = parseInt(dateStr, 10);
  
  // Validation
  if (isNaN(parsed) || parsed < 20000101 || parsed > 20991231) {
    throw new Error(`Invalid date: ${dateStr}`);
  }
  
  // Additional validation: check if it's a real date
  const year = Math.floor(parsed / 10000);
  const month = Math.floor((parsed % 10000) / 100);
  const day = parsed % 100;
  
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    throw new Error(`Invalid date components: ${dateStr}`);
  }
  
  return parsed;
}
```

### 4. Aggregation & Calculation Methods

### Jobs: Pre-Calculated Aggregates

**Atomic Update:**

```php
// StatsController::recordStat()
$today = date('Ymd');  // "20231226"
$statPath = "stats.ui.jdp.view.{$today}";
$aggregatePath = "statsAggregated.jdpViewCount";

db.jobs.updateOne(
  { "id": $listingId },
  {
    "$inc": {
      $statPath: 1,      // Daily stat
      $aggregatePath: 1   // Aggregate stat
    }
  }
)

// ALWAYS consistent: aggregate = sum of all daily values
```

**Reading Aggregates (FAST):**

```php
// Single document read
$listing = db.jobs.findOne({ "id": 12345 });
$totalViews = $listing['statsAggregated']['jdpViewCount'];
// Returns immediately: 6234
```

### Classifieds: Calculated Aggregates

**Separate Writes:**

```php
// 1. Update generalStats (daily)
db.generalStats.updateOne(...)

// 2. Update Memcache (aggregate) - SEPARATE operation
memcache.increment("slc-12345-c", 1)

// Potential consistency issue if Memcache update fails
```

**Reading Aggregates (MULTIPLE SOURCES):**

```php
// Option 1: From Memcache (for pageviews only)
$totalViews = memcache.get("slc-12345-c");
// Returns: 6234 (or false if cleared)

// Option 2: Calculate from generalStats (for other stats)
$result = db.generalStats.aggregate([
  { $match: { itemId: 12345, statName: "searchPageFeaturedImpressions" } },
  { $group: { _id: null, total: { $sum: "$statValue" } } }
]);
$totalImpressions = $result[0]['total'];

// Option 3: From generalFavorites (for favorites)
$totalFavorites = db.generalFavorites.countDocuments({ listingId: 12345 });
```

### Migration Challenge: Handling Aggregate Initialization

**Problem:** Jobs has pre-calculated aggregates that must be migrated to Memcache:

```jsx
// Jobs document
{
  "id": 12345,
  "statsAggregated": {
    "jdpViewCount": 6234,        // ← Need to migrate
    "jdpPrintCount": 45,          // ← Need to calculate if needed
    "srpFeaturedViewCount": 3421  // ← Need to calculate if needed
  }
}
```

**Solution:**

```jsx
// Initialize Memcache with Jobs aggregate
memcache.set(`slc-${listingId}-c`, jobsListing.statsAggregated.jdpViewCount, 0);

// For other stats, they'll be calculated on-demand from generalStats
// Or we can pre-populate during migration for performance:

function initializeAllAggregates(jobsListing) {
  // Pageviews → Memcache
  if (jobsListing.statsAggregated?.jdpViewCount) {
    memcache.set(
      `slc-${jobsListing.id}-c`,
      jobsListing.statsAggregated.jdpViewCount,
      0  // No expiration
    );
  }
  
  // Other aggregates will be calculated from generalStats when needed
  // But we could cache them temporarily for performance:
  const cacheKey = `listing-aggregates-${jobsListing.id}`;
  const cacheData = {
    prints: jobsListing.statsAggregated?.jdpPrintCount || 0,
    featuredViews: jobsListing.statsAggregated?.srpFeaturedViewCount || 0,
    featuredClicks: jobsListing.statsAggregated?.srpFeaturedClickCount || 0,
    // ... etc
  };
  memcache.set(cacheKey, JSON.stringify(cacheData), 3600);  // 1 hour TTL
}
```

### 5. Data Retention & Historical Data

### Jobs: Infinite Retention

```jsx
// Stats from listing created 2 years ago
{
  "id": 12345,
  "createdDate": "2021-12-01",
  "stats": {
    "ui": {
      "jdp": {
        "view": {
          "20211201": 15,  // 2 years old - still here
          "20211202": 18,
          "20211203": 22,
          // ... 700+ date entries over 2 years
          "20231225": 48,
          "20231226": 62   // Recent
        }
      }
    }
  }
}

// Query any historical date:
const viewsOnFirstDay = listing.stats.ui.jdp.view["20211201"];  // 15
```

### Classifieds: 60-Day Rolling Window

```jsx
// MongoDB only keeps last 60 days
db.generalStats.find({
  itemId: 12345,
  statName: "detailPageViews"
})

// Returns documents like:
[
  { statDate: 20231127, statValue: 35 },  // 60 days ago
  { statDate: 20231128, statValue: 41 },
  // ...
  { statDate: 20231225, statValue: 48 },  // Recent
  { statDate: 20231226, statValue: 62 }
]

// Data older than 60 days automatically deleted by TTL index
// For historical data, must query BigQuery
```

**BigQuery Historical Query:**

```sql
SELECT 
  DATE,
  DetailPageviews
FROM `ddm-dbi.job_stats.Web_Client_Dashboard_Stats`
WHERE Listing_Id = 12345
  AND DATE >= '2021-12-01'  -- Can go back years
ORDER BY DATE;
```

### Migration Strategy for Historical Data

**Option 1: Migrate Only Recent Data (Recommended)**

```jsx
// Only migrate stats from last 60 days
const cutoffDate = parseInt(
  new Date(Date.now() - 60*24*60*60*1000)
    .toISOString()
    .slice(0,10)
    .replace(/-/g, '')
);  // e.g., 20231027

function shouldMigrateStat(dateStr) {
  const statDate = parseInt(dateStr);
  return statDate >= cutoffDate;
}

// During migration:
for (const [date, value] of Object.entries(stats.ui.jdp.view)) {
  if (shouldMigrateStat(date)) {
    // Migrate to generalStats
  } else {
    // Skip - too old, will be in BigQuery only
  }
}
```

**Option 2: Migrate All Data (Not Recommended)**

```jsx
// Migrate all data but mark old records for immediate expiration
for (const [date, value] of Object.entries(stats.ui.jdp.view)) {
  const deleteTime = shouldMigrateStat(date)
    ? calculateDeleteTime(date)  // 60 days from stat date
    : new Date();  // Expire immediately (or very soon)
  
  records.push({
    itemId: listing.id,
    statDate: parseInt(date),
    statName: "detailPageViews",
    statValue: value,
    statOrigin: "jobs",
    createTime: new Date(),
    deleteTime: deleteTime
  });
}
```

### 6. Query Pattern Differences

### Jobs: Single-Document Queries

**Get all stats for a listing:**

```jsx
// ONE query, ONE document
const listing = db.jobs.findOne({ id: 12345 });

// All data available immediately:
const stats = {
  totalViews: listing.statsAggregated.jdpViewCount,
  dailyViews: listing.stats.ui.jdp.view,
  totalFavorites: listing.statsAggregated.favoriteAddCount,
  dailyFavorites: listing.stats.ui.favorite.add,
  // ... everything in one place
};
```

### Classifieds: Multi-Collection Queries

**Get all stats for a listing:**

```jsx
// MULTIPLE queries across different systems

// 1. Query generalStats for daily breakdown
const dailyStats = await db.generalStats.find({
  itemType: "listing",
  itemId: 12345,
  statDate: { $gte: 20231126, $lte: 20231225 }
}).toArray();

// 2. Query Memcache for pageview aggregate
const totalViews = await memcache.get("slc-12345-c");

// 3. Query generalFavorites for favorite count
const totalFavorites = await db.generalFavorites.countDocuments({
  listingId: 12345
});

// 4. Calculate other aggregates from daily stats
const featuredImpressions = dailyStats
  .filter(s => s.statName === "searchPageFeaturedImpressions")
  .reduce((sum, s) => sum + s.statValue, 0);

// Combine results
const stats = {
  totalViews,
  dailyViews: groupByDate(dailyStats, "detailPageViews"),
  totalFavorites,
  dailyFavorites: groupByDate(dailyStats, "userFavorite"),
  featuredImpressions
};
```

**Migration Impact:** APIs must be updated to handle multiple data sources

---

## Migration Strategy

### Approach: Phased Migration with Dual-Write Period

The migration follows a **strangler pattern** approach to minimize risk and ensure zero data loss:

1. **Build Alongside**: Implement Classifieds stats infrastructure for Jobs without affecting existing system
2. **Migrate Historical**: One-time migration of historical stats data
3. **Dual-Write**: Write to both systems simultaneously during transition period
4. **Validate Continuously**: Automated validation comparing both systems
5. **Switch Reads**: Gradually move read operations to new system using feature flags
6. **Deprecate Old**: Remove old system after stability proven

## Data Transformation Requirements

### 1. Stat Name Mapping

Create a bidirectional mapping configuration:

```jsx
// statMapping.js
const JOBS_TO_CLASSIFIEDS_MAPPING = {
  // Daily stats
  'ui.jdp.view': {
    statName: 'detailPageViews',
    statOrigin: 'legacy-jobs',  // Track migration source
    includeInMemcache: true      // Update aggregate counter
  },
  'ui.jdp.print': {
    statName: 'detailPagePrints',
    statOrigin: 'legacy-jobs',
    includeInMemcache: false
  },
  'ui.srp.featured.view': {
    statName: 'searchPageFeaturedImpressions',
    statOrigin: 'legacy-jobs',
    includeInMemcache: false
  },
  'ui.srp.featured.click': {
    statName: 'searchPageFeaturedClicks',
    statOrigin: 'legacy-jobs',
    includeInMemcache: false
  },
  'ui.srp.standard.view': {
    statName: 'searchPageStandardImpressions',
    statOrigin: 'legacy-jobs',
    includeInMemcache: false
  },
  'ui.favorite.add': {
    statName: 'userFavorite',
    statOrigin: 'legacy-jobs',
    includeInMemcache: false,
    special: 'favorites-collection'  // Also update generalFavorites
  },
  'ui.application.kslApply': {
    statName: 'applicationSubmits',
    statOrigin: 'legacy-jobs',
    includeInMemcache: false
  }
};

// Aggregate mapping
const AGGREGATE_MAPPING = {
  'jdpViewCount': 'memcache:slc-{id}-c',
  'jdpPrintCount': 'sum:detailPagePrints',
  'srpFeaturedViewCount': 'sum:searchPageFeaturedImpressions',
  'srpFeaturedClickCount': 'sum:searchPageFeaturedClicks',
  'favoriteAddCount': 'collection:generalFavorites',
  'applicationKslApplyCount': 'sum:applicationSubmits'
};
```

### 2. Data Structure Transformation

Transform from Jobs format to Classifieds format:

```jsx
// Example transformation
function transformJobsStatToClassifieds(jobsListing) {
  const records = [];
  
  // Process daily stats
  traverseStatTree(jobsListing.stats, '', (path, date, value) => {
    const mapping = JOBS_TO_CLASSIFIEDS_MAPPING[path];
    if (!mapping) {
      console.warn(`No mapping for stat: ${path}`);
      return;
    }
    
    records.push({
      itemId: jobsListing.id,
      itemType: 'listing',
      statDate: parseInt(date, 10),  // "20231225" -> 20231225
      statName: mapping.statName,
      statValue: value,
      statOrigin: mapping.statOrigin,
      createTime: new Date(),
      deleteTime: calculateDeleteTime(date)  // date + 60 days
    });
  });
  
  return records;
}

function traverseStatTree(obj, path, callback) {
  for (const [key, value] of Object.entries(obj)) {
    const currentPath = path ? `${path}.${key}` : key;
    
    if (typeof value === 'object' && !isDateKey(key)) {
      // Continue traversing
      traverseStatTree(value, currentPath, callback);
    } else if (isDateKey(key)) {
      // Found a date key with a value
      callback(path, key, value);
    }
  }
}

function isDateKey(key) {
  return /^\d{8}$/.test(key);  // Matches YYYYMMDD
}

function calculateDeleteTime(dateStr) {
  const date = parseDate(dateStr);  // Parse YYYYMMDD
  date.setDate(date.getDate() + 60);
  // Add random 0-24 hours to distribute deletes
  date.setHours(date.getHours() + Math.random() * 24);
  return date;
}
```

### 3. Memcache Initialization

Initialize Memcache with aggregate pageview counts:

```jsx
function initializeMemcacheAggregates(jobsListing) {
  const listingId = jobsListing.id;
  const memkey = `slc-${listingId}-c`;
  const pageviews = jobsListing.statsAggregated?.jdpViewCount || 0;
  
  // Set in Memcache with no expiration
  memcache.set(memkey, pageviews, 0);
  
  return { listingId, pageviews };
}
```

### 4. Favorites Migration

Migrate favorite events to `generalFavorites` collection:

```jsx
function migrateFavorites(jobsListing) {
  // Extract favorite add events from stats
  const favoriteEvents = extractFavoriteEvents(jobsListing.stats);
  
  // This is complex because we need to know WHO favorited
  // Jobs stats don't track member IDs for favorites
  // Options:
  // 1. Skip historical favorites (only use current favorites from separate collection)
  // 2. Create placeholder entries if favorites collection already exists
  // 3. Only migrate count, not individual records
  
  // Recommended: Option 3 - just migrate the count as stats
  // The generalFavorites collection will be populated going forward
  
  return favoriteEvents.map(event => ({
    itemId: jobsListing.id,
    itemType: 'listing',
    statDate: event.date,
    statName: 'userFavorite',
    statValue: event.count,
    statOrigin: 'legacy-jobs',
    createTime: new Date(),
    deleteTime: calculateDeleteTime(event.date)
  }));
}
```

---

## Migration Phases

### Phase 1: Preparation & Analysis

### 1.1 Data Audit

- [ ]  Count total job listings with stats
- [ ]  Identify date range of historical data
- [ ]  Calculate total stats records to migrate
- [ ]  Identify edge cases (missing fields, invalid dates, etc.)
- [ ]  Estimate MongoDB storage requirements

### 1.2 Mapping Configuration

- [ ]  Create complete stat name mapping
- [ ]  Document transformation rules
- [ ]  Define statOrigin value for migrated data
- [ ]  Create data validation rules

### 1.3 Environment Setup

- [ ]  Set up staging environment
- [ ]  Prepare MongoDB indexes for generalStats
- [ ]  Verify BigQuery access and permissions
- [ ]  Set up monitoring and alerting

### Phase 2: Historical Data Migration

### 2.1 Migration Script Development

**Command:** `bin/console migrate:jobs:stats-to-classifieds`

```php
<?php
// src/Command/MigrateJobsStatsCommand.php

namespace App\Command;

use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;

class MigrateJobsStatsCommand extends Command
{
    protected static $defaultName = 'migrate:jobs:stats-to-classifieds';
    
    protected function configure()
    {
        $this
            ->setDescription('Migrate Jobs stats to Classifieds stats format')
            ->addOption('dry-run', null, InputOption::VALUE_NONE, 'Run without writing data')
            ->addOption('batch-size', 'b', InputOption::VALUE_REQUIRED, 'Batch size', 1000)
            ->addOption('listing-id', 'l', InputOption::VALUE_REQUIRED, 'Migrate specific listing')
            ->addOption('start-date', null, InputOption::VALUE_REQUIRED, 'Start date (YYYYMMDD)')
            ->addOption('end-date', null, InputOption::VALUE_REQUIRED, 'End date (YYYYMMDD)')
            ->addOption('skip-old-stats', null, InputOption::VALUE_NONE, 'Skip stats older than 60 days')
        ;
    }
    
    protected function execute(InputInterface $input, OutputInterface $output)
    {
        $dryRun = $input->getOption('dry-run');
        $batchSize = (int) $input->getOption('batch-size');
        $listingId = $input->getOption('listing-id');
        $skipOldStats = $input->getOption('skip-old-stats');
        
        // Build query
        $query = [];
        if ($listingId) {
            $query['id'] = (int) $listingId;
        }
        
        // Count total
        $total = $this->jobsCollection->count($query);
        $output->writeln("Found {$total} job listings to migrate");
        
        // Process in batches
        $processed = 0;
        $errors = 0;
        $statsCreated = 0;
        
        $cursor = $this->jobsCollection->find($query, [
            'batchSize' => $batchSize,
            'projection' => ['id' => 1, 'stats' => 1, 'statsAggregated' => 1, 'memberId' => 1]
        ]);
        
        foreach ($cursor as $jobListing) {
            try {
                $result = $this->migrateListingStats(
                    $jobListing, 
                    $dryRun, 
                    $skipOldStats
                );
                
                $statsCreated += $result['statsCreated'];
                $processed++;
                
                if ($processed % 100 === 0) {
                    $output->writeln("Processed {$processed}/{$total}");
                }
                
            } catch (\Exception $e) {
                $errors++;
                $output->writeln("<error>Error processing listing {$jobListing['id']}: {$e->getMessage()}</error>");
            }
        }
        
        $output->writeln("\n<info>Migration Complete</info>");
        $output->writeln("Processed: {$processed}");
        $output->writeln("Stats Created: {$statsCreated}");
        $output->writeln("Errors: {$errors}");
        
        return Command::SUCCESS;
    }
    
    private function migrateListingStats($jobListing, $dryRun, $skipOldStats)
    {
        $listingId = $jobListing['id'];
        $statsRecords = [];
        
        // Transform daily stats
        if (isset($jobListing['stats'])) {
            $statsRecords = $this->transformer->transformDailyStats(
                $listingId,
                $jobListing['stats'],
                $skipOldStats
            );
        }
        
        // Initialize Memcache aggregate
        if (isset($jobListing['statsAggregated']['jdpViewCount'])) {
            if (!$dryRun) {
                $this->initializeMemcacheAggregate(
                    $listingId,
                    $jobListing['statsAggregated']['jdpViewCount']
                );
            }
        }
        
        // Bulk insert to generalStats
        if (!$dryRun && count($statsRecords) > 0) {
            $this->generalStatsCollection->insertMany(
                $statsRecords,
                ['ordered' => false]  // Continue on duplicate key errors
            );
        }
        
        return [
            'statsCreated' => count($statsRecords),
            'listingId' => $listingId
        ];
    }
}
```

### 2.2 Migration Execution

**Steps:**
1. Run with `--dry-run` first to validate
2. Migrate small batch (10 listings) and verify
3. Migrate recent stats (last 60 days) for all listings
4. Optionally migrate historical stats (> 60 days) to separate archive
5. Verify data integrity

**Commands:**

```bash
# Dry run
bin/console migrate:jobs:stats-to-classifieds --dry-run

# Test single listing
bin/console migrate:jobs:stats-to-classifieds --listing-id=12345

# Migrate recent stats only (last 60 days)
bin/console migrate:jobs:stats-to-classifieds --skip-old-stats

# Full migration
bin/console migrate:jobs:stats-to-classifieds --batch-size=1000
```

### 2.3 Data Validation

Create validation script:

```jsx
// Validation checks
function validateMigration(listingId) {
  const checks = {
    memcacheAggregate: validateMemcacheAggregate(listingId),
    dailyStatsCount: validateDailyStatsCount(listingId),
    statValuesMatch: validateStatValues(listingId),
    dateRanges: validateDateRanges(listingId)
  };
  
  return {
    listingId,
    passed: Object.values(checks).every(c => c.passed),
    checks
  };
}
```

### Phase 3: Dual-Write Implementation

During this phase, all new stats are written to BOTH systems.

### 3.1 Stat Recording Adapter

Create adapter layer in Jobs StatsController:

```php
<?php
// site-api/api/controllers/StatsController.php

public function recordStat($key, $id, $memberId = '', $op = 'inc', $value = 1)
{
    // EXISTING: Write to jobs collection
    $this->recordStatToJobsCollection($key, $id, $op, $value);
    
    // NEW: Also write to classifieds generalStats
    $this->recordStatToClassifiedsFormat($key, $id, $memberId, $value);
    
    return $this->_getResponse(['success' => true]);
}

private function recordStatToClassifiedsFormat($key, $listingId, $memberId, $value)
{
    // Map Jobs stat key to Classifieds stat name
    $mapping = $this->getStatMapping($key);
    if (!$mapping) {
        // Log warning but don't fail
        $this->logger->warning("No classifieds mapping for stat key: {$key}");
        return;
    }
    
    // Create generalStats record
    $statDate = (int) date('Ymd');
    $record = [
        'itemId' => (int) $listingId,
        'itemType' => 'listing',
        'statDate' => $statDate,
        'statName' => $mapping['statName'],
        'statValue' => (int) $value,
        'statOrigin' => 'jobs',  // Indicates it came from jobs vertical
        'createTime' => new \MongoDB\BSON\UTCDateTime(),
        'deleteTime' => $this->calculateDeleteTime($statDate)
    ];
    
    // Upsert to generalStats (increment if exists)
    $this->generalStatsCollection->updateOne(
        [
            'itemType' => 'listing',
            'itemId' => (int) $listingId,
            'statDate' => $statDate,
            'statName' => $mapping['statName'],
            'statOrigin' => 'jobs'
        ],
        [
            '$inc' => ['statValue' => (int) $value],
            '$setOnInsert' => [
                'createTime' => $record['createTime'],
                'itemType' => $record['itemType'],
                'deleteTime' => $record['deleteTime']
            ]
        ],
        ['upsert' => true]
    );
    
    // Update Memcache aggregate if applicable
    if ($mapping['includeInMemcache']) {
        $memkey = "slc-{$listingId}-c";
        $this->memcache->increment($memkey, $value);
    }
}
```

### 3.2 BigQuery Stats Sync

Update `getStatsFromBigQuery.php` to write to generalStats:

```php
// After inserting to jobsBigQueryStats, also insert to generalStats
foreach ($statsFromBQ as $stat) {
    $this->insertToGeneralStats([
        'itemId' => $stat['listingId'],
        'itemType' => 'listing',
        'statDate' => $stat['DATE'],
        'statName' => 'detailPageViews',
        'statValue' => $stat['detailViews'],
        'statOrigin' => $stat['source'] === 'web' ? 'bq-web' : 'bq-app',
        // ... etc
    ]);
}
```

### 3.3 Monitoring & Validation

- [ ]  Set up DataDog metrics for dual-write discrepancies
- [ ]  Create daily validation job comparing both systems
- [ ]  Alert on > 1% discrepancy
- [ ]  Log all mapping failures

### Phase 4: Frontend Updates

### 4.1 MyAccount Dashboard Updates

Update `JobsPerformance.ts` to use new API format:

```tsx
// services/ListingPerformance/JobsPerformance.ts

async function JobsPerformance(
  ids: number[],
  memberId: number
): Promise<ListingPerformanceData> {
  
  // Call unified stats API
  const response = await fetch(
    `/api/stats?itemType=listing&itemIdArray=${ids.join(',')}&` +
    `dailyStatNameArray=detailPageViews,searchPageFeaturedImpressions&` +
    `aggregateStatNameArray=detailPageViews,userFavorite`
  );
  
  const { data } = await response.json();
  
  // Transform to expected format
  return ids.map(id => ({
    id,
    type: "Jobs",
    attributes: {
      performanceData: {
        totals: {
          views: data.aggregateStats[id]?.detailPageViews || 0,
          impressions: data.aggregateStats[id]?.searchPageFeaturedImpressions || 0,
          favorites: data.aggregateStats[id]?.userFavorite || 0
        },
        byDay: transformDailyStats(data.dailyStats[id])
      }
    }
  }));
}
```

### 4.2 Listing Detail Page

Update view counter to use Memcache via unified API:

```jsx
// Frontend: Display view count
fetch(`/api/stats/views/${listingId}?increment=true`)
  .then(res => res.json())
  .then(data => {
    document.getElementById('view-count').textContent = 
      `${data.views.toLocaleString()} views`;
  });
```