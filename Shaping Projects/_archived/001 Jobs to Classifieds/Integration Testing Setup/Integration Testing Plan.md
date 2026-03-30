# Integration Testing Plan: CAPI to listing-http-rest Migration

## Goal
Create integration tests that verify the new listing-http-rest service (Go) maintains parity with the legacy CAPI service (PHP) for listing CRUD operations during the Jobs to Classifieds migration.

## Background

### What We're Testing
- **Legacy System (CAPI)**: PHP/Symfony REST API at `Research Repos/Legacy/m-ksl-classifieds-api`
- **New System**: Go REST API at `Research Repos/marketplace-backend/apps/listing/services/listing-http-rest`

### Migration Context
The Jobs vertical is being migrated into the General Classifieds system. During this transition, we need to ensure that the new listing-http-rest service replicates the critical business logic from CAPI's ListingController.

## Critical Endpoints to Test

Based on the CAPI analysis, these endpoints have the most complex business logic that needs parity testing:

### 1. **Create Listing (CreateStub)**
- Dealer active listing limit enforcement
- Status set to "Stub"
- ID generation (atomic increment)
- PubSub event publishing (CREATE)

### 2. **Update Listing**
- Authorization (member ownership vs admin)
- Field validation and sanitization
- Price drop logic (24-hour cooldown, threshold calculation)
- Contact method validation (email/phone/text requirements)
- Category/subcategory lock on active listings
- Dealer phone override logic
- Rental rules handling by marketType
- Markdown/description field syncing
- PubSub event publishing (UPDATE vs CREATE)
- Status transitions

### 3. **Get Listing**
- PII filtering based on user role
- Contact info filtering by source
- Dealer info enrichment
- Member create time lookup

### 4. **Delete Listing**
- Authorization checks
- Valid deleteSource validation
- PubSub event publishing (DELETE)
- Audit trail generation

### 5. **Photo Operations**
- Upload photo with metadata generation
- Edit photo with renditions
- Delete photo with array re-indexing

## Testing Strategy

### Test Architecture

```
Integration Tests
├── Dual Service Orchestrator
│   ├── CAPI Client (HTTP requests to PHP service)
│   └── listing-http-rest Client (HTTP requests to Go service)
├── Test Fixtures (shared input data)
├── Response Comparator (verify parity)
└── Assertion Library (business logic validators)
```

### Test Environment Setup

**Docker Compose Configuration**:
```yaml
services:
  capi:
    # PHP service with Symfony
    # Connected to test MongoDB
    ports:
      - "8081:8080"
    environment:
      - MONGO_URL=mongodb://mongodb:27017
      - MONGO_DATABASE=classifieds_test

  listing-http-rest:
    # Go service
    # Connected to same test MongoDB
    ports:
      - "8082:8080"
    environment:
      - MONGO_URL=mongodb://mongodb:27017
      - MONGO_DATABASE=classifieds_test

  mongodb:
    image: mongo:5.0
    # Shared MongoDB for both services
    ports:
      - "27017:27017"
    volumes:
      - ./test-data/mongo-seed:/docker-entrypoint-initdb.d
```

**Note**: Elasticsearch is NOT needed for integration tests - we're testing CRUD operations and business logic, not search functionality.

### Test Implementation Approach

#### 1. **Comparative Integration Tests**

Test the same operation on both services and compare results:

```go
// Example test structure
func TestCreateListing_Parity(t *testing.T) {
    // Arrange
    input := fixtures.NewListingInput{
        MemberId: 12345,
        Title: "Test Job Listing",
        Category: "Jobs",
        // ... other fields
    }

    // Act - Call both services
    capiResponse := capiClient.CreateStub(input)
    newServiceResponse := listingHttpRestClient.CreateListing(input)

    // Assert - Compare responses
    assert.Equal(t, capiResponse.Status, newServiceResponse.Status)
    assert.NotEmpty(t, capiResponse.ListingId)
    assert.NotEmpty(t, newServiceResponse.ListingId)

    // Verify database state for both
    capiListing := getFromMongo(capiResponse.ListingId)
    newListing := getFromMongo(newServiceResponse.ListingId)

    // Compare critical fields
    assertListingsMatch(t, capiListing, newListing, ignoreFields)
}
```

#### 2. **Business Logic Validation Tests**

Test specific business rules independently:

```go
func TestDealerLimitEnforcement_BothServices(t *testing.T) {
    // Setup: Create dealer with limit of 5 active listings
    // Create 5 listings to reach limit

    // Act: Try to create 6th listing on both services
    capiErr := capiClient.CreateStub(newListing)
    newServiceErr := listingHttpRestClient.CreateListing(newListing)

    // Assert: Both should reject with similar error
    assert.Error(t, capiErr)
    assert.Error(t, newServiceErr)
    assert.Contains(t, capiErr.Error(), "limit")
    assert.Contains(t, newServiceErr.Error(), "limit")
}
```

#### 3. **State Verification Tests**

Verify that database state matches between services:

```go
func TestUpdateListing_PriceDrop_StateVerification(t *testing.T) {
    // Arrange: Create listing with price $100
    listingId := createTestListing(price: 10000) // cents

    // Act: Update price to $75 on both services
    capiClient.UpdateListing(listingId, {price: 7500})
    newServiceClient.UpdateListing(listingId, {price: 7500})

    // Assert: Verify reducedPriceData matches
    capiListing := getCapiListing(listingId)
    newListing := getNewServiceListing(listingId)

    assert.NotNil(t, capiListing.ReducedPriceData)
    assert.NotNil(t, newListing.ReducedPriceData)
    assert.Equal(t,
        capiListing.ReducedPriceData.OriginalPrice,
        newListing.ReducedPriceData.OriginalPrice)
}
```

## Test Scenarios by Priority

### Priority 1: Critical Path (Must Have)

1. **Create Listing - Basic Flow**
   - Valid input → listing created with "Stub" status
   - ID generated correctly (atomic increment)
   - Required fields populated
   - PubSub event published

2. **Update Listing - Status Transitions**
   - **CAPI**: Stub → Active status transition
   - **listing-http-rest**: Stub → pending_activation status transition
   - DisplayTime set correctly
   - Contact method validation
   - PubSub event published (CREATE type for first activation)
   - **Important**: Status transition behavior differs between services

3. **Get Listing - Authorization & PII**
   - Owner can see full listing
   - Guest sees PII-filtered listing
   - Dealer info enriched correctly

4. **Delete Listing - Basic Flow**
   - Authorized deletion works
   - PubSub event published
   - Audit trail created

### Priority 2: Business Logic (Should Have)

5. **Dealer Limit Enforcement**
   - Cannot exceed active listing limit
   - Error message consistent
   - Admin can override

6. **Price Drop Logic** (**CAPI ONLY**)
   - **CAPI**: Test 24-hour cooldown, threshold calculation, reducedPriceData
   - **listing-http-rest**: SKIP - Price drop logic will be event-driven (handled separately)
   - Tests should verify CAPI behavior but NOT expect parity in listing-http-rest

7. **Contact Method Validation**
   - Email required when contactMethod includes email
   - Phone required when contactMethod includes phone
   - Cell phone required when contactMethod includes text

8. **Category Lock on Listings**
   - **CAPI**: Non-admin cannot change category/subCategory on Active listing
   - **listing-http-rest**: Non-admin cannot change category/subCategory on Active OR pending_activation listing
   - Non-admin cannot change priceModifier/marketType on active listings
   - Admin can change restricted fields
   - **Important**: Lock behavior differs - listing-http-rest is stricter

9. **Dealer Phone Override**
   - When dealer has showDealerInfo=true
   - Listing uses dealer transfer phone/text
   - Override happens even if user provides different number

### Priority 3: Edge Cases (Nice to Have)

10. **Field Sanitization**
    - HTML stripped from title
    - Markdown parsed correctly
    - Description fields synced (markdown ↔ plain)

11. **Rental Rules Handling**
    - Preserved for "Rent" marketType
    - Cleared for non-Rent marketTypes

12. **Price Validation Edge Cases**
    - Zero price with callForQuote allowed
    - Zero price for "Wanted" marketType allowed
    - Price capped at subcategory maxPrice

13. **Photo Operations**
    - Upload generates correct metadata
    - Edit preserves photo order
    - Delete re-indexes array correctly

## Test Data Management

### MongoDB Test Data Structure

Based on CAPI test infrastructure research, create realistic test data:

#### Sample Test Documents for `general` Collection

**Document 1 - Basic Private Seller Listing**:
```json
{
  "id": 100,
  "memberId": 2615897,
  "status": "Active",
  "createTime": 1629153094,
  "displayTime": 1629153897,
  "modifyTime": 1629153598,
  "expireTime": 1631745897,
  "category": "General",
  "subCategory": "Junk For Sale",
  "title": "Test Item for Sale",
  "description": "Basic test listing",
  "price": 7600,
  "marketType": "Sale",
  "sellerType": "Private",
  "city": "Salt Lake City",
  "state": "UT",
  "zip": "84101",
  "name": "Jimmy Donaldson",
  "email": "jimbo@bob.com",
  "contactMethod": ["messages", "phoneEmail"]
}
```

**Document 2 - Dealer with Photos and Complex Data**:
```json
{
  "id": 23456789,
  "memberId": 2345678,
  "status": "Active",
  "createTime": 1629153094,
  "displayTime": 1629153897,
  "modifyTime": 1629153598,
  "expireTime": 1631745897,
  "category": "Recreational Vehicles",
  "subCategory": "Travel Trailers, Bumper Pull",
  "title": "HIDEOUT 24BHS",
  "description": "Detailed RV description...",
  "descriptionMarkdown": "Markdown version...",
  "price": 2699500,
  "marketType": "Sale",
  "sellerType": "Business",
  "stockNumber": "spincarId",
  "newUsed": "New",
  "city": "Jerome",
  "state": "ID",
  "zip": "83338",
  "lat": 42.7098,
  "lon": -114.461,
  "name": "Lucius Fox",
  "email": "lfox@wayneindustries.com",
  "cellPhone": "999-999-9999",
  "contactMethod": ["messages", "phoneEmail"],
  "photo": [
    {
      "id": "http://img.ksl.com/mx/mplace-classifieds.ksl.com/2345678-1629153094-168072.jpg",
      "extension": "jpg",
      "height": "635",
      "width": "392",
      "uploadTime": 1629153096
    }
  ],
  "dealerData": {
    "dealerName": "Southern Idaho RV and Marine",
    "city": "Jerome",
    "state": "ID",
    "zip": "83338",
    "activeLimit": true,
    "limitNumber": 500
  }
}
```

**Document 3 - Rental Listing**:
```json
{
  "id": 61111111,
  "memberId": 222222,
  "status": "Active",
  "category": "General",
  "subCategory": "Junk For Sale",
  "marketType": "Rent",
  "priceModifier": "perWeek",
  "renewCount": 2,
  "title": "Rental Item",
  "description": "Weekly rental available",
  "price": 5000
}
```

**Document 4 - Stub Listing (Draft)**:
```json
{
  "id": 200,
  "memberId": 2615897,
  "status": "Stub",
  "createTime": 1629153094,
  "category": "Furniture",
  "subCategory": "Dressers"
}
```

#### Dealer Test Documents for `general_dealer` Collection

**Dealer 1 - With Active Limit**:
```json
{
  "memberId": 2345678,
  "dealerName": "Southern Idaho RV and Marine",
  "city": "Jerome",
  "state": "ID",
  "zip": "83338",
  "limits": {
    "status": "Active",
    "limitType": "General",
    "limitNumber": 500
  },
  "showMoreListingsBySellerCarousel": true,
  "transferNumber": "5555555555",
  "transferTextNumber": "5555555556",
  "logo": "https://img.ksl.com/mx/mplace-classifieds.ksl.com/logo.png"
}
```

**Dealer 2 - With Transfer Phone Override**:
```json
{
  "memberId": 12345,
  "dealerName": "Wayne Enterprises, Inc.",
  "city": "Gotham City",
  "state": "UT",
  "zip": "84101",
  "limits": {
    "status": "Active",
    "limitType": "General",
    "limitNumber": 15
  },
  "transferNumber": "8015551234",
  "transferTextNumber": "8015551235",
  "showDealerInfo": true
}
```

### JWT Test Payloads

**Standard User**:
```json
{
  "member": {
    "kslMemberId": "2615897",
    "kslMemberGroup": "member",
    "classifiedsMemberGroup": "member",
    "first": "Jimmy",
    "last": "Donaldson",
    "email": "jimbo@bob.com"
  }
}
```

**Admin User**:
```json
{
  "member": {
    "kslMemberId": "999999",
    "kslMemberGroup": "admin",
    "classifiedsMemberGroup": "admin",
    "first": "Admin",
    "last": "User",
    "email": "admin@ksl.com"
  }
}
```

### Database Seeding Strategy

1. **Pre-load MongoDB with test documents** before running integration tests
2. **Use separate test database** (`classifieds_test`) to avoid conflicts
3. **Seed collections**:
   - `general` - 4+ test listings (Active, Stub, Rental, Dealer)
   - `general_dealer` - 2+ test dealers with different configurations
   - `general_category` - Category tree definitions
   - `idTracker` - ID sequence starting at 1000 for test listings

### Cleanup Strategy

After each test:
1. Restore original test documents (reset modified listings)
2. Delete any newly created listings (ID > 1000)
3. Reset idTracker to 1000
4. Clear any temp collections

## Testing Tools & Frameworks

### Recommended Stack

**Primary Testing Framework**: Go's standard `testing` package
- Consistent with existing listing-http-rest tests
- No external dependencies
- Good CI/CD integration

**HTTP Client**: `net/http` with `httptest` for server mocking
- Standard library
- Used in existing tests

**Assertions**: `github.com/stretchr/testify/assert`
- Already used in marketplace-backend
- Rich assertion library

**MongoDB Testing**:
- **Option A**: Real MongoDB in Docker (better for integration tests)
- **Option B**: `mtest` package (already used in listing-http-rest)

**CAPI Client**: Custom HTTP client wrapper
```go
type CapiClient struct {
    baseURL string
    httpClient *http.Client
}

func (c *CapiClient) CreateStub(input CreateStubInput) (*CreateStubResponse, error)
func (c *CapiClient) UpdateListing(id int, input UpdateListingInput) (*UpdateListingResponse, error)
func (c *CapiClient) GetListing(id int, options GetListingOptions) (*ListingResponse, error)
func (c *CapiClient) DeleteListing(id int, deleteSource string) error
```

**listing-http-rest Client**:
- Use existing service client or create thin wrapper
- Mirror CAPI client interface for easy comparison

### Test Execution

```bash
# Run all integration tests
go test ./tests/integration/... -tags=integration

# Run specific test suite
go test ./tests/integration/create_listing_test.go -v

# Run with MongoDB in Docker
docker-compose up -d mongodb capi listing-http-rest
go test ./tests/integration/... -tags=integration

# Generate coverage report
go test ./tests/integration/... -tags=integration -coverprofile=coverage.out
go tool cover -html=coverage.out
```

## Success Criteria

### Parity Verification

Tests pass when both services:
1. Return equivalent HTTP status codes for same inputs
2. Create identical database records (ignoring auto-generated fields like timestamps)
3. Publish equivalent PubSub events
4. Apply same business logic validations
5. Return consistent error messages for validation failures

### Acceptable Differences

Document known acceptable differences:
- **Status Transitions**:
  - CAPI: Stub → Active
  - listing-http-rest: Stub → pending_activation
- **Category Lock**:
  - CAPI: Only locks Active listings
  - listing-http-rest: Locks both Active AND pending_activation listings
- **Price Drop Logic**:
  - CAPI: Implements full price drop logic (24-hour cooldown, reducedPriceData)
  - listing-http-rest: NO price drop logic (event-driven, handled separately)
- Timestamp precision (PHP vs Go time handling)
- Error message formatting (as long as error codes match)
- Response field ordering (JSON field order)
- Log message formatting

## Implementation Plan

### Phase 1: MongoDB Test Database Setup (1-2 days)
1. Create MongoDB seeding script from CAPI test fixtures
2. Set up `classifieds_test` database with collections:
   - `general` (4+ test listings)
   - `general_dealer` (2+ dealers)
   - `general_category` (category tree)
   - `idTracker` (sequence generator)
3. Create database reset/cleanup utilities
4. Verify both CAPI and listing-http-rest can connect to test DB

### Phase 2: Test Infrastructure (2-3 days)
1. Create Go test framework structure in `marketplace-backend/apps/listing/services/listing-http-rest/tests/integration/`
2. Implement HTTP clients:
   - `CapiTestClient` - wrapper for CAPI endpoints
   - `ListingRestTestClient` - wrapper for listing-http-rest endpoints
3. Create response comparison utilities:
   - Field-by-field comparators
   - Ignore list for acceptable differences (timestamps, etc.)
   - Deep equality checkers for nested objects
4. Implement JWT generation helpers for test users
5. Create MongoDB query helpers for state verification

### Phase 3: CRUD Operation Tests (4-6 days)

**3.1 Create Listing Tests**:
- Basic create (minimal fields)
- Create with full fields
- Dealer limit enforcement
- Invalid input validation
- ID generation verification

**3.2 Get Listing Tests**:
- Get by ID (owner)
- Get by ID (guest with PII filtering)
- Get by ID (non-existent)
- Get with dealer info enrichment
- Get with stats

**3.3 Update Listing Tests**:
- Basic field updates
- Status transitions:
  - **CAPI**: Stub → Active
  - **listing-http-rest**: Stub → pending_activation
- Price updates (basic - no price drop logic in listing-http-rest)
- **CAPI only**: Price drop with 24-hour cooldown (skip for listing-http-rest)
- Contact method validation
- Category lock:
  - **CAPI**: Lock on Active status
  - **listing-http-rest**: Lock on Active OR pending_activation status
- Dealer phone override
- Field sanitization (HTML stripping, markdown)

**3.4 Delete Listing Tests**:
- Owner deletion
- Admin deletion
- Authorization failures
- Audit trail verification
- Invalid deleteSource rejection

### Phase 4: Business Logic Tests (3-5 days)

**4.1 Authorization & Security**:
- Member ownership checks
- Admin override capabilities
- Service JWT access
- PII filtering by user role

**4.2 Dealer-Specific Logic**:
- Active listing limit enforcement
- Transfer phone override
- Dealer info enrichment
- CSL limit checks

**4.3 Validation Rules**:
- Contact method requirements (email/phone/text)
- Price validation by marketType
- Category/subcategory restrictions
- Zero price edge cases
- Field length limits

**4.4 Complex Business Logic**:
- Rental rules by marketType
- Markdown/description syncing
- Specification field validation
- Stock number handling
- **Note**: Price drop logic excluded from listing-http-rest comparison

### Phase 5: Edge Cases & Search (2-3 days)
1. Photo operations (if implemented)
2. Search endpoint parity
3. Listing counts endpoint
4. Statistics endpoint
5. Error message consistency

### Phase 6: Documentation (1-2 days)
1. Test execution guide
2. Database setup instructions
3. Troubleshooting guide
4. Coverage report generation
5. Known differences documentation

**Total Estimated Time**: 13-21 days

## Risks & Mitigations

### Risk 1: CAPI Behavior Unclear
**Mitigation**: Document actual CAPI behavior through observation tests. Create "characterization tests" that capture current behavior before comparing.

### Risk 2: Test Environment Complexity
**Mitigation**: Use Docker Compose for reproducible environments. Provide clear setup instructions and scripts.

### Risk 3: Test Maintenance Burden
**Mitigation**: Use fixtures and helper functions to reduce duplication. Focus on high-value tests that catch real bugs.

### Risk 4: Performance of Integration Tests
**Mitigation**: Run tests in parallel where possible. Use database transactions for faster cleanup. Consider running subset in CI, full suite nightly.

## Decisions Made

Based on user input and research:

1. **Test Approach**: Side-by-side comparison of CAPI vs listing-http-rest responses
2. **CAPI Setup**: Use local mock MongoDB with sample data from CAPI test fixtures
3. **Test Scope**: ALL CRUD operations (not just Jobs-specific)
4. **External Services**: Will be handled in later work (defer for now)
5. **Test Data Source**: Use `tests/Controller/data/listings/` from CAPI as template

## Deliverables

1. **MongoDB Test Database**:
   - Seeding script using CAPI test fixture patterns
   - 10+ realistic test documents covering various scenarios
   - Database reset/cleanup utilities
   - Location: `marketplace-backend/scripts/seed-test-db.go`

2. **Test Suite**:
   - Go integration tests in `marketplace-backend/apps/listing/services/listing-http-rest/tests/integration/`
   - Test structure:
     ```
     tests/integration/
     ├── setup_test.go              # DB seeding, cleanup
     ├── clients/
     │   ├── capi_client.go         # HTTP client for CAPI
     │   └── listingrest_client.go  # HTTP client for listing-http-rest
     ├── comparators/
     │   ├── response_comparator.go # Response comparison utilities
     │   └── db_comparator.go       # Database state comparison
     ├── create_listing_test.go
     ├── get_listing_test.go
     ├── update_listing_test.go
     ├── delete_listing_test.go
     ├── dealer_logic_test.go
     ├── validation_test.go
     └── search_test.go
     ```

3. **Test Fixtures**:
   - JSON files based on CAPI `tests/Controller/data/listings/` patterns
   - JWT payloads for various user types
   - Request/response templates

4. **Documentation**:
   - `tests/integration/README.md` with:
     - Setup instructions
     - Running tests
     - Understanding test output
     - Debugging failed tests
   - Known differences/acceptable variations document

5. **Test Report**:
   - Parity verification checklist
   - Coverage metrics (endpoints, business logic scenarios)
   - Gap analysis (what's not yet implemented in listing-http-rest)
   - Recommendations for migration readiness

## Next Steps

1. **Immediate**: Review and approve this plan
2. **Phase 1**: Create MongoDB test database with seed data from CAPI fixtures
3. **Phase 2**: Build test infrastructure (clients, comparators, helpers)
4. **Phase 3**: Implement CRUD operation tests
5. **Phase 4**: Add business logic tests
6. **Phase 5**: Edge cases and search tests
7. **Phase 6**: Documentation and reporting

## Key Files to Reference During Implementation

### From CAPI (`Research Repos/Legacy/m-ksl-classifieds-api/`):
- `src/Controller/ListingController.php` - Business logic source of truth
- `tests/Controller/ListingControllerTest.php` - Test patterns and scenarios
- `tests/Controller/data/listings/` - Test fixture examples (35+ scenarios)
- `src/Db/Mongo/GeneralCollection.php` - MongoDB document structure

### In listing-http-rest (`Research Repos/marketplace-backend/apps/listing/services/listing-http-rest/`):
- `internal/handler/*_test.go` - Existing test patterns
- `internal/store/listingMongo_crud.go` - MongoDB operations
- `internal/domain/` - Business logic implementations
- `routes.go` - Endpoint definitions

## Success Metrics

Integration tests will be considered successful when:

1. **Coverage**: 90%+ of CAPI ListingController business logic tested
2. **Parity**: Both services produce identical results for 95%+ of test cases
3. **Reliability**: Tests run consistently without flakes
4. **Documentation**: Clear setup and execution instructions
5. **Actionable**: Test failures clearly identify parity gaps

## Risk Mitigation

### Risk: Test data doesn't match production patterns
**Mitigation**: Use actual CAPI test fixtures as blueprint

### Risk: Services have subtle behavioral differences
**Mitigation**: Side-by-side comparison catches differences immediately

### Risk: External service mocking complexity
**Mitigation**: Defer external services to later work (as user specified)

### Risk: MongoDB connection issues
**Mitigation**: Use local MongoDB in Docker, connection string configuration

---

**Note**: This plan focuses on comparative integration testing to verify parity. It does NOT include:
- Unit tests for individual functions (already covered by existing tests)
- Load/performance testing
- Security testing
- End-to-end UI testing
- Elasticsearch indexing verification (separate concern)
