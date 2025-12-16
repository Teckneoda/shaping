# Services - Architecture & Implementation

This document defines the service architecture for the unified listing system, covering both the REST API service in `marketplace-backend` and the GraphQL layer in `marketplace-graphql`.

---

## 1. Overview

### Architecture Pattern

The unified listing system follows a **thin GraphQL gateway** pattern per ADR 013:

```
Frontend (Next.js)
    ↓ GraphQL queries/mutations
marketplace-graphql (GraphQL Gateway)
    ↓ REST API calls
marketplace-backend/apps/listing/services/listing-http-rest (Go REST API)
    ↓ Data operations
MongoDB + Elasticsearch + Redis
```

**Key Principles**:
- GraphQL layer has **NO business logic**
- GraphQL layer has **NO direct data store access**
- All business logic resides in Go REST APIs
- GraphQL simply coordinates and aggregates REST API calls

---

## 2. marketplace-backend/apps/listing/services/listing-http-rest

### 2.1 Service Overview

**Location**: `marketplace-backend/apps/listing/services/listing-http-rest`

**Purpose**: Core REST API service for all listing operations across Jobs, Classifieds, Cars, and Homes verticals.

**Technology Stack**:
- **Language**: Go 1.21+
- **Web Framework**: TBD (Gin, Echo, or Chi)
- **Database**: MongoDB (primary), MySQL (secondary)
- **Search**: Elasticsearch
- **Cache**: Redis
- **Observability**: `golang-o11y` (Datadog tracing, structured logging)
- **API Documentation**: OpenAPI 3.0

---

### 2.2 Package Structure

```
listing-http-rest/
├── main.go                    # Application entry point
├── app.go                     # Application setup and configuration
├── routes.go                  # HTTP route definitions
├── go.mod                     # Go module definition
├── go.sum                     # Go module checksums
├── Dockerfile                 # Container image definition
├── README.md                  # Service documentation
│
├── handler/                   # HTTP request handlers
│   ├── listing.go            # Core listing CRUD handlers
│   ├── search.go             # Search and filter handlers
│   ├── photo.go              # Photo management handlers
│   ├── favorite.go           # Favorite handlers
│   ├── saved_search.go       # Saved search handlers
│   ├── category.go           # Category handlers
│   ├── dealer.go             # Dealer management handlers
│   ├── spotlight.go          # Spotlight/featured handlers
│   ├── boost.go              # Boost handlers (Jobs)
│   ├── archive.go            # Archive handlers
│   ├── abuse.go              # Abuse reporting handlers
│   ├── member.go             # Member operations handlers
│   ├── homepage.go           # Homepage aggregation handlers
│   ├── payment.go            # Payment/pricing handlers
│   ├── management.go         # Admin/batch operation handlers
│   └── health.go             # Health check handlers
│
├── domain/                    # Business logic layer
│   ├── listing/              # Listing domain
│   │   ├── service.go        # Listing service interface and implementation
│   │   ├── model.go          # Listing entity and related types
│   │   ├── validator.go      # Listing validation logic
│   │   ├── lifecycle.go      # Status transitions, renewals
│   │   └── pricing.go        # Pricing calculations
│   │
│   ├── search/               # Search domain
│   │   ├── service.go        # Search service
│   │   ├── query_builder.go  # Elasticsearch query construction
│   │   ├── facets.go         # Facet aggregation logic
│   │   └── suggester.go      # Search suggestions
│   │
│   ├── category/             # Category domain
│   │   ├── service.go        # Category service
│   │   ├── model.go          # Category entity
│   │   ├── specifications.go # Subcategory specifications
│   │   └── tree.go           # Category tree operations
│   │
│   ├── favorite/             # Favorite domain
│   │   ├── service.go        # Favorite service
│   │   └── model.go          # Favorite entity
│   │
│   ├── saved_search/         # Saved search domain
│   │   ├── service.go        # Saved search service
│   │   └── model.go          # Saved search entity
│   │
│   ├── dealer/               # Dealer domain
│   │   ├── service.go        # Dealer service
│   │   ├── model.go          # Dealer entity
│   │   └── csl.go            # CSL configuration logic
│   │
│   ├── spotlight/            # Spotlight domain
│   │   ├── service.go        # Spotlight service
│   │   └── model.go          # Spotlight entity
│   │
│   ├── boost/                # Boost domain (Jobs)
│   │   ├── service.go        # Boost service
│   │   ├── model.go          # Boost configuration
│   │   └── scheduler.go      # Auto-boost scheduling
│   │
│   ├── abuse/                # Abuse reporting domain
│   │   ├── service.go        # Abuse service
│   │   └── model.go          # Abuse report entity
│   │
│   ├── member/               # Member domain
│   │   ├── service.go        # Member service
│   │   └── model.go          # Member entity
│   │
│   └── payment/              # Payment domain
│       ├── service.go        # Payment service
│       ├── stripe.go         # Stripe integration
│       └── pricing.go        # Pricing calculations
│
├── repository/                # Data access layer
│   ├── mongo/                # MongoDB repositories
│   │   ├── listing.go        # Listing repository
│   │   ├── category.go       # Category repository
│   │   ├── dealer.go         # Dealer repository
│   │   ├── favorite.go       # Favorite repository
│   │   ├── saved_search.go   # Saved search repository
│   │   ├── spotlight.go      # Spotlight repository
│   │   ├── abuse.go          # Abuse repository
│   │   └── member.go         # Member repository
│   │
│   ├── elasticsearch/        # Elasticsearch repositories
│   │   ├── listing.go        # Listing search repository
│   │   └── suggester.go      # Search suggestion repository
│   │
│   └── redis/                # Redis caching
│       └── cache.go          # Cache operations
│
├── infrastructure/            # External service integrations
│   ├── mongodb/              # MongoDB client and connection
│   │   └── client.go
│   │
│   ├── elasticsearch/        # Elasticsearch client
│   │   └── client.go
│   │
│   ├── redis/                # Redis client
│   │   └── client.go
│   │
│   ├── s3/                   # S3 integration (via image service)
│   │   └── client.go
│   │
│   ├── stripe/               # Stripe integration
│   │   └── client.go
│   │
│   ├── memberapi/            # Member API integration
│   │   └── client.go
│   │
│   ├── imageservice/         # Image upload/download service
│   │   └── client.go
│   │
│   ├── reportsservice/       # Reports service integration
│   │   └── client.go
│   │
│   └── pubsub/               # PubSub integration
│       └── client.go
│
├── middleware/                # HTTP middleware
│   ├── auth.go               # JWT authentication
│   ├── logging.go            # Request logging
│   ├── recovery.go           # Panic recovery
│   ├── cors.go               # CORS configuration
│   ├── ratelimit.go          # Rate limiting
│   └── tracing.go            # Datadog tracing
│
├── dto/                       # Data Transfer Objects
│   ├── request/              # Request DTOs
│   │   ├── listing.go
│   │   ├── search.go
│   │   ├── favorite.go
│   │   └── ...
│   │
│   └── response/             # Response DTOs
│       ├── listing.go
│       ├── search.go
│       ├── favorite.go
│       └── ...
│
├── util/                      # Utility functions
│   ├── validator.go          # Input validation
│   ├── error.go              # Error handling utilities
│   ├── pagination.go         # Pagination helpers
│   └── transform.go          # Data transformation utilities
│
└── test/                      # Test files
    ├── integration/          # Integration tests
    └── fixtures/             # Test fixtures and mocks
```

---

### 2.3 Service Responsibilities

#### Core Responsibilities

1. **Listing Lifecycle Management**
   - Create, read, update, delete listings
   - Status transitions (draft → active → expired/sold/deleted)
   - Renewal and expiration logic
   - History tracking

2. **Search & Discovery**
   - Elasticsearch query construction
   - Faceted search and filtering
   - Search suggestions and autocomplete
   - Archive search

3. **Media Management**
   - Photo upload coordination (via image service)
   - Photo metadata management
   - Photo ordering and deletion

4. **Favorites & Saved Searches**
   - Favorite CRUD operations
   - Saved search CRUD operations
   - Notification preference management

5. **Premium Features**
   - Featured listings (Classifieds, Cars, Homes)
   - Spotlight management (Classifieds)
   - Top Jobs (Jobs)
   - Boost system (Jobs)

6. **Category & Taxonomy**
   - Category tree retrieval
   - Subcategory specifications
   - Category filtering and SEO data

7. **Dealer & Employer Management**
   - Dealer information and logos
   - CSL configuration
   - Fee bypass settings
   - Employer groups and packages (Jobs)

8. **Abuse & Moderation**
   - Abuse report submission
   - Abuse report review
   - Abuse statistics

9. **Member Operations**
   - Member information retrieval
   - Member notes
   - Verification status
   - Listings visibility toggles

10. **Payment & Pricing**
    - Payment intent creation
    - Pricing calculations
    - Stripe integration

11. **Homepage Aggregation**
    - User listings summary
    - User favorites summary
    - Featured listings
    - Saved search results

12. **Batch Operations**
    - Dealer monthly emails
    - Batch listing updates
    - Member listings dealer data updates

#### External Service Coordination

**Image Service Integration**:
- Photo upload via `POST /images/upload`
- Photo download via `GET /images/{id}`
- Thumbnail generation

**Reports Service Integration**:
- Statistics retrieval (views, clicks, favorites)
- BigQuery data integration
- Analytics dashboards

**Member API Integration**:
- Authentication verification
- User profile data
- Authorization checks

**Stripe Integration**:
- Payment intent creation
- Payment method management
- Subscription handling

**PubSub Integration**:
- Event publishing (listing created, updated, deleted)
- Feed data consumption

---

### 2.4 Data Layer Design

#### MongoDB Collections

**Primary Collections**:
- `listings` - Unified listing collection (all verticals)
- `categories` - Category hierarchy and metadata
- `dealers` - Dealer information and configuration
- `favorites` - User-listing favorites
- `savedSearches` - User saved searches
- `spotlights` - Spotlight configurations
- `abuseReports` - Abuse reports and reviews
- `memberNotes` - Member moderation notes

**Indexes**:
```javascript
// listings collection
{
  "id": 1,                           // Unique
  "memberId": 1,
  "listingType": 1,
  "status": 1,
  "category": 1, "subCategory": 1,
  "displayTime": -1,
  "expireTime": 1,
  "city": 1, "state": 1,
  "topJobStart": -1                  // For Jobs sorting
}

// favorites collection
{
  "memberId": 1, "listingId": 1      // Compound unique
}

// savedSearches collection
{
  "memberId": 1
}
```

#### Elasticsearch Indices

**Index**: `listings`

**Mapping**:
```json
{
  "mappings": {
    "properties": {
      "id": {"type": "long"},
      "listingType": {"type": "keyword"},
      "status": {"type": "keyword"},
      "title": {"type": "text", "analyzer": "standard"},
      "description": {"type": "text", "analyzer": "standard"},
      "price": {"type": "long"},
      "category": {"type": "keyword"},
      "subCategory": {"type": "keyword"},
      "city": {"type": "keyword"},
      "state": {"type": "keyword"},
      "zip": {"type": "keyword"},
      "location": {"type": "geo_point"},
      "displayTime": {"type": "date"},
      "expireTime": {"type": "date"},
      "isFeatured": {"type": "boolean"},
      "isSpotlighted": {"type": "boolean"},
      "topJob": {"type": "boolean"},
      "topJobStart": {"type": "date"},
      
      // Vertical-specific fields
      "carDetails": {"type": "object", "enabled": false},
      "homeDetails": {"type": "object", "enabled": false},
      "jobDetails": {
        "properties": {
          "employmentType": {"type": "keyword"},
          "educationLevel": {"type": "keyword"},
          "yearsOfExperience": {"type": "keyword"},
          "payRangeType": {"type": "keyword"},
          "salaryFrom": {"type": "long"},
          "salaryTo": {"type": "long"}
        }
      },
      "classifiedDetails": {"type": "object", "enabled": false}
    }
  }
}
```

#### Redis Caching Strategy

**Cache Keys**:
- `listing:{id}` - Individual listing (TTL: 5 minutes)
- `category:tree` - Category tree (TTL: 1 hour)
- `category:{id}:specifications` - Subcategory specs (TTL: 1 hour)
- `dealer:{id}` - Dealer info (TTL: 15 minutes)
- `search:{hash}` - Search results (TTL: 2 minutes)

**Cache Invalidation**:
- Listing update/delete → invalidate `listing:{id}`
- Category update → invalidate `category:*`
- Dealer update → invalidate `dealer:{id}`

---

### 2.5 API Design Patterns

#### RESTful Conventions

- `GET` for read operations
- `POST` for create operations
- `PUT` for full updates
- `PATCH` for partial updates
- `DELETE` for delete operations

#### Response Format

**Success Response**:
```json
{
  "data": { ... },
  "meta": {
    "timestamp": "2025-12-15T10:30:00Z",
    "requestId": "abc123"
  }
}
```

**Error Response**:
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid listing data",
    "details": [
      {"field": "title", "message": "Title is required"}
    ]
  },
  "meta": {
    "timestamp": "2025-12-15T10:30:00Z",
    "requestId": "abc123"
  }
}
```

#### Pagination

```json
{
  "data": [...],
  "pagination": {
    "page": 1,
    "perPage": 20,
    "total": 150,
    "totalPages": 8,
    "hasNext": true,
    "hasPrev": false
  }
}
```

---

### 2.6 Authentication & Authorization

**Authentication**: JWT tokens from Member API

**Middleware Flow**:
```
Request → Auth Middleware → Verify JWT → Extract memberId → Handler
```

**Authorization Levels**:
- **Anonymous**: Limited read-only access (search, view listings)
- **Authenticated**: Full read/write for own listings, favorites, saved searches
- **Dealer**: Additional dealer management endpoints
- **Moderator**: Abuse review, member management
- **Admin**: All operations including batch updates

---

### 2.7 Error Handling

**Error Codes**:
- `VALIDATION_ERROR` - Input validation failed
- `NOT_FOUND` - Resource not found
- `UNAUTHORIZED` - Authentication required
- `FORBIDDEN` - Insufficient permissions
- `CONFLICT` - Resource conflict (duplicate, concurrent update)
- `INTERNAL_ERROR` - Server error
- `SERVICE_UNAVAILABLE` - Downstream service error

**Error Logging**:
- All errors logged with structured logging (o11y)
- Error stack traces for internal errors
- Request context included (requestId, memberId, etc.)

---

### 2.8 Testing Strategy

**Unit Tests**:
- Domain logic (validation, pricing, lifecycle)
- Repository layer (mocked database)
- Handler layer (mocked services)
- Coverage target: >80%

**Integration Tests**:
- Full request/response cycles
- Real MongoDB/Elasticsearch (test containers)
- External service mocking (Member API, Stripe, etc.)

**End-to-End Tests**:
- Critical user flows (create listing, search, favorite)
- Cross-vertical scenarios
- Performance benchmarks

---

### 2.9 Deployment

**Container Image**:
- Multi-stage Docker build
- Alpine Linux base image
- Health check endpoint (`/health`)

**Environment Variables**:
- `MONGODB_URI` - MongoDB connection string
- `ELASTICSEARCH_URL` - Elasticsearch endpoint
- `REDIS_URL` - Redis connection string
- `MEMBER_API_URL` - Member API endpoint
- `STRIPE_SECRET_KEY` - Stripe API key
- `IMAGE_SERVICE_URL` - Image service endpoint
- `REPORTS_SERVICE_URL` - Reports service endpoint
- `LOG_LEVEL` - Logging level (debug, info, warn, error)

**Scaling**:
- Horizontal scaling (stateless)
- Load balancer with health checks
- Auto-scaling based on CPU/memory

---

## 3. Additional Microservices

### 3.1 listing-applications (Job Applications)

**Location**: `marketplace-backend/apps/listing/services/listing-applications`

**Purpose**: Handle job application submissions with file uploads and virus scanning.

**Responsibilities**:
- Accept job applications with resume/cover letter
- Virus scan uploaded files (ClamAV integration)
- Store files in S3
- Send emails to employer and applicant
- Manage Quick Apply profiles
- Track application counts

**Technology**:
- Go 1.21+
- ClamAV integration
- S3 storage
- Email service integration

**Endpoints**:
- `POST /applications` - Submit application
- `GET /applications/quick-apply` - Get Quick Apply profile
- `POST /applications/quick-apply` - Save Quick Apply profile
- `GET /applications/{id}/download` - Download application file

**TODO**: @Chris - Add technical notes on virus scanning infrastructure

---

### 3.2 listing-feed-parser (Feed Processing)

**Location**: `marketplace-backend/apps/listing/services/listing-feed-parser`

**Purpose**: Parse XML/CSV feeds and publish to PubSub.

**Responsibilities**:
- Download feeds from configured URLs
- Parse XML (Jobs) and CSV (Classifieds/Cars)
- Transform to unified listing format
- Publish to PubSub topic
- Error handling and retry logic
- Notification on completion

**Technology**:
- Go 1.21+
- XML parser (encoding/xml)
- CSV parser (encoding/csv)
- PubSub publisher

**Data Flow**:
```
Cron/Scheduler → Parser Service → Download Feed → Parse → PubSub Topic
```

---

### 3.3 listing-feed-subscriber (Feed Consumer)

**Location**: `marketplace-backend/apps/listing/services/listing-feed-subscriber`

**Purpose**: Subscribe to PubSub feed messages and create/update listings via REST API.

**Responsibilities**:
- Subscribe to PubSub feed topic
- Validate listing data
- Call listing-http-rest API for CRUD
- Match on externalId for create vs. update
- Cleanup stale listings
- Error handling and dead letter queue

**Technology**:
- Go 1.21+
- PubSub subscriber
- HTTP client for REST API calls

**Data Flow**:
```
PubSub Topic → Subscriber Service → REST API (listing-http-rest)
```

---

### 3.4 Existing Services (No Migration)

**listing-cron-boosts**:
- Execute scheduled auto-boosts for Jobs
- Update `topJobStart` for re-boosting

**listing-cron-stats**:
- Aggregate statistics
- Sync with BigQuery

**listing-ps-classifieds-events-to-bq**:
- Stream listing events to BigQuery

**listing-ps-google-shopping**:
- Publish listings to Google Shopping feed

**listing-ps-profile-verification-status-updated**:
- Update listing verification status on member verification

**listing-ps-update-video-url**:
- Update video URLs on video processing completion

**listing-redirect-http**:
- Handle legacy URL redirects

---

## 4. marketplace-graphql

### 4.1 Service Overview

**Location**: `marketplace-graphql`

**Purpose**: Thin GraphQL gateway for frontend applications. Coordinates REST API calls from `marketplace-backend`.

**Architecture Philosophy** (per ADR 013):
- **NO business logic** - all logic in REST APIs
- **NO direct data access** - only REST API calls
- **Authentication only** - JWT validation
- **Query resolution only** - coordinate and aggregate REST responses

---

### 4.2 Package Structure

```
marketplace-graphql/
├── main.go                    # Application entry point
├── app.go                     # GraphQL server setup
├── gqlgen.yml                 # gqlgen configuration
├── go.mod
├── go.sum
│
├── graph/                     # GraphQL schema and resolvers
│   ├── schema.graphqls       # GraphQL schema definition
│   ├── generated/            # gqlgen generated code
│   │   └── generated.go
│   │
│   ├── model/                # GraphQL models (generated + custom)
│   │   └── models_gen.go
│   │
│   └── resolver/             # Resolver implementations
│       ├── resolver.go       # Root resolver
│       ├── listing.go        # Listing resolvers
│       ├── search.go         # Search resolvers
│       ├── favorite.go       # Favorite resolvers
│       ├── saved_search.go   # Saved search resolvers
│       ├── category.go       # Category resolvers
│       ├── dealer.go         # Dealer resolvers
│       ├── job.go            # Jobs-specific resolvers
│       └── homepage.go       # Homepage resolvers
│
├── services/                  # REST API client services
│   ├── listing/              # Listing service client
│   │   └── client.go
│   │
│   ├── search/               # Search service client
│   │   └── client.go
│   │
│   ├── category/             # Category service client
│   │   └── client.go
│   │
│   ├── dealer/               # Dealer service client
│   │   └── client.go
│   │
│   └── reports/              # Reports service client (existing)
│       └── client.go
│
├── middleware/                # GraphQL middleware
│   ├── auth.go               # JWT authentication
│   ├── logging.go            # Request logging
│   └── tracing.go            # Datadog tracing
│
└── directives.go              # Custom GraphQL directives (@auth, etc.)
```

---

### 4.3 GraphQL Schema Design

#### Core Types

```graphql
# Unified listing type with discriminator pattern
interface Listing {
  id: ID!
  listingType: ListingType!
  status: ListingStatus!
  title: String!
  description: String!
  price: Int
  priceModifier: PriceModifier
  
  # Lifecycle
  createTime: DateTime!
  modifyTime: DateTime!
  displayTime: DateTime!
  expireTime: DateTime!
  
  # Ownership
  memberId: ID!
  
  # Location
  location: Location
  
  # Media
  primaryImage: Image
  photos: [Photo!]!
  
  # Contact
  contact: Contact!
  
  # Stats
  stats: ListingStats
  
  # Featured
  isFeatured: Boolean
  isSpotlighted: Boolean
  ribbons: [String!]!
}

# Concrete listing types
type JobListing implements Listing {
  # ... all Listing fields ...
  
  # Jobs-specific
  jobTitle: String!
  companyName: String!
  employmentType: EmploymentType
  educationLevel: EducationLevel
  yearsOfExperience: YearsOfExperience
  payRange: PayRange
  companyPerks: [String!]!
  applicationUrl: String
  topJob: Boolean
  topJobStart: DateTime
  autoBoost: AutoBoostConfig
}

type ClassifiedListing implements Listing {
  # ... all Listing fields ...
  
  # Classifieds-specific
  category: String!
  subCategory: String!
  marketType: MarketType
  newUsed: String
  dealerData: DealerData
  isRental: Boolean
  rentalPriceUnitRate: String
  rentalRules: [String!]!
}

type CarListing implements Listing {
  # ... all Listing fields ...
  
  # Cars-specific
  vin: String!
  make: String!
  model: String!
  makeYear: Int!
  mileage: Int!
  newUsed: String!
  transmission: String
  fuel: String
  dealerData: DealerData
}

type HomeListing implements Listing {
  # ... all Listing fields ...
  
  # Homes-specific
  bed: Int!
  bath: Float!
  squareFoot: Int!
  acre: Float
  buildYear: Int
  openHouseDates: [DateTime!]!
  agencyName: String
  mlsNumber: String
}

# Enums
enum ListingType {
  JOB
  CLASSIFIED
  CAR
  HOME_BUY
  HOME_RENT
}

enum ListingStatus {
  DRAFT
  ACTIVE
  EXPIRED
  SOLD
  DELETED
  PENDING
}

enum EmploymentType {
  FULL_TIME
  PART_TIME
  CONTRACT
  TEMPORARY
  INTERNSHIP
  SEASONAL
}

enum MarketType {
  SALE
  WANTED
  RENT
  SERVICE
  BUY
}

# Supporting types
type Location {
  street1: String
  street2: String
  city: String!
  state: String!
  zip: String!
  coordinates: Coordinates
}

type Coordinates {
  latitude: Float!
  longitude: Float!
}

type Contact {
  name: String!
  email: String!
  phone: String
  cellPhone: String
  homePhone: String
  displayPhone: Boolean
  displayEmail: Boolean
}

type Photo {
  id: ID!
  url: String!
  order: Int!
  caption: String
  sizes: PhotoSizes
}

type PayRange {
  type: PayRangeType!
  from: Int
  to: Int
}

enum PayRangeType {
  HOURLY
  SALARY
}

type AutoBoostConfig {
  enabled: Boolean!
  frequency: Int!
  lastBoostTime: DateTime
  nextBoostTime: DateTime
}

type ListingStats {
  pageViews: Int
  favoriteCount: Int
  viewCount: Int
  clickCount: Int
  emailCount: Int
  phoneCount: Int
  applicationCount: Int
}

# Search types
type SearchResults {
  listings: [Listing!]!
  facets: [Facet!]!
  pagination: Pagination!
}

type Facet {
  name: String!
  values: [FacetValue!]!
}

type FacetValue {
  value: String!
  count: Int!
}

type Pagination {
  page: Int!
  perPage: Int!
  total: Int!
  totalPages: Int!
  hasNext: Boolean!
  hasPrev: Boolean!
}

# Favorite types
type Favorite {
  id: ID!
  memberId: ID!
  listing: Listing!
  notifyOnPriceDrop: Boolean!
  notifyOnExpiration: Boolean!
  createTime: DateTime!
}

# Saved search types
type SavedSearch {
  id: ID!
  memberId: ID!
  name: String!
  filters: SearchFilters!
  notifyOnMatch: Boolean!
  createTime: DateTime!
}

type SearchFilters {
  listingType: ListingType
  category: String
  subCategory: String
  city: String
  state: String
  zip: String
  radius: Int
  priceMin: Int
  priceMax: Int
  keyword: String
  # ... additional filters
}
```

---

#### Queries

```graphql
type Query {
  # Listing queries
  listing(id: ID!): Listing
  listings(filters: SearchFilters!, page: Int, perPage: Int): SearchResults!
  
  # Job-specific
  job(id: ID!): JobListing
  jobs(filters: JobSearchFilters!, page: Int, perPage: Int): SearchResults!
  topJobs(city: String, state: String, category: String): [JobListing!]!
  
  # Favorites
  myFavorites(page: Int, perPage: Int): [Favorite!]!
  
  # Saved searches
  mySavedSearches: [SavedSearch!]!
  savedSearchListings(id: ID!, page: Int, perPage: Int): SearchResults!
  
  # Categories
  categories: [Category!]!
  categoryTree: CategoryTree!
  subCategorySpecifications(category: String!, subCategory: String!): [Specification!]!
  
  # Dealer
  dealer(id: ID!): Dealer
  
  # Homepage
  myListings(status: ListingStatus, page: Int, perPage: Int): [Listing!]!
  featuredListings(listingType: ListingType, limit: Int): [Listing!]!
  rentalListings(city: String, state: String, limit: Int): [Listing!]!
  
  # Metadata
  listingMeta: ListingMeta!
  contactInfo: Contact
  
  # Stats (via reports service)
  listingStats(listingId: ID!): ListingStats
}
```

---

#### Mutations

```graphql
type Mutation {
  # Listing mutations
  createListingDraft(input: CreateListingInput!): Listing!
  updateListing(id: ID!, input: UpdateListingInput!): Listing!
  deleteListing(id: ID!): Boolean!
  renewListing(id: ID!): Listing!
  expireListing(id: ID!): Listing! # Jobs
  markListingSold(id: ID!): Listing! # Classifieds/Cars/Homes
  
  # Photo mutations
  uploadListingPhoto(listingId: ID!, photo: Upload!): Photo!
  editListingPhoto(listingId: ID!, photoId: ID!, input: PhotoInput!): Photo!
  deleteListingPhoto(listingId: ID!, photoId: ID!): Boolean!
  
  # Favorite mutations
  favoriteListing(listingId: ID!, input: FavoriteInput): Favorite!
  unfavoriteListing(listingId: ID!): Boolean!
  updateFavorite(listingId: ID!, input: FavoriteInput!): Favorite!
  
  # Saved search mutations
  createSavedSearch(input: SavedSearchInput!): SavedSearch!
  updateSavedSearch(id: ID!, input: SavedSearchInput!): SavedSearch!
  deleteSavedSearch(id: ID!): Boolean!
  
  # Jobs-specific mutations
  boostJob(id: ID!, boostType: BoostType!): JobListing!
  configureAutoBoost(id: ID!, config: AutoBoostInput!): JobListing!
  
  # Payment mutations
  createPaymentIntent(input: PaymentIntentInput!): PaymentIntent!
  
  # Abuse mutations
  reportAbuse(listingId: ID!, input: AbuseReportInput!): AbuseReport!
}
```

---

### 4.4 Resolver Implementation Pattern

**Example: Listing Query Resolver**

```go
func (r *queryResolver) Listing(ctx context.Context, id string) (model.Listing, error) {
    // 1. Extract auth context (if needed)
    memberId, _ := auth.GetMemberIdFromContext(ctx)
    
    // 2. Call REST API
    resp, err := r.services.Listing.GetListing(ctx, id, memberId)
    if err != nil {
        return nil, err
    }
    
    // 3. Transform REST response to GraphQL type
    listing := transformToGraphQLListing(resp)
    
    // 4. Return GraphQL type
    return listing, nil
}
```

**Example: Search Query Resolver (Aggregates Multiple Calls)**

```go
func (r *queryResolver) Listings(ctx context.Context, filters model.SearchFilters, page *int, perPage *int) (*model.SearchResults, error) {
    // 1. Call listing search API
    searchResp, err := r.services.Listing.SearchListings(ctx, filters, page, perPage)
    if err != nil {
        return nil, err
    }
    
    // 2. Optionally enrich with additional data (e.g., stats for each listing)
    // This demonstrates aggregation across multiple REST calls
    if shouldIncludeStats(ctx) {
        for i, listing := range searchResp.Listings {
            stats, _ := r.services.Reports.GetListingStats(ctx, listing.ID)
            searchResp.Listings[i].Stats = stats
        }
    }
    
    // 3. Transform to GraphQL type
    results := transformToGraphQLSearchResults(searchResp)
    
    return results, nil
}
```

**Key Principles**:
- Resolvers are **thin wrappers** around REST API calls
- No business logic in resolvers
- Transform REST responses to GraphQL types
- Aggregate multiple REST calls when needed
- Error handling delegated to REST APIs

---

### 4.5 REST API Client Services 

**Service Interface Pattern**:

```go
type ListingService interface {
    GetListing(ctx context.Context, id string, memberId string) (*dto.Listing, error)
    SearchListings(ctx context.Context, filters dto.SearchFilters, page, perPage *int) (*dto.SearchResults, error)
    CreateListingDraft(ctx context.Context, input dto.CreateListingInput) (*dto.Listing, error)
    UpdateListing(ctx context.Context, id string, input dto.UpdateListingInput) (*dto.Listing, error)
    DeleteListing(ctx context.Context, id string) error
    RenewListing(ctx context.Context, id string) (*dto.Listing, error)
    // ... additional methods
}

type listingServiceImpl struct {
    httpClient *http.Client
    baseURL    string
    logger     o11y.Logger
}

func (s *listingServiceImpl) GetListing(ctx context.Context, id string, memberId string) (*dto.Listing, error) {
    url := fmt.Sprintf("%s/listings/%s", s.baseURL, id)
    
    req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)
    req.Header.Set("X-Member-ID", memberId) // Pass auth context
    
    resp, err := s.httpClient.Do(req)
    if err != nil {
        s.logger.Error("Failed to get listing", "error", err, "id", id)
        return nil, err
    }
    defer resp.Body.Close()
    
    if resp.StatusCode != http.StatusOK {
        return nil, parseAPIError(resp)
    }
    
    var result dto.Listing
    if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
        return nil, err
    }
    
    return &result, nil
}
```

---

### 4.6 Authentication & Directives

**Custom Directive: @auth**

```graphql
directive @auth(requires: Role = USER) on FIELD_DEFINITION

enum Role {
  USER
  DEALER
  MODERATOR
  ADMIN
}
```

**Implementation**:

```go
func AuthDirective(ctx context.Context, obj interface{}, next graphql.Resolver, requires Role) (interface{}, error) {
    // Extract JWT from context
    token, err := auth.GetTokenFromContext(ctx)
    if err != nil {
        return nil, errors.New("unauthorized")
    }
    
    // Verify token with Member API
    claims, err := auth.VerifyToken(token)
    if err != nil {
        return nil, errors.New("invalid token")
    }
    
    // Check role if required
    if !hasRequiredRole(claims, requires) {
        return nil, errors.New("insufficient permissions")
    }
    
    // Add claims to context for resolvers
    ctx = auth.AddClaimsToContext(ctx, claims)
    
    return next(ctx)
}
```

---

### 4.7 Error Handling

**GraphQL Error Extension**:

```go
func toGraphQLError(err error) *gqlerror.Error {
    // Parse REST API error
    apiErr, ok := err.(APIError)
    if !ok {
        return gqlerror.Errorf("internal server error")
    }
    
    return &gqlerror.Error{
        Message: apiErr.Message,
        Extensions: map[string]interface{}{
            "code": apiErr.Code,
            "details": apiErr.Details,
        },
    }
}
```

---

### 4.8 Testing Strategy

**Resolver Tests**:
- Mock REST API client services
- Verify correct API calls made
- Verify GraphQL type transformations
- Test error handling

**Integration Tests**:
- GraphQL query/mutation execution
- Mock REST API responses
- Verify authentication flow

---

## 5. Cross-Service Communication

### 5.1 Service Dependencies

```
marketplace-frontend (Next.js)
    ↓ GraphQL
marketplace-graphql
    ↓ HTTP REST
listing-http-rest
    ↓ HTTP REST (external)
    ├── Member API (auth, user data)
    ├── Image Service (photo upload/download)
    ├── Reports Service (statistics)
    ├── Payment Service (Stripe integration)
    └── Email Service (notifications)
    
    ↓ PubSub
    ├── listing-feed-subscriber (consumes)
    └── listing-ps-* services (produces events)
```

---

### 5.2 Event Publishing (PubSub)

**Events Published by listing-http-rest**:

- `listing.created` - New listing created
- `listing.updated` - Listing updated
- `listing.deleted` - Listing deleted
- `listing.expired` - Listing expired
- `listing.renewed` - Listing renewed
- `listing.featured` - Listing featured
- `listing.boosted` - Listing boosted (Jobs)

**Event Schema**:
```json
{
  "eventType": "listing.created",
  "timestamp": "2025-12-15T10:30:00Z",
  "listingId": "12345",
  "listingType": "JOB",
  "memberId": "67890",
  "data": { ... }
}
```

**Consumers**:
- `listing-ps-classifieds-events-to-bq` - Stream to BigQuery
- `listing-ps-google-shopping` - Update Google Shopping feed
- `saved-search-match-service` - Match against saved searches

---

### 5.3 Feed Data Flow

```
External Feed (XML/CSV)
    ↓
listing-feed-parser
    ↓ PubSub publish
PubSub Topic: listing-feed-data
    ↓ PubSub subscribe
listing-feed-subscriber
    ↓ HTTP REST
listing-http-rest (POST/PUT /listings)
```

---

## 6. Deployment & Operations

### 6.1 Service Deployment

**listing-http-rest**:
- Kubernetes deployment
- 3+ replicas for HA
- Horizontal pod autoscaling
- Health checks on `/health`
- Readiness checks on `/ready`

**marketplace-graphql**:
- Kubernetes deployment
- 2+ replicas for HA
- Load balancer with session affinity
- Health checks on `/health`

**listing-applications**:
- Kubernetes deployment
- 2+ replicas
- S3 access for file storage
- ClamAV sidecar container

**listing-feed-parser**:
- CronJob (daily/hourly runs)
- Slack notification on completion/failure

**listing-feed-subscriber**:
- Kubernetes deployment
- PubSub subscription with dead letter queue
- Auto-scaling based on message queue depth

---

### 6.2 Monitoring & Observability

**Metrics** (Prometheus):
- Request rate, latency, errors (RED metrics)
- Database connection pool stats
- Elasticsearch query performance
- Cache hit/miss rates
- PubSub message processing rate

**Logging** (Structured):
- Request/response logging
- Error logging with stack traces
- Audit logging (listing changes)
- Performance logging (slow queries)

**Tracing** (Datadog):
- Distributed tracing across services
- GraphQL → REST API → Database traces
- External service call traces

**Alerting**:
- Error rate > 1%
- Latency p99 > 1s
- Database connection pool exhaustion
- Elasticsearch cluster unhealthy
- PubSub message backlog > 1000

---

## 7. Migration Strategy

### Phase 1: Foundation
1. Deploy `listing-http-rest` with core endpoints
2. Deploy `marketplace-graphql` with basic schema
3. Migrate frontend to use GraphQL for new listings

### Phase 2: Feature Parity
4. Migrate all Classifieds endpoints
5. Migrate Jobs-specific features
6. Deploy `listing-applications` service
7. Cutover frontend to new services

### Phase 3: Optimization
8. Deploy feed services (parser + subscriber)
9. Performance optimization
10. Decommission legacy services

---

## 8. Success Criteria

### Service Health
- ✅ 99.9% uptime
- ✅ p95 latency < 200ms (REST API)
- ✅ p95 latency < 500ms (GraphQL)
- ✅ Error rate < 0.1%

### Code Quality
- ✅ Unit test coverage > 80%
- ✅ Integration test coverage for critical paths
- ✅ Linting passes (golangci-lint)
- ✅ Security scanning passes

### Documentation
- ✅ OpenAPI spec complete and accurate
- ✅ GraphQL schema documented
- ✅ README files in all services
- ✅ Architecture diagrams up to date

---

## 9. Open Questions & TODOs

1. **TODO @Chris**: Add virus scanning infrastructure details for `listing-applications`
2. **Decision Needed**: Choose web framework (Gin, Echo, or Chi) for `listing-http-rest`
3. **Decision Needed**: Redis vs Memcached for caching (recommendation: Redis for better features)
4. **Research Needed**: Elasticsearch cluster sizing for production load
5. **Design Needed**: Feed parser error handling and retry strategy
6. **Design Needed**: Dead letter queue handling for feed subscriber
