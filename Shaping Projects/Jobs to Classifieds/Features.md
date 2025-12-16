# Features - Unified Listing Service

This document outlines all required features for the unified listing service that consolidates Jobs, Classifieds, Cars, and Homes verticals.

---

## 1. Core Listing Management

### 1.1 Listing CRUD Operations

**Priority**: Phase 1 (MVP)

**Description**: Basic create, read, update, delete operations for all listing types (Jobs, Classifieds, Cars, Homes).

**Acceptance Criteria**:
- ✅ Users can create a new listing draft
- ✅ Users can retrieve a single listing by ID
- ✅ Users can update listing fields (title, description, price, location, etc.)
- ✅ Users can soft-delete listings (status change to "Deleted")
- ✅ Listing creation validates required fields per vertical type
- ✅ Listing updates preserve history in `history` array
- ✅ Support for discriminator pattern (listingType: CAR, CLASSIFIED, HOME_BUY, HOME_RENT, JOB)
- ✅ Vertical-specific fields stored in typed objects (carDetails, jobDetails, etc.)
- ✅ Draft listings (status: "Draft") not visible in public search
- ✅ Active listings have proper expiration dates set

**Endpoints**:
- `POST /listings/create-draft` - Create draft listing
- `GET /listings/{id}` - Get listing by ID
- `PUT /listings/{id}` - Update listing
- `DELETE /listings/{id}` - Delete listing

---

### 1.2 Listing Lifecycle Management

**Priority**: Phase 1 (MVP)

**Description**: Manage listing state transitions through their lifecycle (draft → active → expired/sold/deleted).

**Acceptance Criteria**:
- ✅ Status transitions tracked in history
- ✅ Timestamps automatically managed (createTime, modifyTime, displayTime, expireTime)
- ✅ Support for manual expiration
- ✅ Support for marking listings as sold
- ✅ Renewal extends expiration date
- ✅ Expired listings automatically transitioned by cron job
- ✅ Deleted listings soft-deleted (preserved in database)

**Statuses**:
- `Draft` - Draft, not published
- `Active` - Live and searchable
- `Expired` - Past expiration date
- `Sold` - Manually marked as sold
- `Deleted` - Soft deleted
- `Pending` - Awaiting payment/approval

**Endpoints**:
- `PUT /listings/{id}/renew` - Renew listing (extend expiration)
- `PUT /listings/{id}/expire` - Manually expire listing (Jobs)
- `PUT /listings/{id}/mark-sold` - Mark listing as sold (Classifieds/Cars/Homes)

---

### 1.3 Listing Metadata & Support Data

**Priority**: Phase 1 (MVP)

**Description**: Provide supporting data for creating and managing listings (categories, options, user defaults).

**Acceptance Criteria**:
- ✅ Return category tree with subcategories
- ✅ Return category-specific specifications and allowed values
- ✅ Return user's default contact information
- ✅ Return pricing information for renewals
- ✅ Return predefined rental rules (for rental listings)
- ✅ Return thanks page data after listing creation
- ✅ Support for getting paid listing information

**Endpoints**:
- `GET /listings/meta` - Get listing metadata (categories, options)
- `GET /listings/contact-info` - Get user's default contact info
- `GET /listings/renew-data` - Get renewal pricing and data
- `GET /listings/predefined-rental-rules` - Get rental rule templates
- `GET /listings/{id}/thanks-page` - Get data for post-creation page
- `POST /listings/paid-info` - Get paid feature info for multiple listings

---

## 2. Search & Discovery

### 2.1 Listing Search

**Priority**: Phase 1 (MVP)

**Description**: Search and filter listings with Elasticsearch.

**Acceptance Criteria**:
- ✅ Search by keyword (title, description)
- ✅ Filter by location (city, state, zip, radius)
- ✅ Filter by price range
- ✅ Filter by category and subcategory
- ✅ Filter by listing type (vertical)
- ✅ Filter by market type (Sale, Wanted, Rent, Service for Classifieds)
- ✅ Faceted search with counts
- ✅ Sorting (date, price, relevance)
- ✅ Pagination support
- ✅ Exclude deleted/expired listings (unless specifically requested)
- ✅ Support for "Top Jobs Only" filter (Jobs)
- ✅ Support for featured/spotlight filtering

**Search Facets**:
- Category/Subcategory
- Price ranges
- Location
- Listing type (vertical)
- Market type
- Category-specific attributes (varies by category)

**Jobs-Specific Filters**:
- Employment type (Full Time, Part Time, Contract, etc.)
- Education level
- Years of experience
- Salary/hourly range
- Company perks

**Endpoints**:
- `GET /listings` - Search listings with filters

---

### 2.2 Search Suggestions

**Priority**: Phase 2

**Description**: Autocomplete and category suggestions for search.

**Acceptance Criteria**:
- ✅ Keyword autocomplete suggestions
- ✅ Category suggestions based on query text
- ✅ Suggestions based on Elasticsearch data
- ✅ Configurable maximum results

**Endpoints**:
- `GET /suggester/keyword-search-suggestions` - Keyword autocomplete
- `GET /suggester/suggested-categories` - Category suggestions

---

### 2.3 Archive Search

**Priority**: Phase 2

**Description**: Search expired and sold listings for historical reference.

**Acceptance Criteria**:
- ✅ Search archived/expired listings
- ✅ Filter by date range
- ✅ Similar search capabilities as active listings
- ✅ Restore capability for archived listings

**Endpoints**:
- `GET /archive-listings` - Search archived listings
- `PUT /archive-listings` - Restore archived listings

---

## 3. Media Management

### 3.1 Photo Upload & Management

**Priority**: Phase 1 (MVP)

**Description**: Upload, edit, and delete photos for listings.

**Acceptance Criteria**:
- ✅ Upload photos to S3 via image service
- ✅ Multiple photos per listing (array)
- ✅ Set primary photo
- ✅ Reorder photos
- ✅ Edit photo metadata (caption, description)
- ✅ Delete individual photos
- ✅ Photo size validation
- ✅ Photo format validation (jpg, png, etc.)
- ✅ Generate thumbnails via image service
- ✅ Maximum photo count enforced (varies by vertical/plan)

**Storage**:
- S3 integration via existing image upload/download services
- Photo metadata stored in listing document

**Endpoints**:
- `POST /listings/{id}/photos` - Upload photo
- `POST /listings/{id}/photos/{photoId}` - Edit photo metadata
- `DELETE /listings/{id}/photos/{photoId}` - Delete photo

---

### 3.2 Video Management

**Priority**: Phase 3

**Description**: Upload and manage video content for listings (Cars, Homes).

**Acceptance Criteria**:
- ✅ Video upload integration
- ✅ Video processing status tracking
- ✅ Video thumbnail generation
- ✅ Multiple videos per listing
- ✅ Video metadata (title, description)

---

## 4. Favorites & Saved Searches

### 4.1 Listing Favorites

**Priority**: Phase 2

**Description**: Users can favorite/unfavorite listings for quick access.

**Acceptance Criteria**:
- ✅ Add listing to favorites
- ✅ Remove listing from favorites
- ✅ Update favorite settings (notification preferences)
- ✅ Get user's favorited listings
- ✅ Favorite count tracked on listing
- ✅ Support for all listing types
- ✅ Authentication required

**Endpoints**:
- `POST /listings/{listingId}/favorites` - Favorite a listing
- `PUT /listings/{listingId}/favorites` - Update favorite settings
- `DELETE /listings/{listingId}/favorites` - Unfavorite listing
- `GET /homepage/my-favorites` - Get user's favorites

---

### 4.2 Saved Searches

**Priority**: Phase 2

**Description**: Users can save search criteria for quick access and alerts.

**Acceptance Criteria**:
- ✅ Create saved search with filter criteria
- ✅ Update saved search
- ✅ Delete saved search
- ✅ Get saved searches for user
- ✅ Get listings matching saved search
- ✅ Email notification settings per saved search
- ✅ Support for all listing types

**Endpoints**:
- `POST /saved-searches` - Create saved search
- `PUT /saved-searches/{id}` - Update saved search
- `DELETE /saved-searches/{id}` - Delete saved search
- `GET /homepage/saved-search/{id}/listings` - Get matching listings

---

## 5. Premium Features & Promotions

### 5.1 Featured Listings (Classifieds, Cars, Homes)

**Priority**: Phase 2

**Description**: Premium placement for listings with enhanced visibility.

**Acceptance Criteria**:
- ✅ Standard featured ads (persistent highlighting)
- ✅ Featured date tracking (array of dates)
- ✅ Featured listings prioritized in search results
- ✅ Featured badges/ribbons displayed
- ✅ Pricing per category
- ✅ Purchase during listing creation or later

**Fields**:
- `standardFeatured` - Boolean flag
- `standardFeaturedDates` - Array of feature dates
- `isFeatured` - Computed from dates

---

### 5.2 Spotlight Listings (Classifieds)

**Priority**: Phase 2

**Description**: Premium homepage/category page placement.

**Acceptance Criteria**:
- ✅ Create spotlight for listing
- ✅ Target specific category/subcategory
- ✅ Member-specific spotlights
- ✅ Status management (Active/Inactive)
- ✅ Multiple spotlight types
- ✅ Display on homepage and category pages

**Endpoints**:
- `GET /spotlights` - Get spotlights
- `POST /spotlights` - Add spotlight
- `PUT /spotlights` - Update spotlight
- `DELETE /spotlights` - Remove spotlight

---

### 5.3 Top Jobs (Jobs)

**Priority**: Phase 2

**Description**: Premium 30-day placement for job listings.

**Acceptance Criteria**:
- ✅ Purchase Top Job promotion ($25 for 30 days)
- ✅ Immediate activation
- ✅ Display in "Latest Top Jobs" homepage section
- ✅ Sort by `topJobStart` (descending)
- ✅ "Top Jobs Only" search filter
- ✅ Automatic expiration after 30 days
- ✅ Re-purchase capability (overwrites dates)

**Fields**:
- `topJob` - Boolean flag
- `topJobStart` - Start timestamp (for sorting)
- `topJobTime` - Expiration timestamp (start + 30 days)

---

### 5.4 Boost System (Jobs)

**Priority**: Phase 2

**Description**: Move job listings to top of search results.

**Acceptance Criteria**:
- ✅ Free boost (periodic allowance)
- ✅ Paid boost (immediate purchase)
- ✅ Auto boost (scheduled at 3, 7, or 14-day intervals)
- ✅ Boost history tracking
- ✅ Scheduled boost queue
- ✅ Last boost time tracking
- ✅ Boost cooldown period for free boosts

**Fields**:
- `allowFreeBoost` - Boolean (eligibility for free boost)
- `autoBoost` - Object (enabled, frequency, timestamps)
- `boostHistory` - Array of boost events
- `scheduledBoosts` - Array of Unix timestamps

**Endpoints**:
- `POST /listings/{id}/boost` - Boost listing to top
- `PUT /listings/{id}/auto-boost` - Configure auto-boost

---

### 5.5 Pricing & Payment Intent

**Priority**: Phase 2

**Description**: Calculate pricing and create Stripe payment intents.

**Acceptance Criteria**:
- ✅ Get pricing for listing features (listing fee, featured, boost, etc.)
- ✅ Create Stripe payment intent
- ✅ Support for promo codes
- ✅ Category-specific pricing
- ✅ Package/bundle pricing (Jobs employers)
- ✅ Track purchase history on listing

**Endpoints**:
- `POST /listings/create-payment-intent` - Create Stripe payment intent
- `GET /payments/stripe-key` - Get public Stripe key
- `GET /payments/payment-methods` - Get user's payment methods

---

## 6. Jobs-Specific Features

### 6.1 Job Application System (Separate Microservice)

**Priority**: Phase 2

**Description**: Job seekers can apply directly on KSL or be redirected to external application URLs.

**Service**: `listing-applications` (separate microservice)

**Acceptance Criteria**:
- ✅ Apply with resume and cover letter (PDF/DOC formats)
- ✅ Virus scanning of uploaded files (ClamAV integration)
- ✅ S3 storage of application files
- ✅ Email to employer with attachments
- ✅ Confirmation email to applicant
- ✅ Quick Apply profile (saved applicant data)
- ✅ Anonymous applications (no login required)
- ✅ Application count tracked on listing
- ✅ Application history per listing
- ✅ 4MB total file size limit
- ✅ External `applicationUrl` support (redirect)

**Data Storage**:
- MongoDB: `jobsApplication`, `jobsQuickApply` collections
- S3: Resume and cover letter files in `mplace-jobs.ksl.com` bucket

**TODO**: @Chris - Add technical notes on virus scanning infrastructure and deployment

**Endpoints** (in separate `listing-applications` service):
- `POST /applications` - Submit job application
- `GET /applications/quick-apply` - Get saved Quick Apply profile
- `POST /applications/quick-apply` - Save Quick Apply profile
- `GET /applications/{id}/download` - Download application file

---

### 6.2 Pay Range Display (Jobs)

**Priority**: Phase 1 (MVP)

**Description**: Display salary or hourly compensation ranges for job listings.

**Acceptance Criteria**:
- ✅ Support for salary ranges (annual)
- ✅ Support for hourly ranges
- ✅ `payRangeType` field ("hourly" | "salary")
- ✅ Stored in cents to avoid floating point issues
- ✅ Optional field (can be omitted)
- ✅ Used in search filters/facets
- ✅ Display formatted on frontend

**Fields**:
- `jobDetails.payRangeType` - "hourly" | "salary"
- `jobDetails.salaryFrom` - Integer (cents)
- `jobDetails.salaryTo` - Integer (cents)
- `jobDetails.hourlyFrom` - Integer (cents)
- `jobDetails.hourlyTo` - Integer (cents)

---

### 6.3 Employer Features (Jobs)

**Priority**: Phase 3

**Description**: Employer accounts with packages, multiple authorized users, and company profiles.

**Acceptance Criteria**:
- ✅ Employer packages with job allotments
- ✅ Multiple authorized users per employer
- ✅ Company logo upload
- ✅ Company profile information
- ✅ Package consumption tracking
- ✅ Employer group hierarchy

**Fields**:
- `authorizedUsers` - Array of member IDs
- `companyName` - Company name
- `companyPerks` - Array of perks

---

## 7. Classifieds-Specific Features

### 7.1 Category & Subcategory System

**Priority**: Phase 1 (MVP)

**Description**: Hierarchical category tree with subcategories and specifications.

**Acceptance Criteria**:
- ✅ Get full category tree
- ✅ Get category SEO data
- ✅ Get category filters
- ✅ Get subcategory specifications (dynamic fields per subcategory)
- ✅ Jobs migrated as subcategories under "Jobs" parent category
- ✅ Specification limits: 10 string, 10 int, 2 float fields per subcategory

**Endpoints**:
- `GET /categories` - Get category tree
- `GET /category-tree` - Get category tree (alt)
- `GET /category-seo` - Get category SEO data
- `GET /category-filters` - Get category filters
- `GET /sub-categories/specifications` - Get subcategory specifications

---

### 7.2 Dealer Management (Classifieds, Cars)

**Priority**: Phase 2

**Description**: Dealer accounts with logos, CSL configuration, and fee bypass.

**Acceptance Criteria**:
- ✅ Get dealer information
- ✅ Upload dealer logo
- ✅ Delete dealer logo
- ✅ CSL (auto-import) configuration
- ✅ Bypass listing fee setting
- ✅ Integration settings
- ✅ Dealer monthly email reports

**Endpoints**:
- `GET /dealer/{dealerId}` - Get dealer info
- `POST /dealer/{dealerId}/logo` - Upload dealer logo
- `DELETE /dealer/{dealerId}/logo` - Delete dealer logo
- `POST /dealer/{dealerId}/csl-config` - Add CSL config
- `GET /dealer/{dealerId}/csl-config` - Get CSL config
- `DELETE /dealer/{dealerId}/csl-config` - Remove CSL config
- `PATCH /dealer/{dealerId}/bypass-listing-fee` - Update fee bypass
- `PATCH /dealer/{dealerId}/integration` - Update integration
- `DELETE /dealer/{dealerId}/integration` - Remove integration

---

### 7.3 Rental Listings (Classifieds, Homes)

**Priority**: Phase 2

**Description**: Support for rental listings with specific rules and pricing.

**Acceptance Criteria**:
- ✅ Rental-specific fields (price unit rate, rules, available date)
- ✅ Predefined rental rules templates
- ✅ Separate rental pricing
- ✅ Rental category filtering
- ✅ Display on homepage rental section

**Fields**:
- `isRental` - Boolean
- `rentalPriceUnitRate` - "perDay" | "perWeek" | "perMonth" | "perYear"
- `rentalRules` - Array of rule strings
- `availableDate` - Date

**Endpoints**:
- `GET /listings/predefined-rental-rules` - Get rental rule templates
- `GET /homepage/rental-listings` - Get rental listings for homepage

---

## 8. Feed Integration

### 8.1 XML Feed Processing (Jobs, Classifieds)

**Priority**: Phase 3

**Description**: Import listings from external XML feeds via pubsub architecture.

**Architecture**:
1. **Feed Parser Service**: Parse XML feeds and publish to PubSub
2. **Feed Subscriber Service**: Subscribe to PubSub and call listing REST endpoints for CRUD

**Acceptance Criteria**:
- ✅ Parse XML feeds (Jobs: LHM, Workstream, Ken Garff, Harmons)
- ✅ Publish parsed listing data to PubSub topic
- ✅ Subscriber creates/updates listings via REST API
- ✅ Match on `externalId` (feedJobId for Jobs, stockNumber for Classifieds)
- ✅ Cleanup stale listings not in feed
- ✅ Feed source tracking (`onFeed` array)
- ✅ Package consumption tracking (Jobs employer groups)
- ✅ Error handling and retry logic
- ✅ Notification on completion (Slack)

**Feed Types**:
- **Jobs**: XML feeds from employer groups
- **Classifieds**: CSV feeds from dealers (existing General Feeds)

**Data Flow**:
```
XML Feed → Parser Service → PubSub Topic → Subscriber Service → REST API (CRUD)
```

**Fields**:
- `externalId` - External system identifier
- `onFeed` - Array of feed sources
- `importSource` - Feed client identifier

---

### 8.2 Feed Configuration

**Priority**: Phase 3

**Description**: Configure and manage feed sources per dealer/employer.

**Acceptance Criteria**:
- ✅ Feed URL configuration
- ✅ Feed format specification
- ✅ Feed schedule/frequency
- ✅ Package limits (Jobs)
- ✅ Field mapping configuration
- ✅ Enable/disable per feed

---

## 9. Shared Features (All Verticals)

### 9.1 Abuse Reporting & Moderation

**Priority**: Phase 2

**Description**: Users can report abusive listings; moderators can review and take action.

**Acceptance Criteria**:
- ✅ Submit abuse report for listing
- ✅ Get abuse reports for listing
- ✅ Get all abuse records with filtering
- ✅ Review abuse report (moderator action)
- ✅ Abuse stats by time range
- ✅ Abuse history tracking
- ✅ Multiple reports per listing
- ✅ Report reasons (spam, scam, inappropriate, etc.)

**Endpoints**:
- `POST /abuse/{listingId}/reports` - Report listing
- `GET /abuse/{listingId}/reports` - Get reports for listing
- `GET /abuse/{listingId}` - Get abuse record for listing
- `GET /abuse` - Get all abuse records
- `PUT /abuse/{listingId}/review` - Review abuse report
- `GET /abuse/stats` - Get abuse statistics
- `POST /abuse/stats/timeRange` - Get abuse stats for time range

---

### 9.2 Statistics & Analytics

**Priority**: Phase 1 (MVP) - Integration with existing `reports-http-rest` service

**Description**: Track and retrieve listing statistics (views, clicks, favorites, applications).

**Acceptance Criteria**:
- ✅ Integration with existing `reports-http-rest` service in marketplace-backend
- ✅ Track page views, favorites, clicks, emails, phone calls
- ✅ Application counts (Jobs)
- ✅ Daily aggregation
- ✅ BigQuery integration for historical data
- ✅ Memcache for performance
- ✅ Stats by listing, by member, by date range

**Note**: Statistics are handled by the existing `reports-http-rest` service. No migration needed for listing service.

**External Service Endpoints**:
- `GET /stats` - Get listing statistics (via `reports-http-rest`)

---

### 9.3 Notifications

**Priority**: Phase 3

**Description**: Email notifications for various listing events.

**Acceptance Criteria**:
- ✅ Price drop notifications
- ✅ Expiration warnings (seller)
- ✅ Expiration notifications (buyers with favorites)
- ✅ Saved search match alerts
- ✅ Application received (Jobs employers)
- ✅ Application confirmation (Jobs applicants)
- ✅ Configurable notification preferences

**Endpoints**:
- `POST /price-drop/notifications` - Send price drop notifications
- `POST /expiration/notify-seller` - Notify seller of upcoming expiration
- `POST /expiration/notify-buyers` - Notify buyers of expiring favorites
- `GET /expiration/listings` - Get listings expiring soon

---

### 9.4 Homepage Aggregation

**Priority**: Phase 2

**Description**: Aggregate user-specific listing data for homepage display.

**Acceptance Criteria**:
- ✅ Get user's active listings summary
- ✅ Get user's favorites summary
- ✅ Get top/featured listings
- ✅ Get rental listings
- ✅ Get saved search matches
- ✅ User preference management
- ✅ Homepage metadata

**Endpoints**:
- `GET /homepage/my-listings` - User's listings
- `GET /homepage/my-favorites` - User's favorites
- `GET /homepage/top-listings` - Featured/top listings
- `GET /homepage/rental-listings` - Rental listings
- `GET /homepage/saved-search/{id}/listings` - Saved search matches
- `GET /homepage/get-meta-data` - Homepage metadata
- `POST /homepage/save-user-preferences` - Save user preferences

---

### 9.5 Member Management

**Priority**: Phase 2

**Description**: Member-related operations for listings (verification, notes, status).

**Acceptance Criteria**:
- ✅ Get member information
- ✅ Get member notes
- ✅ Create member note
- ✅ Update member status
- ✅ Update verification status for member listings
- ✅ Toggle hidden status for member listings
- ✅ Get member listings status

**Endpoints**:
- `GET /members/{memberId}` - Get member info
- `GET /members` - Get multiple members info
- `GET /members/{memberId}/notes` - Get member notes
- `POST /members/{memberId}/notes` - Create member note
- `PUT /members/{memberId}/status` - Update member status
- `PUT /listings/member/{memberId}/verification-status` - Update verification
- `PUT /listings/member/{memberId}/toggle-hidden/{setHidden}` - Toggle hidden
- `GET /listings/member/{memberId}/listings-status` - Get listings status
- `GET /listings/{id}/member` - Get member by listing ID
- `GET /members/{id}/lookup` - Get member by ID

---

### 9.6 Management & Batch Operations

**Priority**: Phase 3

**Description**: Administrative endpoints for batch operations.

**Acceptance Criteria**:
- ✅ Send dealer monthly email
- ✅ Batch update listings
- ✅ Update member listings dealer data
- ✅ Bulk operations with validation

**Endpoints**:
- `PUT /management/dealer-monthly-email/{memberId}` - Send dealer monthly email
- `PUT /management/update-batch-listings` - Batch update listings
- `PUT /management/update-member-listings-dealer-data/{memberId}` - Update dealer data

---

## 10. Support Features

### 10.1 Cities Data

**Priority**: Phase 2

**Description**: Get city/location data for dropdowns and autocomplete.

**Acceptance Criteria**:
- ✅ Get cities list
- ✅ Filter by state
- ✅ Get location from zip code

**Endpoints**:
- `GET /cities` - Get cities

---

### 10.2 Surveys (Classifieds)

**Priority**: Phase 4 (Low Priority)

**Description**: Survey system for gathering user feedback on listings.

**Acceptance Criteria**:
- ✅ Create survey
- ✅ Update survey
- ✅ Get survey by ID
- ✅ Get all surveys
- ✅ Submit survey results
- ✅ Get survey statistics
- ✅ Delete survey

**Endpoints**:
- `GET /surveys` - Get all surveys
- `POST /surveys` - Create survey
- `GET /surveys/{id}` - Get survey
- `PUT /surveys/{id}` - Update survey
- `DELETE /surveys/{id}` - Delete survey
- `POST /surveys/{id}/results` - Submit results
- `GET /surveys/stats` - Get statistics
- `GET /surveys/types` - Get survey types

---

## Feature Priority Summary

### Phase 1 (MVP)
- Core listing CRUD
- Listing lifecycle management
- Listing metadata & support data
- Listing search (basic)
- Photo upload & management
- Category system (read-only)
- Pay range display (Jobs)
- Statistics integration (existing service)

### Phase 2
- Listing favorites
- Saved searches
- Featured listings
- Spotlight listings
- Top Jobs
- Boost system (Jobs)
- Job applications (separate microservice)
- Dealer management
- Rental listings
- Search suggestions
- Archive search
- Abuse reporting
- Homepage aggregation
- Member management
- Cities data

### Phase 3
- Feed integration (XML parser + PubSub)
- Employer features (Jobs)
- Video management
- Notifications
- Batch operations

### Phase 4
- Surveys
- Advanced analytics
- Additional integrations

---

## Cross-Vertical Feature Matrix

| Feature | Jobs | Classifieds | Cars | Homes |
|---------|------|-------------|------|-------|
| **Core CRUD** | ✅ | ✅ | ✅ | ✅ |
| **Search** | ✅ | ✅ | ✅ | ✅ |
| **Photos** | ✅ | ✅ | ✅ | ✅ |
| **Videos** | ❌ | ❌ | ✅ | ✅ |
| **Favorites** | ✅ | ✅ | ✅ | ✅ |
| **Saved Searches** | ✅ | ✅ | ✅ | ✅ |
| **Featured Ads** | ✅ (Top Jobs) | ✅ | ✅ | ✅ |
| **Boost/Spotlight** | ✅ (Boost) | ✅ (Spotlight) | ❌ | ❌ |
| **Applications** | ✅ | ❌ | ❌ | ❌ |
| **Pay Ranges** | ✅ | ❌ | ❌ | ❌ |
| **Dealer Management** | ❌ | ✅ | ✅ | ❌ |
| **Employer Features** | ✅ | ❌ | ❌ | ❌ |
| **Rentals** | ❌ | ✅ | ❌ | ✅ |
| **Feed Integration** | ✅ (XML) | ✅ (CSV) | ✅ (CSV) | ❌ |
| **Abuse Reporting** | ✅ | ✅ | ✅ | ✅ |
| **Statistics** | ✅ | ✅ | ✅ | ✅ |
| **Categories** | ✅ (38 subcats) | ✅ (hierarchical) | ✅ (make/model) | ✅ (property types) |

---

## Technical Requirements

### Data Storage
- **MongoDB**: Primary data store for listings, favorites, saved searches, dealers, categories
- **Elasticsearch**: Search index for all listing types
- **Redis**: Caching layer (replacing Memcached)
- **S3**: Photo/video storage (via image services)
- **BigQuery**: Analytics and statistics (via reports service)

### External Services
- **Member API**: Authentication and user management
- **Image Services**: Photo/video upload and processing
- **Reports Service**: Statistics and analytics
- **Payment Service**: Stripe integration
- **Email Service**: Notification delivery
- **Applications Service**: Job application processing (separate microservice)
- **PubSub**: Feed data distribution

### Authentication
- JWT token-based authentication
- Integration with Member API
- Support for anonymous operations (limited)

### Performance
- Response time < 200ms for listing retrieval
- Search results < 500ms
- Photo upload < 5s (depends on image service)
- Cache frequently accessed data (categories, metadata)

### Scalability
- Horizontal scaling support
- Stateless service design
- Database connection pooling
- Elasticsearch cluster support

---

## Success Metrics

### Functional
- ✅ 100% feature parity with legacy Jobs system
- ✅ 100% feature parity with legacy Classifieds API
- ✅ Zero data loss during migration
- ✅ All existing API consumers migrated successfully

### Performance
- ✅ Average response time < 200ms
- ✅ 99.9% uptime
- ✅ Support for 10,000+ concurrent users
- ✅ Search results < 500ms (p95)

### Quality
- ✅ Unit test coverage > 80%
- ✅ Integration test coverage for all critical paths
- ✅ Zero critical bugs in production after 30 days
- ✅ API documentation complete and accurate

---

## Notes

- Authentication endpoints are NOT migrated (handled by Member API)
- Statistics endpoints are NOT migrated (handled by existing `reports-http-rest` service)
- Job applications are a SEPARATE microservice (`listing-applications`)
- Feed processing uses PubSub architecture (parser → pubsub → subscriber → REST API)
- Virus scanning infrastructure details: TODO @Chris
