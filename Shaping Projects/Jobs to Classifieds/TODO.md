# TODO: Unified Listing Service - Implementation Review Checklist

This checklist breaks down all work needed to implement the unified listing service consolidating Jobs, Classifieds, Cars, and Homes.

**Legend:**
- 🔴 Critical/Blocker
- 🟡 Important
- 🟢 Nice to have
- 📋 Research needed
- ⏰ Cron/scheduled task

---

## Phase 1: Core API Endpoints (MVP)

### Listing CRUD Operations

- [ ] 🔴 **POST /listings/create-draft** - Create listing draft
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::createStub()`
  - Legacy route: `listingsCreateStub`
  - Validates: listingType, title, contact info, location
  - Sets status to "Draft"
  - Generates unique listing ID
  - TODO: Determine default expiration dates per vertical (Jobs: 30d, Classifieds: varies by category)
  - TODO: Validate required fields per listingType discriminator
  - TODO: Handle authorized users array for dealer accounts

- [ ] 🔴 **GET /listings/{id}** - Get listing by ID
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::getListing()`
  - Legacy route: `listingsGet`
  - Public endpoint (no auth required for active listings)
  - Return different fields based on listingType
  - TODO: Implement view tracking (increment stats.viewCount)
  - TODO: Check if listing is visible (not deleted, not expired unless owner)
  - TODO: Populate dealerData from dealer collection
  - TODO: Return carfax/autocheck URLs for cars

- [ ] 🔴 **PUT /listings/{id}** - Update listing
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::updateListing()`
  - Legacy route: `listingsUpdate`
  - Validate owner or authorized user
  - Append change to history array
  - Update modifyTime timestamp
  - TODO: Re-index in Elasticsearch after update
  - TODO: Handle price change → check for price drop notification trigger
  - TODO: Validate category-specific specifications
  - TODO: Handle status transitions (Draft → Active requires payment check)

- [ ] 🔴 **DELETE /listings/{id}** - Delete listing (soft delete)
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::deleteListing()`
  - Legacy route: `listingsDelete`
  - Soft delete: set status to "Deleted", set deleteTime
  - Validate owner only
  - TODO: Remove from Elasticsearch active index
  - TODO: Archive to separate collection or mark in same collection
  - TODO: Cancel any scheduled boosts (Jobs)
  - TODO: Notify favorites users of deletion

- [ ] 🔴 **PUT /listings/{id}/renew** - Renew listing
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::renewListing()`
  - Legacy route: `listingsRenew`
  - Extends expireTime by configured duration
  - May require payment (check pricing)
  - Update displayTime to current
  - TODO: Check renewal eligibility (not deleted, owner match)
  - TODO: Calculate renewal fee (category-dependent)
  - TODO: Create payment intent via Stripe if fee required
  - TODO: Update Elasticsearch with new expireTime

- [ ] 🟡 **PUT /listings/{id}/expire** - Manually expire listing
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php` (inferred)
  - Jobs-specific endpoint
  - Sets status to "Expired"
  - Sets expireTime to now
  - TODO: Only allow for Jobs vertical
  - TODO: Validate owner
  - TODO: Remove from active search index
  - TODO: Trigger expiration notifications

- [ ] 🟡 **PUT /listings/{id}/mark-sold** - Mark listing as sold
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php` (inferred)
  - Classifieds/Cars/Homes only
  - Sets status to "Sold"
  - TODO: Prevent for Jobs vertical
  - TODO: Validate owner
  - TODO: Archive from active listings
  - TODO: Notify favorited users

- [ ] 🔴 **GET /listings/{id}/thanks-page** - Get listing data for thanks page
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::getListingThanksPage()`
  - Legacy route: `listingsGetThanksPage`
  - Return listing data for post-creation confirmation
  - Include stats, payment info, featured status
  - TODO: Include promotional messaging based on vertical
  - TODO: Include upsell opportunities (Top Job, Featured, etc.)

### Listing Support/Metadata Endpoints

- [ ] 🔴 **GET /listings/meta** - Get listing metadata
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::getListingMeta()`
  - Legacy route: `getListingsMeta`
  - Return category tree
  - Return employment types (Jobs)
  - Return education levels (Jobs)
  - Return market types (Classifieds)
  - TODO: Cache response (Redis, 1hr TTL)
  - TODO: Include category-specific field definitions

- [ ] 🟡 **GET /listings/contact-info** - Get user's default contact info
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::getListingContactInfo()`
  - Legacy route: `getListingsContactInfo`
  - Returns authenticated user's saved contact preferences
  - TODO: Fetch from Member API
  - TODO: Include phone, email, display preferences
  - TODO: Handle dealer accounts (return dealer contact info)

- [ ] 🟡 **GET /listings/renew-data** - Get renewal pricing and support data
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::getRenewListingSupportData()`
  - Legacy route: `getListingsRenewData`
  - Returns renewal fee and duration
  - TODO: Calculate based on category and vertical
  - TODO: Check for dealer discounts
  - TODO: Return payment options

- [ ] 🟡 **GET /listings/predefined-rental-rules** - Get rental rule templates
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::getPredefinedRentalRules()`
  - Legacy route: `getPredefinedRentalRules`
  - Returns common rental rules for Homes/Classifieds rentals
  - TODO: Store templates in MongoDB
  - TODO: Allow customization per listing

- [ ] 🟡 **POST /listings/paid-info** - Get paid feature info for listings
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::getListingsPaidInfo()`
  - Legacy route: `listingGetListingsPaidInfo`
  - Accepts array of listing IDs
  - Returns featured dates, spotlight status, payment history
  - TODO: Aggregate from subscription/payment collections
  - TODO: Include Top Job status and dates (Jobs)

### Search Endpoints

- [ ] 🔴 **GET /listings** - Search listings
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::getListings()`
  - Legacy route: `listingsSearch`
  - Public endpoint (no auth)
  - Elasticsearch-backed search
  - Query params: keyword, listingType, category, subCategory, city, state, zip, radius, priceMin, priceMax, marketType, topJobsOnly, featured, sort, page, perPage
  - TODO: Build Elasticsearch query with all filters
  - TODO: Implement faceted search (category counts, price ranges)
  - TODO: Exclude deleted/expired unless admin
  - TODO: Sort options: date_desc (default), date_asc, price_desc, price_asc, relevance
  - TODO: Pagination: default 20/page, max 100/page
  - TODO: Cache popular searches (Redis, 5min TTL)
  - TODO: Track search queries for analytics

- [ ] 🟡 **GET /suggester/keyword-search-suggestions** - Keyword autocomplete
  - Reference: `m-ksl-classifieds-api/src/Controller/SuggesterController.php::getKeywordSearchSuggestions()`
  - Legacy route: `getKeywordSearchSuggestions`
  - Returns autocomplete suggestions
  - Uses Elasticsearch suggester
  - TODO: Limit to 10 results by default
  - TODO: Base suggestions on title and description fields
  - TODO: Cache frequent queries

- [ ] 🟡 **GET /suggester/suggested-categories** - Category suggestions
  - Reference: `m-ksl-classifieds-api/src/Controller/SuggesterController.php::getSuggestedCategories()`
  - Legacy route: `getSuggestedCategories`
  - Suggest categories based on query text
  - TODO: Use Elasticsearch category analyzer
  - TODO: Return category hierarchy with each suggestion

### Photo Management Endpoints

- [ ] 🔴 **POST /listings/{id}/photos** - Upload listing photo
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::uploadListingPhoto()`
  - Legacy route: `listingsUploadListingPhoto`
  - Upload to S3 via image upload service
  - Multipart/form-data upload
  - TODO: Call http-image-upload service (images-services repo)
  - TODO: Validate file size (max 10MB)
  - TODO: Validate file type (jpg, png, webp)
  - TODO: Generate thumbnails via image service
  - TODO: Store photo metadata in listing.photos array
  - TODO: Set as primaryImage if first photo
  - TODO: Enforce max photo count (varies by vertical and plan)
  - TODO: Update modifyTime on listing

- [ ] 🟡 **POST /listings/{id}/photos/{photoId}** - Edit photo metadata
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::editListingPhoto()`
  - Legacy route: `listingsEditListingPhoto`
  - Update caption, order, description
  - TODO: Validate photo exists in listing
  - TODO: Validate owner
  - TODO: Update photo in listing.photos array
  - TODO: Handle reordering (update order field on all photos)

- [ ] 🟡 **DELETE /listings/{id}/photos/{photoId}** - Delete photo
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::deleteListingPhoto()`
  - Legacy route: `listingsDeleteListingPhoto`
  - Remove photo from listing
  - TODO: Delete from S3 via image service
  - TODO: Remove from listing.photos array
  - TODO: If was primaryImage, set new primaryImage (first remaining photo)
  - TODO: Validate owner

### Favorites Endpoints

- [ ] 🟡 **POST /listings/{listingId}/favorites** - Favorite a listing
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingFavoriteController.php::createListingFavorite()`
  - Legacy route: `listingsFavoritesCreate`
  - Create favorite for authenticated user
  - Optional: notifyOnPriceDrop, notifyOnExpiration
  - TODO: Store in separate favorites collection or user document
  - TODO: Increment listing.stats.favoriteCount
  - TODO: Prevent duplicate favorites (409 if exists)
  - TODO: Subscribe to price drop notifications if requested

- [ ] 🟡 **PUT /listings/{listingId}/favorites** - Update favorite settings
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingFavoriteController.php::updateListingFavorite()`
  - Legacy route: `listingsFavoritesUpdate`
  - Update notification settings
  - TODO: Update favorite document
  - TODO: Subscribe/unsubscribe from notifications

- [ ] 🟡 **DELETE /listings/{listingId}/favorites** - Unfavorite listing
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingFavoriteController.php::deleteListingFavorite()`
  - Legacy route: `listingsFavoritesDelete`
  - Remove favorite
  - TODO: Delete favorite document
  - TODO: Decrement listing.stats.favoriteCount
  - TODO: Unsubscribe from all notifications

### Saved Searches Endpoints

- [ ] 🟡 **POST /saved-searches** - Create saved search
  - Reference: `m-ksl-classifieds-api/src/Controller/SavedSearchController.php::createSavedSearch()`
  - Legacy route: `savedSearchesCreate`
  - Save search filters for quick access
  - Optional: notifyOnMatch (alert when new listings match)
  - TODO: Store search criteria in saved_searches collection
  - TODO: Link to member ID
  - TODO: Set up percolation query in Elasticsearch if notifications enabled
  - TODO: Max saved searches per user (e.g., 10)

- [ ] 🟡 **PUT /saved-searches/{id}** - Update saved search
  - Reference: `m-ksl-classifieds-api/src/Controller/SavedSearchController.php::updateSavedSearch()`
  - Legacy route: `savedSearchesUpdate`
  - Update filters or notification settings
  - TODO: Validate owner
  - TODO: Update percolation query if filters changed
  - TODO: Update notification subscription

- [ ] 🟡 **DELETE /saved-searches/{id}** - Delete saved search
  - New endpoint (inferred from common pattern)
  - TODO: Validate owner
  - TODO: Remove percolation query
  - TODO: Unsubscribe from notifications
  - TODO: Delete saved search document

### Category Endpoints

- [ ] 🔴 **GET /categories** - Get category tree
  - Reference: `m-ksl-classifieds-api/src/Controller/CategoryController.php::getCategoriesTree()`
  - Legacy route: `getCategoriesTree`
  - Public endpoint
  - Return full category hierarchy
  - TODO: Include subcategories nested
  - TODO: Cache response (Redis, 1hr TTL)
  - TODO: Filter by vertical if specified

- [ ] 🟡 **GET /category-filters** - Get category filters
  - Reference: `m-ksl-classifieds-api/src/Controller/CategoryController.php::getCategoryFilters()`
  - Legacy route: `getCategoryFilters`
  - Public endpoint
  - Returns available filters for a category
  - TODO: Return facets available for the category/subcategory
  - TODO: Include value ranges (e.g., price ranges)

- [ ] 🔴 **GET /sub-categories/specifications** - Get subcategory specs
  - Reference: `m-ksl-classifieds-api/src/Controller/CategoryController.php::getSubCategorySpecifications()`
  - Legacy route: `getSpecification`
  - Public endpoint
  - Returns dynamic field specifications for subcategory
  - TODO: Return field names, types, options, validation rules
  - TODO: Use for dynamic form generation on frontend
  - TODO: Cache per subcategory (Redis, 1hr TTL)

---

## Phase 1: Jobs-Specific Features

### Boost Endpoints

- [ ] 🟡 **POST /listings/{id}/boost** - Boost listing to top (Jobs)
  - Reference: Jobs system research (Top Jobs feature)
  - Boost job listing to top of search results
  - Free boost: once per listing
  - Paid boost: unlimited
  - TODO: Validate listingType is JOB
  - TODO: Check allowFreeBoost flag (one-time use)
  - TODO: Create payment intent if paid boost
  - TODO: Update topJob flag and topJobTime timestamp
  - TODO: Add to boostHistory array
  - TODO: Re-index with boosted ranking in Elasticsearch
  - TODO: Track boost in analytics

- [ ] 🟡 **PUT /listings/{id}/auto-boost** - Configure auto-boost
  - Reference: Jobs system research (scheduled boosts)
  - Configure automatic boost schedule
  - Frequency: every 3, 7, or 14 days
  - TODO: Validate listingType is JOB
  - TODO: Store autoBoost config (enabled, frequency)
  - TODO: Calculate and store scheduledBoosts timestamps
  - TODO: Create cron/worker to process scheduled boosts
  - TODO: Require payment method on file for auto-boost

### Pay Range Display

- [ ] 🔴 **Display pay ranges on job listings**
  - Reference: Engineer Research/Pay ranges doc
  - Show salary or hourly range
  - Fields: payRangeType (hourly|salary), salaryFrom, salaryTo, hourlyFrom, hourlyTo
  - TODO: Validate ranges (from <= to)
  - TODO: Display format: "$50,000 - $75,000/year" or "$20 - $30/hour"
  - TODO: Support "Competitive" or blank (don't display)
  - TODO: Include in search results and detail page

---

## Phase 1: Payment Integration

- [ ] 🔴 **Payment intent creation**
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::createPaymentIntent()`
  - Legacy route: `listingsСreatePaymentIntent`
  - Create Stripe payment intent for listing fees
  - TODO: Calculate amount based on category, vertical, features
  - TODO: Support discounts/promo codes
  - TODO: Store transaction in purchaseHistory
  - TODO: Link to subscription if recurring
  - TODO: Handle payment success webhook

- [ ] 🟡 **Stripe webhook handling**
  - Reference: `m-ksl-classifieds-api/src/Controller/PaymentController.php::handleSubscriptionEvent()`
  - Legacy route: `paymentsHandleSubscriptionEvent`
  - TODO: Verify webhook signature
  - TODO: Handle payment_intent.succeeded → activate listing
  - TODO: Handle subscription.created → link to listing
  - TODO: Handle subscription.canceled → expire listing
  - TODO: Handle payment failure → mark pending or revert status

---

## Phase 2: Advanced Features

### Archive Operations

- [ ] 🟡 **GET /archive-listings** - Search archived listings
  - Reference: `m-ksl-classifieds-api/src/Controller/ArchiveListingController.php::getListings()`
  - Legacy route: `getArchivedListings`
  - Search expired/sold listings
  - TODO: Similar filters to active search
  - TODO: Include date range filter
  - TODO: Admin or owner only

- [ ] 🟡 **PUT /archive-listings** - Restore archived listings
  - Reference: `m-ksl-classifieds-api/src/Controller/ArchiveListingController.php::restoreListings()`
  - Legacy route: `restoreArchivedListing`
  - Restore listing from archive to active
  - TODO: Validate owner
  - TODO: May require new payment
  - TODO: Reset expireTime
  - TODO: Re-index in Elasticsearch

### Dealer Endpoints

- [ ] 🟡 **GET /dealer/{dealerId}** - Get dealer information
  - Reference: `m-ksl-classifieds-api/src/Controller/DealerController.php::getDealer()`
  - Legacy route: `getDealer`
  - Public endpoint
  - Returns dealer profile, logo, listings count
  - TODO: Aggregate active listings count
  - TODO: Cache dealer profile (Redis, 30min TTL)

- [ ] 📋 **Dealer logo management** - POST/DELETE /dealer/{dealerId}/logo
  - Reference: `m-ksl-classifieds-api/src/Controller/DealerController.php`
  - Legacy routes: `dealerAddLogo`, `dealerDeleteLogo`
  - TODO: Research if needed for Phase 2
  - TODO: Use image service for upload
  - TODO: Store logo URL in dealer document

- [ ] 📋 **Dealer CSL config** - Dealer-specific configuration
  - Reference: `m-ksl-classifieds-api/src/Controller/DealerController.php`
  - Legacy routes: `addDealerCslConfigItem`, `getDealerCslConfig`, `removeDealerCslConfigItem`
  - TODO: Research what CSL config is
  - TODO: Determine if needed in new system

### Abuse Reporting

- [ ] 🟡 **GET /abuse/{listingId}** - Get listing abuse record
  - Reference: `m-ksl-classifieds-api/src/Controller/AbuseController.php::getListingAbuseRecord()`
  - Legacy route: `abuseGetListingAbuseRecord`
  - Admin only
  - Returns abuse reports for listing
  - TODO: Include report count, status, moderator notes

- [ ] 🟡 **POST /abuse/{listingId}/reports** - Create abuse report
  - Reference: `m-ksl-classifieds-api/src/Controller/AbuseController.php::createUserReport()`
  - Legacy route: `abuseCreateUserReport`
  - User reports listing for abuse
  - Reasons: spam, fraud, inappropriate, wrong category, etc.
  - TODO: Store in abuseReports array on listing
  - TODO: Increment report count
  - TODO: Auto-hide if report threshold exceeded
  - TODO: Notify moderation queue

- [ ] 🟡 **PUT /abuse/{listingId}/review** - Review abuse report
  - Reference: `m-ksl-classifieds-api/src/Controller/AbuseController.php::reviewListingAbuseRecord()`
  - Legacy route: `abuseReviewListingAbuseRecord`
  - Admin only
  - Moderator reviews and actions report
  - TODO: Update abuse record status (pending, reviewed, actioned, dismissed)
  - TODO: Store moderator ID and timestamp
  - TODO: Action: delete listing, warn user, dismiss

- [ ] 🟡 **GET /abuse** - Get all abuse records
  - Reference: `m-ksl-classifieds-api/src/Controller/AbuseController.php::getListingsAbuseRecords()`
  - Legacy route: `abuseGetListingsAbuseRecords`
  - Admin only
  - Returns all listings with abuse reports
  - TODO: Filter by status (pending, reviewed, etc.)
  - TODO: Sort by report count, date
  - TODO: Paginate results

### Member Operations

- [ ] 📋 **PUT /listings/member/{memberId}/toggle-hidden/{setHidden}** - Toggle member listings hidden
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::toggleMemberListingsHidden()`
  - Legacy route: `listingsMemberToggleHidden`
  - TODO: Research use case
  - TODO: Bulk operation on all member listings
  - TODO: Admin only?

- [ ] 📋 **GET /listings/member/{memberId}/listings-status** - Get member listings status
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::getMemberListingsStatus()`
  - Legacy route: `listingsMemberGetListingsStatus`
  - TODO: Research what status info is needed
  - TODO: Count by status (active, expired, deleted, etc.)

- [ ] 📋 **PUT /listings/member/{memberId}/verification-status** - Update member verification
  - Reference: `m-ksl-classifieds-api/src/Controller/ListingController.php::updateMemberVerificationStatus()`
  - Legacy route: `listingsMemberUpdateVerificationStatus`
  - TODO: Research verification system
  - TODO: Admin only
  - TODO: May affect listing visibility

### Homepage/Dashboard Endpoints

- [ ] 🟡 **GET /homepage/get-meta-data** - Get homepage metadata
  - Reference: `m-ksl-classifieds-api/src/Controller/HomepageController.php::getMetaData()`
  - Legacy route: `homepageGetMetaData`
  - Returns categories, featured listings, user preferences
  - TODO: Aggregate multiple data sources
  - TODO: Personalize based on user preferences
  - TODO: Cache for anonymous users

- [ ] 🟡 **GET /homepage/my-listings** - Get user's listings
  - Reference: `m-ksl-classifieds-api/src/Controller/HomepageController.php::getMyListings()`
  - Legacy route: `homepageGetMyListings`
  - Returns authenticated user's listings
  - TODO: Group by status (active, expired, pending, etc.)
  - TODO: Include stats (views, favorites, etc.)
  - TODO: Sort by most recent

- [ ] 🟡 **GET /homepage/my-favorites** - Get user's favorites
  - Reference: `m-ksl-classifieds-api/src/Controller/HomepageController.php::getMyFavorites()`
  - Legacy route: `homepageGetMyFavorites`
  - Returns favorited listings
  - TODO: Include price drop notifications
  - TODO: Mark expired/sold listings
  - TODO: Paginate results

- [ ] 🟡 **GET /homepage/saved-search/{savedSearchId}/listings** - Get saved search results
  - Reference: `m-ksl-classifieds-api/src/Controller/HomepageController.php::getSavedSearchListings()`
  - Legacy route: `homepageGetSavedSearchListings`
  - Execute saved search and return results
  - TODO: Apply saved filters
  - TODO: Include new matches count since last view
  - TODO: Cache results briefly

### Management/Admin Endpoints

- [ ] 📋 **PUT /management/dealer-monthly-email/{memberId}** - Send dealer monthly email
  - Reference: `m-ksl-classifieds-api/src/Controller/ManagementController.php::sendDealerMonthlyEmail()`
  - Legacy route: `managementDealerMonthlyEmail`
  - Admin only
  - TODO: Research monthly email content
  - TODO: Use email service (Mandrill)
  - TODO: Include stats, renewals, upsells

- [ ] 📋 **PUT /management/update-batch-listings/** - Batch update listings
  - Reference: `m-ksl-classifieds-api/src/Controller/ManagementController.php::updateBatchListings()`
  - Legacy route: `managementUpdateBatchListings`
  - Admin only
  - TODO: Research use cases
  - TODO: Support bulk operations (change category, update dealer, etc.)

- [ ] 📋 **PUT /management/update-member-listings-dealer-data/{memberId}** - Update dealer data
  - Reference: `m-ksl-classifieds-api/src/Controller/ManagementController.php::updateMemberListingsDealerData()`
  - Legacy route: `managementUpdateMemberListingsDealerData`
  - Admin only
  - TODO: Research when dealer data needs bulk update
  - TODO: Update all listings for a member

---

## Phase 2: Notification Systems

### Price Drop Notifications

- [ ] 🟡 **POST /price-drop/notifications** - Handle price drop notification
  - Reference: `m-ksl-classifieds-api/src/Controller/PriceDropController.php::handlePriceDropNotification()`
  - Legacy route: `priceDropNotify`
  - Triggered when listing price is reduced
  - TODO: Find all users who favorited with notifyOnPriceDrop=true
  - TODO: Send notification via push/email
  - TODO: Track notification sent in listing.history
  - TODO: Use saved-search-alert-workers service pattern

### Expiration Notifications

- [ ] 🟡 **POST /expiration/notify-seller** - Notify seller of expiration
  - Reference: `m-ksl-classifieds-api/src/Controller/ExpirationController.php::handleSellerExpirationNotification()`
  - Legacy route: `expirationNotifySeller`
  - Notifies listing owner before expiration
  - TODO: Send 3 days before, 1 day before
  - TODO: Include renewal link
  - TODO: Track notification sent

- [ ] 🟡 **POST /expiration/notify-buyers** - Notify favorited users
  - Reference: `m-ksl-classifieds-api/src/Controller/ExpirationController.php::handleBuyersExpirationNotification()`
  - Legacy route: `expirationNotifyBuyers`
  - Notifies users who favorited with notifyOnExpiration=true
  - TODO: Send when listing expires
  - TODO: Suggest similar listings

- [ ] 🟡 **GET /expiration/listings** - Get expiring listings
  - Reference: `m-ksl-classifieds-api/src/Controller/ExpirationController.php::getListings()`
  - Legacy route: `expirationListings`
  - Admin/cron endpoint
  - Returns listings expiring soon
  - TODO: Filter by date range
  - TODO: Group by notification type (seller, buyers)

---

## Cron Jobs / Workers

### Listing Lifecycle Workers

- [ ] ⏰ **Expire listings cron** - Auto-expire listings past expireTime
  - Runs: Every hour (or more frequently)
  - TODO: Find all listings where expireTime < now AND status = "Active"
  - TODO: Set status = "Expired"
  - TODO: Remove from Elasticsearch active index
  - TODO: Trigger expiration notifications
  - TODO: Log in listing.history

- [ ] ⏰ **Auto-boost cron** - Process scheduled boosts (Jobs)
  - Reference: Jobs Top Jobs research
  - Runs: Every hour
  - TODO: Find all listings with autoBoost.enabled=true AND nextBoostTime <= now
  - TODO: Perform boost (update topJobTime, re-index)
  - TODO: Calculate next boost time based on frequency
  - TODO: Charge payment method on file
  - TODO: Disable auto-boost if payment fails

- [ ] ⏰ **Expiration reminder cron** - Send expiration reminders
  - Runs: Daily
  - TODO: Find listings expiring in 3 days → send seller reminder
  - TODO: Find listings expiring in 1 day → send seller reminder
  - TODO: Find listings that just expired → send buyer notifications
  - TODO: Use notification service

- [ ] ⏰ **Archive old listings cron** - Move very old listings to archive
  - Runs: Daily
  - TODO: Find listings where status IN ("Expired", "Sold", "Deleted") AND expireTime < (now - 90 days)
  - TODO: Move to archive collection or flag
  - TODO: Remove from Elasticsearch active index (if not already)
  - TODO: Keep for historical/stats purposes

### Feed Processing Workers

- [ ] ⏰ **Feed parser cron** - Parse XML job feeds
  - Reference: Engineer Research/Job Feeds doc, Services.md (listing-feed-parser service)
  - Runs: Hourly or on schedule per dealer
  - Separate microservice: listing-feed-parser
  - TODO: Fetch XML from dealer feed URLs
  - TODO: Parse and validate XML
  - TODO: Transform to listing format
  - TODO: Publish to PubSub topic: listing-feed-events
  - TODO: Handle errors (malformed XML, invalid data)

- [ ] ⏰ **Feed subscriber worker** - Process feed events from PubSub
  - Reference: Services.md (listing-feed-subscriber service)
  - Runs: Continuously (subscribe to PubSub)
  - Separate microservice: listing-feed-subscriber
  - TODO: Subscribe to listing-feed-events topic
  - TODO: For each event, call REST API to create/update listing
  - TODO: POST /listings/create-draft or PUT /listings/{id}
  - TODO: Handle duplicates (match on externalId/feedJobId)
  - TODO: Retry on failure with exponential backoff
  - TODO: Dead letter queue for persistent failures

### Search Index Maintenance

- [ ] ⏰ **Reindex Elasticsearch cron** - Full reindex periodically
  - Runs: Weekly
  - TODO: Read all active listings from MongoDB
  - TODO: Bulk index to Elasticsearch
  - TODO: Swap to new index (zero-downtime)
  - TODO: Delete old index
  - TODO: Monitor for failures

---

## Data Layer TODOs

### MongoDB

- [ ] 🔴 **Design unified listings collection schema**
  - Discriminator field: listingType (JOB, CLASSIFIED, CAR, HOME_BUY, HOME_RENT)
  - Vertical-specific fields in nested objects (jobDetails, carDetails, etc.)
  - TODO: Define indexes (memberId, status, expireTime, category, location)
  - TODO: Compound index for search: (status, listingType, category, expireTime)
  - TODO: Geospatial index for location coordinates
  - TODO: Text index for title and description (or rely on Elasticsearch)

- [ ] 🔴 **Create categories collection**
  - Store category tree with hierarchy
  - TODO: Parent/child relationships
  - TODO: Index on category ID
  - TODO: Cache in Redis

- [ ] 🟡 **Create dealers collection**
  - Store dealer profiles, logos, integrations
  - TODO: Index on dealer ID
  - TODO: Link to members collection (Member API)

- [ ] 🟡 **Create favorites collection**
  - memberId, listingId, notification settings, createTime
  - TODO: Compound index: (memberId, listingId) unique
  - TODO: Index on listingId for aggregation

- [ ] 🟡 **Create saved_searches collection**
  - memberId, name, filters (JSON), notifyOnMatch, createTime
  - TODO: Index on memberId
  - TODO: Limit per user (e.g., 10)

- [ ] 🟡 **Create abuse_reports collection** (or embed in listings)
  - Option A: Separate collection with listingId reference
  - Option B: Embed in listings.abuseReports array
  - TODO: Decide on approach
  - TODO: Index on status for moderation queue

### Elasticsearch

- [ ] 🔴 **Define listings index mapping**
  - Fields: id, listingType, status, title, description, price, location (geo_point), category, subCategory, createTime, displayTime, expireTime, topJob, isFeatured, memberId
  - Analyzers: Standard for title/description, keyword for category
  - TODO: Include all searchable fields
  - TODO: Nested objects for carDetails, jobDetails, etc.
  - TODO: Geo-point for location-based search
  - TODO: Suggester for autocomplete

- [ ] 🔴 **Create index update pipeline**
  - TODO: Index on create
  - TODO: Update on listing change
  - TODO: Remove on delete/expire
  - TODO: Bulk operations for efficiency
  - TODO: Handle reindex for schema changes

- [ ] 🟡 **Set up percolation queries for saved search alerts**
  - Store saved search filters as percolation queries
  - TODO: Match new listings against saved searches
  - TODO: Trigger notifications for matches
  - TODO: Use saved-search-match-service pattern

### Redis

- [ ] 🔴 **Set up caching strategy**
  - Cache: category tree (1hr TTL)
  - Cache: listing metadata (1hr TTL)
  - Cache: dealer profiles (30min TTL)
  - Cache: popular searches (5min TTL)
  - TODO: Use consistent key naming (e.g., "listings:meta", "dealer:{id}")
  - TODO: Implement cache invalidation on updates
  - TODO: Monitor hit rates

---

## Integration TODOs

### Image Service Integration

- [ ] 🔴 **Integrate with http-image-upload service**
  - Reference: images-services/http-image-upload
  - Upload photos to S3
  - Generate thumbnails
  - TODO: Call upload endpoint with multipart form data
  - TODO: Receive S3 URL and thumbnail URLs
  - TODO: Store URLs in listing.photos array

- [ ] 🔴 **Integrate with http-image-download service**
  - Reference: images-services/http-image-download
  - Serve images with resizing
  - TODO: Return image URLs using download service
  - TODO: Support different sizes (thumbnail, small, medium, large, original)

### Member API Integration

- [ ] 🔴 **Authenticate via Member API**
  - JWT token validation
  - TODO: Verify bearer token on protected endpoints
  - TODO: Extract member ID from token
  - TODO: Check authorization (owner, authorized user, dealer)

- [ ] 🟡 **Fetch member contact info**
  - For GET /listings/contact-info
  - TODO: Call Member API to get user profile
  - TODO: Return default contact preferences

### Statistics Service Integration (No Migration Needed)

- [ ] 🔴 **Track listing views/clicks via reports-http-rest**
  - Reference: Services.md (existing reports-http-rest service)
  - Increment view count, email count, phone count
  - TODO: Call reports service endpoint on each action
  - TODO: Async/fire-and-forget to avoid blocking
  - TODO: Aggregate stats periodically and store in listing.stats

### Payment Service Integration

- [ ] 🔴 **Create Stripe payment intents**
  - For listing fees, renewals, Top Jobs, featured listings
  - TODO: Call Stripe API to create payment intent
  - TODO: Return client secret to frontend
  - TODO: Store transaction in listing.purchaseHistory
  - TODO: Link to subscription if recurring

- [ ] 🔴 **Handle Stripe webhooks**
  - payment_intent.succeeded, payment_intent.failed
  - subscription.created, subscription.updated, subscription.canceled
  - TODO: Verify webhook signature
  - TODO: Update listing status on payment success
  - TODO: Handle payment failures (notify user, mark pending)

### Notification Service Integration

- [ ] 🟡 **Send push notifications**
  - Reference: push-notifications-service repo
  - Price drops, expiration reminders, new matches
  - TODO: Call push notification service API
  - TODO: Include listing data, action links
  - TODO: Handle opt-out preferences

- [ ] 🟡 **Send email notifications**
  - Via Mandrill or similar
  - TODO: Use email templates
  - TODO: Include unsubscribe links
  - TODO: Track email sends

### Saved Search Alert Integration

- [ ] 🟡 **Integrate with saved-search-alert-workers**
  - Reference: saved-search-alert-workers repo
  - Notify users when new listings match saved searches
  - TODO: Publish new listing events to PubSub
  - TODO: Workers match against saved searches (percolation)
  - TODO: Send notifications for matches
  - TODO: Use saved-search-match-service for percolation

---

## Testing TODOs

### Unit Tests

- [ ] 🔴 **Test listing CRUD handlers**
  - Test create, get, update, delete operations
  - Mock database calls
  - TODO: Test validation logic
  - TODO: Test authorization checks
  - TODO: Test error handling

- [ ] 🔴 **Test search functionality**
  - Test Elasticsearch query building
  - Mock Elasticsearch client
  - TODO: Test all filter combinations
  - TODO: Test sorting and pagination
  - TODO: Test faceting

- [ ] 🟡 **Test payment integration**
  - Mock Stripe API
  - TODO: Test payment intent creation
  - TODO: Test webhook handling
  - TODO: Test failure scenarios

### Integration Tests

- [ ] 🔴 **Test full listing lifecycle**
  - Create draft → update → publish → renew → expire
  - Use test database
  - TODO: Verify status transitions
  - TODO: Verify Elasticsearch indexing
  - TODO: Verify timestamps

- [ ] 🟡 **Test photo upload flow**
  - Upload → edit → delete
  - Use mock image service or test environment
  - TODO: Verify S3 upload
  - TODO: Verify thumbnail generation
  - TODO: Verify photo metadata storage

- [ ] 🟡 **Test search and filters**
  - Index test data in Elasticsearch
  - TODO: Test various search queries
  - TODO: Verify facets
  - TODO: Verify pagination

### E2E Tests

- [ ] 🟡 **Test complete user flows**
  - User creates listing → uploads photos → publishes → searches → updates → renews
  - Use staging environment
  - TODO: Test across all verticals (Jobs, Classifieds, Cars, Homes)
  - TODO: Test error cases (validation failures, auth errors)

---

## Deployment TODOs

### Infrastructure

- [ ] 🔴 **Set up Kubernetes deployment**
  - Reference: Services.md deployment section
  - listing-http-rest service
  - listing-applications service (Quick Apply)
  - listing-feed-parser service
  - listing-feed-subscriber service
  - TODO: Define resource limits (CPU, memory)
  - TODO: Set up autoscaling (HPA)
  - TODO: Configure health checks

- [ ] 🔴 **Set up MongoDB**
  - TODO: Create listings database
  - TODO: Create collections (listings, categories, dealers, favorites, saved_searches)
  - TODO: Set up indexes
  - TODO: Configure replication
  - TODO: Set up backups

- [ ] 🔴 **Set up Elasticsearch**
  - TODO: Create listings index
  - TODO: Define mapping
  - TODO: Set up cluster (3 nodes)
  - TODO: Configure backups/snapshots

- [ ] 🔴 **Set up Redis**
  - TODO: Deploy Redis cluster or standalone
  - TODO: Configure persistence (optional)
  - TODO: Set memory limits

- [ ] 🔴 **Set up PubSub**
  - TODO: Create topic: listing-feed-events
  - TODO: Create subscription for listing-feed-subscriber
  - TODO: Configure retry policy
  - TODO: Set up dead letter queue

### CI/CD

- [ ] 🔴 **Set up CI pipeline**
  - TODO: Run unit tests on PR
  - TODO: Run linting and formatting checks
  - TODO: Build Docker images
  - TODO: Push images to container registry

- [ ] 🔴 **Set up CD pipeline**
  - TODO: Deploy to staging on merge to main
  - TODO: Run integration tests in staging
  - TODO: Deploy to production on tag/manual trigger
  - TODO: Blue-green or canary deployment

### Monitoring & Observability

- [ ] 🔴 **Set up logging**
  - Reference: golang-o11y repo for Go logging patterns
  - TODO: Structured logging (JSON)
  - TODO: Log to stdout (captured by Kubernetes)
  - TODO: Aggregate logs (e.g., CloudWatch, Datadog)
  - TODO: Set log levels (debug, info, warn, error)

- [ ] 🔴 **Set up metrics**
  - Reference: golang-o11y repo for metrics
  - TODO: Expose Prometheus metrics endpoint
  - TODO: Track request latency, error rates, DB query times
  - TODO: Create Datadog dashboards
  - TODO: Set up alerts (high error rate, slow responses)

- [ ] 🔴 **Set up tracing**
  - Reference: golang-o11y repo for distributed tracing
  - TODO: Implement OpenTelemetry tracing
  - TODO: Trace request flow across services
  - TODO: Send traces to Datadog or Jaeger

---

## Documentation TODOs

- [ ] 🔴 **Complete OpenAPI specification**
  - Already created: openapi-spec.yaml
  - TODO: Review and validate against new requirements
  - TODO: Add examples for all request/response bodies
  - TODO: Document all error codes

- [ ] 🔴 **Write API documentation**
  - Generate from OpenAPI spec
  - TODO: Publish to developer portal
  - TODO: Include authentication guide
  - TODO: Include rate limiting info
  - TODO: Include examples for each endpoint

- [ ] 🟡 **Write runbook**
  - Operational guide for on-call engineers
  - TODO: Common issues and resolutions
  - TODO: Monitoring dashboards and alerts
  - TODO: Deployment procedures
  - TODO: Rollback procedures
  - TODO: Database migration procedures

- [ ] 🟡 **Write migration guide**
  - Guide for transitioning from legacy to new system
  - TODO: Data migration steps
  - TODO: API changes and compatibility
  - TODO: Timeline and rollout plan
  - TODO: Rollback plan

---

## Security & Compliance TODOs

- [ ] 🔴 **Implement authentication**
  - JWT token validation via Member API
  - TODO: Verify token on all protected endpoints
  - TODO: Extract and validate member ID
  - TODO: Handle token expiration
  - TODO: Support refresh tokens

- [ ] 🔴 **Implement authorization**
  - Owner, authorized user, dealer, admin roles
  - TODO: Check ownership on update/delete operations
  - TODO: Check dealer permissions for dealer features
  - TODO: Check admin permissions for admin endpoints

- [ ] 🔴 **Validate input**
  - Prevent injection attacks
  - TODO: Validate all request bodies against schema
  - TODO: Sanitize user input (titles, descriptions)
  - TODO: Validate file uploads (size, type)
  - TODO: Rate limit endpoints

- [ ] 🔴 **Implement rate limiting**
  - Prevent abuse
  - TODO: 100 requests/minute per user (as documented)
  - TODO: Higher limits for dealer accounts
  - TODO: Use Redis for rate limit tracking
  - TODO: Return 429 Too Many Requests

- [ ] 🟡 **Audit logging**
  - Track sensitive operations
  - TODO: Log all create/update/delete operations
  - TODO: Log admin actions
  - TODO: Include member ID, IP, timestamp
  - TODO: Store in separate audit log

- [ ] 🟡 **Data privacy**
  - Comply with privacy regulations
  - TODO: Implement PII handling (email, phone)
  - TODO: Support data deletion requests
  - TODO: Support data export requests
  - TODO: Anonymize deleted user data

---

## Additional Research Needed

- [ ] 📋 **Research virus scanning for Quick Apply**
  - Reference: TODO in Services.md and Features.md
  - Currently under development
  - TODO: @Chris - Add technical notes on virus scanning infrastructure
  - TODO: Integrate with virus scanning service
  - TODO: Quarantine suspicious uploads
  - TODO: Notify users of scan results

- [ ] 📋 **Research Spincar/Tours integration**
  - Reference: ToursController in legacy system
  - 360° vehicle tours for Cars vertical
  - TODO: Determine if still in use (Utah.com)
  - TODO: If needed, integrate with Spincar API
  - TODO: Store tour URLs in carDetails

- [ ] 📋 **Research survey system**
  - Reference: SurveysController in legacy system
  - TODO: Determine if surveys are still active
  - TODO: If needed, design survey endpoints
  - TODO: Store in separate surveys collection

- [ ] 📋 **Research CSL config**
  - Reference: DealerController CSL config methods
  - TODO: What is CSL?
  - TODO: Is it still needed?
  - TODO: Design data model if needed

- [ ] 📋 **Research member verification**
  - Reference: ListingController member verification methods
  - TODO: What verification is needed?
  - TODO: Who can verify?
  - TODO: Impact on listing visibility?

---

## Phase 3+ Future Features (Not in Current Scope)

- [ ] 🟢 **Advanced analytics dashboard** - Listing performance metrics, trends
- [ ] 🟢 **A/B testing framework** - Test pricing, features, UI
- [ ] 🟢 **Recommendation engine** - Suggest similar listings
- [ ] 🟢 **Social sharing** - Share listings on social media
- [ ] 🟢 **Bulk import/export** - CSV import for dealers
- [ ] 🟢 **Advanced fraud detection** - Integrate with Sift or similar
- [ ] 🟢 **Multi-language support** - I18n for listings
- [ ] 🟢 **Mobile app APIs** - Optimized for mobile apps
- [ ] 🟢 **GraphQL subscriptions** - Real-time updates via WebSocket
- [ ] 🟢 **Listing templates** - Pre-filled templates for common types

---

## Summary

**Phase 1 (MVP) TODOs**: ~50 critical items
**Phase 2 TODOs**: ~30 important items
**Research Items**: ~6 items needing investigation
**Cron/Workers**: ~6 scheduled tasks
**Infrastructure**: ~15 deployment/monitoring items
**Testing**: ~10 test suites needed

**Total**: ~117 actionable TODO items

**Next Steps**:
1. Begin Phase 1 core endpoints (listings CRUD, search, photos)
2. Set up infrastructure (MongoDB, Elasticsearch, Redis, Kubernetes)
3. Implement authentication and authorization
4. Create test suite
5. Research outstanding questions (virus scanning, CSL config, etc.)
