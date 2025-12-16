# Listing Service - Golang Implementation Outline

## Overview

This document outlines the new **Listing Service** written in Golang, which will replace the existing legacy classifieds API (`m-ksl-classifieds-api`). This service is part of the **Jobs to Classifieds** migration project.

### Legacy System Reference

**Legacy Repository**: `/Users/cpies/code/AI-Agents/Research Repos/Legacy/m-ksl-classifieds-api`

The legacy system is a Symfony PHP application that provides a comprehensive REST API for KSL Classifieds. It includes:
- **Language**: PHP (Symfony Framework)
- **Database**: MongoDB (primary), MySQL (secondary)
- **Search**: Elasticsearch
- **Cache**: Memcached
- **Routes**: Defined in [`config/routes.yaml`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml)
- **Controllers**: Located in [`src/Controller/`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller)

---

## API Endpoints to Migrate

The following sections document all endpoints from the legacy system, organized by functional domain.

### 1. Authentication Endpoints (No need to migrate)

**Controller**: [`AuthController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/AuthController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| POST | `/auth` | `authAcquire` | `getAuthToken` | Acquire authentication token |
| POST | `/auth/` | `authAcquire2` | `getAuthToken` | Acquire authentication token (alt) |
| POST | `/auth/refresh` | `authRefresh` | `refreshAuthToken` | Refresh authentication token |
| POST | `/auth/expire` | `authExpire` | `expireAuthToken` | Expire authentication token |
| POST | `/auth/anonymous` | `authAnonymous` | `getAnonymousAuthToken` | Get anonymous auth token |

**Legacy Reference**: [routes.yaml:3-26](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L3-L26)

---

### 2. Listing Endpoints (Migration Required)

**Controller**: [`ListingController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ListingController.php)

#### Core Listing Operations (Migration Required)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/listings/{id}` | `listingsGet` | `getListing` | Get listing by ID |
| GET | `/listings/{id}/thanks-page` | `listingsGetThanksPage` | `getListingThanksPage` | Get listing data for thanks page |
| GET | `/listings` | `listingsSearch` | `getListings` | Search listings |
| POST | `/listings/create-stub` | `listingsCreateStub` | `createStub` | Create new listing stub |
| PUT | `/listings/{id}` | `listingsUpdate` | `updateListing` | Update listing |
| DELETE | `/listings/{listingId}` | `listingsDelete` | `deleteListing` | Delete listing |
| PUT | `/listings/{id}/renew` | `listingsRenew` | `renewListing` | Renew listing |

**Legacy Reference**: [routes.yaml:31-83](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L31-L83)

#### Listing Photos (Migration Required)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| POST | `/listings/{id}/photos` | `listingsUploadListingPhoto` | `uploadListingPhoto` | Upload listing photo |
| POST | `/listings/{id}/photos/{photoId}` | `listingsEditListingPhoto` | `editListingPhoto` | Edit listing photo |
| DELETE | `/listings/{id}/photos/{photoId}` | `listingsDeleteListingPhoto` | `deleteListingPhoto` | Delete listing photo |

**Legacy Reference**: [routes.yaml:156-177](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L156-L177)

#### Member-Specific Listing Operations (TODO: Determine if migration is required)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| PUT | `/listings/member/{memberId}/toggle-hidden/{setHidden}` | `listingsMemberToggleHidden` | `toggleMemberListingsHidden` | Toggle hidden status for member listings |
| GET | `/listings/member/{memberId}/listings-status` | `listingsMemberGetListingsStatus` | `getMemberListingsStatus` | Get member listings status |
| PUT | `/listings/member/{memberId}/verification-status` | `listingsMemberUpdateVerificationStatus` | `updateMemberVerificationStatus` | Update verification status for member listings |

**Legacy Reference**: [routes.yaml:86-109](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L86-L109)

#### Listing Metadata & Support (Migration Required)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| POST | `/listings/paid-info` | `listingGetListingsPaidInfo` | `getListingsPaidInfo` | Get paid info for listings |
| POST | `/listings/create-payment-intent` | `listingsСreatePaymentIntent` | `createPaymentIntent` | Create payment intent |
| GET | `/listings/meta` | `getListingsMeta` | `getListingMeta` | Get listing metadata |
| GET | `/listings/renew-data` | `getListingsRenewData` | `getRenewListingSupportData` | Get renew listing support data |
| GET | `/listings/predefined-rental-rules` | `getPredefinedRentalRules` | `getPredefinedRentalRules` | Get predefined rental rules |
| GET | `/listings/contact-info` | `getListingsContactInfo` | `getListingContactInfo` | Get listing contact info |

**Legacy Reference**: [routes.yaml:111-242](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L111-L242)

---

### 3. Category Endpoints (Future Migration Required)

**Controller**: [`CategoryController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/CategoryController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/category-seo` | `getCategorySeo` | `getCategorySeo` | Get category SEO data |
| GET | `/category-filters` | `getCategoryFilters` | `getCategoryFilters` | Get category filters |
| GET | `/category-tree` | `getCategoryTree` | `getCategoryTree` | Get category tree |
| GET | `/categories` | `getCategoriesTree` | `getCategoriesTree` | Get categories tree |
| GET | `/sub-categories/specifications` | `getSpecification` | `getSubCategorySpecifications` | Get subcategory specifications |
| POST | `/sub-categories/specifications` | `createSpecification` | `createSubCategorySpecification` | Create subcategory specification |
| PUT | `/sub-categories/specifications` | `updateSpecification` | `updateSubCategorySpecification` | Update subcategory specification |
| PUT | `/sub-categories/specifications/weights` | `updateSpecificationWeights` | `updateSpecificationWeights` | Update specification weights |

**Legacy Reference**: [routes.yaml:179-217](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L179-L217)

---

### 4. Dealer Endpoints (Future Migration Required)

**Controller**: [`DealerController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/DealerController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/dealer/{dealerId}` | `getDealer` | `getDealer` | Get dealer information |
| POST | `/dealer/{dealerId}/logo` | `dealerAddLogo` | `addLogo` | Add dealer logo |
| DELETE | `/dealer/{dealerId}/logo` | `dealerDeleteLogo` | `deleteLogo` | Delete dealer logo |
| POST | `/dealer/{dealerId}/csl-config` | `addDealerCslConfigItem` | `addCslConfigItem` | Add CSL config item |
| GET | `/dealer/{dealerId}/csl-config` | `getDealerCslConfig` | `getCslConfig` | Get CSL config |
| DELETE | `/dealer/{dealerId}/csl-config` | `removeDealerCslConfigItem` | `removeCslConfigItem` | Remove CSL config item |
| PATCH | `/dealer/{dealerId}/bypass-listing-fee` | `updateDealerBypassListingFee` | `updateDealerBypassListingFee` | Update bypass listing fee |
| PATCH | `/dealer/{dealerId}/integration` | `updateDealerIntegration` | `updateDealerIntegration` | Update dealer integration |
| DELETE | `/dealer/{dealerId}/integration` | `removeDealerIntegration` | `removeDealerIntegration` | Remove dealer integration |

**Legacy Reference**: [routes.yaml:254-317](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L254-L317)

---

### 5. Spotlight Endpoints (TODO: Determine if migration is required)

**Controller**: [`SpotlightController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/SpotlightController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/spotlights` | `getSpotlights` | `getSpotlights` | Get spotlights |
| POST | `/spotlights` | `addSpotlights` | `addSpotlight` | Add spotlight |
| PUT | `/spotlights` | `updateSpotlights` | `addSpotlight` | Update spotlight |
| DELETE | `/spotlights` | `removeSpotlights` | `removeSpotlight` | Remove spotlight |

**Legacy Reference**: [routes.yaml:320-340](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L320-L340)

---

### 6. Saved Search Endpoints (Future Migration Required)

**Controller**: [`SavedSearchController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/SavedSearchController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| POST | `/saved-searches/` | `savedSearchesCreate` | `createSavedSearch` | Create saved search |
| PUT | `/saved-searches/{id}` | `savedSearchesUpdate` | `updateSavedSearch` | Update saved search |

**Legacy Reference**: [routes.yaml:342-352](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L342-L352)

---

### 7. Listing Favorites Endpoints (Future Migration Required)

**Controller**: [`ListingFavoriteController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ListingFavoriteController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| POST | `/listings/{listingId}/favorites` | `listingsFavoritesCreate` | `createListingFavorite` | Create listing favorite |
| PUT | `/listings/{listingId}/favorites` | `listingsFavoritesUpdate` | `updateListingFavorite` | Update listing favorite |
| PUT | `/listings/{listingId}/favorites/{memberId}` | `listingsFavoritesUpdateWithMember` | `updateListingFavoriteWithMember` | Update listing favorite (deprecated) |
| DELETE | `/listings/{listingId}/favorites` | `listingsFavoritesDelete` | `deleteListingFavorite` | Delete listing favorite |

**Legacy Reference**: [routes.yaml:393-421](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L393-L421)

---

### 8. Survey Endpoints (TODO: Research these endpoints)

**Controller**: [`SurveysController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/SurveysController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/surveys` | `surveyGetAll` | `getSurveys` | Get all surveys |
| POST | `/surveys` | `surveyCreate` | `updateSurvey` | Create survey |
| GET | `/surveys/stats` | `surveyGetStats` | `getSurveyStats` | Get survey stats |
| GET | `/surveys/types` | `surveyType` | `getSurveyTypes` | Get survey types |
| GET | `/surveys/{surveyId}` | `surveyGet` | `getSurvey` | Get survey by ID |
| PUT | `/surveys/{surveyId}` | `surveyUpdate` | `updateSurvey` | Update survey |
| POST | `/surveys/{surveyId}/results` | `surveyAddResults` | `addSurveyResults` | Add survey results |
| DELETE | `/surveys/{surveyId}` | `surveyRemove` | `removeSurvey` | Remove survey |

**Legacy Reference**: [routes.yaml:116-154](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L116-L154)

---

### 9. Suggester Endpoints (TODO: Determine if related to listing service)

**Controller**: [`SuggesterController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/SuggesterController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/suggester/keyword-search-suggestions` | `getKeywordSearchSuggestions` | `getKeywordSearchSuggestions` | Get keyword search suggestions |
| GET | `/suggester/suggested-categories` | `getSuggestedCategories` | `getSuggestedCategories` | Get suggested categories |

**Legacy Reference**: [routes.yaml:244-252](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L244-L252)

---

### 10. Cities Endpoints (TODO: Determine if related to listing service)

**Controller**: [`CitiesController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/CitiesController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/cities` | `getCities` | `getCities` | Get cities |

**Legacy Reference**: [routes.yaml:354-357](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L354-L357)

---

### 11. Statistics Endpoints (Migration not required)

**Controller**: [`StatController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/StatController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/stats` | `getStats` | `getStats` | Get statistics |

**Legacy Reference**: [routes.yaml:359-362](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L359-L362)

---

### 12. Management Endpoints (Migration required)

**Controller**: [`ManagementController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ManagementController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| PUT | `/management/dealer-monthly-email/{memberId}` | `managementDealerMonthlyEmail` | `sendDealerMonthlyEmail` | Send dealer monthly email |
| PUT | `/management/update-batch-listings/` | `managementUpdateBatchListings` | `updateBatchListings` | Update batch listings |
| PUT | `/management/update-member-listings-dealer-data/{memberId}` | `managementUpdateMemberListingsDealerData` | `updateMemberListingsDealerData` | Update member listings dealer data |

**Legacy Reference**: [routes.yaml:364-381](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L364-L381)

---

### 13. Archive Listing Endpoints (Migration required)

**Controller**: [`ArchiveListingController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ArchiveListingController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/archive-listings` | `getArchivedListings` | `getListings` | Get archived listings |
| PUT | `/archive-listings` | `restoreArchivedListing` | `restoreListings` | Restore archived listings |

**Legacy Reference**: [routes.yaml:383-391](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L383-L391)

---

### 14. Price Drop Endpoints (Future Migration required)

**Controller**: [`PriceDropController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/PriceDropController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| POST | `/price-drop/notifications` | `priceDropNotify` | `handlePriceDropNotification` | Handle price drop notification |

**Legacy Reference**: [routes.yaml:423-426](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L423-L426)

---

### 15. Expiration Endpoints (Future Migration required)

**Controller**: [`ExpirationController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ExpirationController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| POST | `/expiration/notify-seller` | `expirationNotifySeller` | `handleSellerExpirationNotification` | Notify seller of expiration |
| POST | `/expiration/notify-buyers` | `expirationNotifyBuyers` | `handleBuyersExpirationNotification` | Notify buyers of expiration |
| GET | `/expiration/listings` | `expirationListings` | `getListings` | Get expiring listings |

**Legacy Reference**: [routes.yaml:428-441](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L428-L441)

---

### 16. Tours (Spincar) Endpoints (TODO: Research, Utah.com No migration needed)

**Controller**: [`ToursController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ToursController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| PUT | `/listings/{listingId}/spincar` | `updateListingSpins` | `loadSpincarTourOnListing` | Load Spincar tour on listing |
| DELETE | `/listings/{listingId}/spincar` | `deleteListingSpins` | `removeTourFromListing` | Remove tour from listing |
| PUT | `/tours/{memberId}` | `updateMemberSpins` | `manageToursOnMembersListings` | Manage tours on member listings |
| DELETE | `/tours/{memberId}` | `deleteMemberSpins` | `manageToursOnMembersListings` | Remove tours from member listings |

**Legacy Reference**: [routes.yaml:443-473](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L443-L473)

---

### 17. Abuse Endpoints (Future Migration required)

**Controller**: [`AbuseController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/AbuseController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/abuse/{listingId}` | `abuseGetListingAbuseRecord` | `getListingAbuseRecord` | Get listing abuse record |
| GET | `/abuse` | `abuseGetListingsAbuseRecords` | `getListingsAbuseRecords` | Get listings abuse records |
| PUT | `/abuse/{listingId}/review` | `abuseReviewListingAbuseRecord` | `reviewListingAbuseRecord` | Review listing abuse record |
| GET | `/abuse/{listingId}/reports` | `abuseGetListingUserReports` | `getListingUserReports` | Get listing user reports |
| POST | `/abuse/{listingId}/reports` | `abuseCreateUserReport` | `createUserReport` | Create user report |
| GET | `/abuse/stats` | `abuseGetStats` | `getStats` | Get abuse stats |
| POST | `/abuse/stats/timeRange` | `abuseGetStatsTimeRange` | `getStatsTimeRange` | Get abuse stats for time range |

**Legacy Reference**: [routes.yaml:475-516](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L475-L516)

---

### 18. Members Endpoints (Future Migration required)

**Controller**: [`MembersController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/MembersController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/members/{memberId}` | `membersGetMember` | `getMemberInfo` | Get member information |
| GET | `/members` | `membersGetMembers` | `getMembersInfo` | Get members information |
| GET | `/members/{memberId}/notes` | `membersGetMemberNotes` | `getMemberNotes` | Get member notes |
| POST | `/members/{memberId}/notes` | `membersCreateMemberNote` | `createMemberNote` | Create member note |
| PUT | `/members/{memberId}/status` | `membersUpdateMemberStatus` | `updateMemberStatus` | Update member status |
| GET | `/listings/{id}/member` | `listingsGetMemberInfoByListingId` | `getInfoByMemberIdOrListingId` | Get member info by listing ID |
| GET | `/members/{id}/lookup` | `listingsGetMemberInfoByMemberId` | `getInfoByMemberIdOrListingId` | Get member info by member ID |

**Legacy Reference**: [routes.yaml:518-568](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L518-L568)

---

### 19. Homepage Endpoints (Future Migration required)

**Controller**: [`HomepageController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/HomepageController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/homepage/get-meta-data` | `homepageGetMetaData` | `getMetaData` | Get homepage metadata |
| POST | `/homepage/save-user-preferences` | `homepageSaveUserPreferences` | `saveUserPreferences` | Save user preferences |
| GET | `/homepage/my-listings` | `homepageGetMyListings` | `getMyListings` | Get user's listings |
| GET | `/homepage/my-favorites` | `homepageGetMyFavorites` | `getMyFavorites` | Get user's favorites |
| GET | `/homepage/saved-search/{savedSearchId}/listings` | `homepageGetSavedSearchListings` | `getSavedSearchListings` | Get saved search listings |
| GET | `/homepage/top-listings` | `homepageGetFeaturedListings` | `getTopListings` | Get top/featured listings |
| GET | `/homepage/rental-listings` | `homepageGetRentalListings` | `getRentalListings` | Get rental listings |

**Legacy Reference**: [routes.yaml:570-605](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L570-L605)

---

### 20. Payment Endpoints (Future Migration required)

**Controller**: [`PaymentController.php`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/PaymentController.php)

| Method | Path | Legacy Route Name | Controller Method | Description |
|--------|------|-------------------|-------------------|-------------|
| GET | `/payments/stripe-key` | `paymentsGetStripeKey` | `getStripeKey` | Get Stripe key |
| GET | `/payments/payment-methods` | `paymentsGetPaymentMethods` | `getPaymentMethods` | Get payment methods |
| PUT | `/payments/subscription-event` | `paymentsHandleSubscriptionEvent` | `handleSubscriptionEvent` | Handle subscription event |

**Legacy Reference**: [routes.yaml:607-620](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml#L607-L620)

---

## Technical Architecture Considerations

### Data Storage

The legacy system uses:
- **MongoDB**: Primary data store for listings, categories, dealers, etc.
- **MySQL**: Secondary database for certain operations
- **Elasticsearch**: Search functionality
- **Memcached**: Caching layer

### External Dependencies

Based on the legacy controller imports, the system integrates with:
- **Member API**: User authentication and member management
- **MyAccount API**: User account operations
- **KSL API**: General KSL services
- **Spincar**: 360° vehicle tours
- **Stripe**: Payment processing
- **S3**: Image storage
- **Mandrill**: Email delivery
- **Sift**: Fraud detection
- **PubSub**: Event messaging

### Key Data Models

The legacy system works with these primary entities (found in `src/Db/Mongo/`):
- Listings (General)
- Categories
- Dealers
- Favorites
- Matched Alerts
- Surveys
- Members
- Abuse Reports

---

## Migration Strategy

### Phase 1: Core Listing Operations
Focus on migrating the most critical endpoints first:
1. Authentication endpoints
2. Core listing CRUD operations
3. Listing search functionality
4. Photo upload/management

### Phase 2: Supporting Features
5. Categories and filters
6. Favorites and saved searches
7. Member-specific operations
8. Dealer management

### Phase 3: Advanced Features
9. Surveys and statistics
10. Abuse reporting
11. Tours/Spincar integration
12. Payment processing
13. Notifications (price drops, expirations)

### Phase 4: Administrative & Edge Cases
14. Management endpoints
15. Archive operations
16. Homepage aggregation endpoints

---

## Next Steps

1. **Define Golang Service Structure**: Determine package organization, routing framework (e.g., Gin, Echo, Chi), and middleware
2. **Data Layer Design**: Design data access patterns for MongoDB, MySQL, and Elasticsearch in Go
3. **API Contract Specification**: Create OpenAPI/Swagger specifications for each endpoint
4. **Authentication Strategy**: Implement JWT or similar token-based auth in Go
5. **Testing Strategy**: Plan unit, integration, and E2E tests
6. **Deployment Plan**: Containerization, CI/CD, and infrastructure as code

---

## References

- **Legacy API Repository**: [`m-ksl-classifieds-api`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api)
- **Routes Configuration**: [`config/routes.yaml`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/config/routes.yaml)
- **Controllers Directory**: [`src/Controller/`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller)
- **README**: [`README.md`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api/README.md)
