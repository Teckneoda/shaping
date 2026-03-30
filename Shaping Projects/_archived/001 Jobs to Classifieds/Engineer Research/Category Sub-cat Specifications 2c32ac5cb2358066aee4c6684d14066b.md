# Category/Sub-cat Specifications

ℹ️ While category level specifications could be useful in General Classifieds, I think it may be easier to just add [Jobs specific fields](https://www.notion.so/Jobs-Listing-Fields-For-Moving-Into-General-Classifieds-2bd2ac5cb2358085a57ada835369a06f?pvs=21) at this time.

# Classifieds Category Specifications Analysis

**Analyzed Repositories:**
- `m-ksl-classifieds` - Legacy PHP frontend application for classifieds
- `m-ksl-classifieds-api` - Symfony backend API for classifieds (source of truth)
- `nest/classifieds/categoryManager` - React admin tool for managing categories
- `nest/classifieds/specificationManager` - React admin tool for managing specifications
- `marketplace-graphql` - Go/GraphQL API layer for Next.js frontends
- `marketplace-frontend` - Next.js frontend for marketplace (modern replacement)
- `ksl-api` - Legacy shared API services (no specification usage found)

---

## 1. Architecture Overview

### 1.1 Data Storage

**MongoDB Collections:**
- `generalCategory` (or `generalCategoryDev`) - Production category data
- `generalCategoryInProgress` (or `generalCategoryInProgressDev`) - Draft/staging category data

**Structure:**

```jsx
{
  // Category Document
  type: "category",
  id: 123,
  title: "Community",
  metaPageTitle: "...",
  metaDescription: "...",
  new: true,
  newUntilTime: 1234567890,
  // ... other category fields
}

{
  // SubCategory Document
  type: "subCategory",
  id: 456,
  parent_id: 123,
  title: "Pets",
  featurePrice: 7.00,
  listingTypes: {
    Sale: true,
    Wanted: true,
    Rent: false,
    Service: false
  },
  pricingType: "regular", // "regular", "zero", "free"
  priceDropThreshold: {
    type: "percentage", // "none", "percentage", "amount"
    value: 5
  },
  specifications: [...], // Array of specification objects
  hiddenSellFormFields: ["newUsed", "video", "tour"],
  listingFee: 5.00,
  listingRentalFee: 10.00,
  renewFee: 2.00,
  renewRentalFee: 5.00,
  maxPrice: 10000.00,
  limitRenew: true,
  maxRenewCount: 3,
  subscription: {
    listingFee: {
      enabled: false,
      title: "Listing Fee",
      prodStripeId: "price_xxx",
      prodAmount: 5.00,
      testStripeId: "price_yyy",
      testAmount: 5.00
    }
  },
  deprecated: true,
  moved: true,
  newCategory: "Pets",
  newCategoryId: 789,
  newSubcategory: "Dogs",
  newSubcategoryId: 101,
  sunsetTime: 1234567890,
  // Change tracking flags
  specificationsChanged: true,
  featuredPriceChanged: true,
  listingFeeChanged: true,
  // ... other change flags
}
```

### 1.2 Specification Field System

**Field Types and Limits:**

Per `m-ksl-classifieds-api/src/Library/Specification/SpecMapping.php`:

```php
const FIELD_TYPE_COUNT = [
    'string' => 10,  // specSubCatString1 - specSubCatString10
    'int' => 10,     // specSubCatInt1 - specSubCatInt10
    'float' => 2,    // specSubCatFloat1 - specSubCatFloat2
];

const INPUT_TYPE_FIELD_TYPE = [
    'select' => 'string',      // Dropdown/select fields
    'rangeInt' => 'int',       // Integer range (e.g., 100-500)
    'rangeFloat' => 'float',   // Decimal range (e.g., 2.5-10.75)
];
```

**Total Available Specification Slots:**
- 10 string fields (for select dropdowns)
- 10 integer fields (for integer ranges)
- 2 float fields (for decimal ranges)
- **Total: 22 specification fields per subcategory**

### 1.3 Specification Object Structure

```jsx
{
  fieldname: "specSubCatString1",  // Auto-assigned based on inputType
  label: "Brand",                   // Display label
  slug: "brand",                    // URL-friendly identifier
  status: "Active",                 // "Active" or "Inactive"
  inputType: "select",              // "select", "rangeInt", "rangeFloat"
  weight: 1,                        // Display order (lower = higher priority)
  isRequired: false,                // Whether field is required on sell form
  inputConfig: {
    // For "select" type:
    values: [
      {
        label: "Apple",
        value: "apple",
        weight: 1
      },
      // ... more options
    ],
    sort: "alpha", // "alpha", "weight", or "none"
    
    // For "rangeInt" or "rangeFloat" type:
    min: 0,
    max: 1000,
    precision: 2,
    unit: "lbs"
  }
}

```

---

## 2. Repository-Specific Implementation

### 2.1 m-ksl-classifieds-api (Symfony Backend)

**Key Components:**

### Controllers

- **CategoryController** (`src/Controller/CategoryController.php`)
    - `getCategoryTree()` - Retrieves category/subcategory tree
    - `getCategoryFilters()` - Gets all category filter info
    - `getCategorySeo()` - Gets SEO metadata
    - `createSubCategorySpecification()` - Creates new spec field
    - `updateSubCategorySpecification()` - Updates existing spec field
    - `updateSpecificationWeights()` - Reorders spec fields
    - `getSubCategorySpecifications()` - Gets all specs for a subcategory

### Helpers

- **CategoryHelper** (`src/Helper/CategoryHelper.php`)
    - Manages production category data
    - Handles caching (Memcache)
    - `getCategoryTree()` - Main method for retrieving category tree
        - Supports options: `keyType`, `showFields`, `specSort`, `specHashify`, etc.
    - `getMappedListingSpecifications()` - Maps spec fieldnames to labels
    - `filterCategoryTreeSunsetItems()` - Hides deprecated categories
- **CategoryInProgressHelper** (`src/Helper/CategoryInProgressHelper.php`)
    - Manages draft/staging category data
    - `createSpecification()` - Validates and creates new spec
    - `updateSpecification()` - Updates existing spec
    - `validateSpecification()` - Validates spec data structure
    - `getNextAvailableSpecFieldname()` - Finds next available slot
    - `getAvailableSpecFieldTypes()` - Returns count of available slots

### Database Collections

- **GeneralCategoryCollection** (`src/Db/Mongo/GeneralCategoryCollection.php`)
    - Handles production category MongoDB operations
    - `getCategoryTree()` - Aggregation pipeline for tree structure
    - `getSeoCategoryTree()` - SEO-only data
    - `getAllCategoryFilterInformation()` - For search filters
- **GeneralCategoryInProgressCollection** (`src/Db/Mongo/GeneralCategoryInProgressCollection.php`)
    - Extends GeneralCategoryCollection
    - `createSpec()` - Pushes new spec to array
    - `updateSpec()` - Updates spec at specific index
    - `updateSpecFieldWeight()` - Updates weight fields

**API Endpoints:**

```
GET  /category-tree
     ?options={"showFields":["specifications"],"specSort":true}
     &category=Community
     &subCategory=Pets

GET  /category-filters

POST /category/subcategory/specification/create
     Body: {category, subCategory, specification}

PUT  /category/subcategory/specification/update
     Body: {category, subCategory, specification}

PUT  /category/subcategory/specification/weights
     Body: {category, subCategory, fieldWeightArray}

GET  /category/subcategory/specifications
     ?category=Community
     &subCategory=Pets
     &specSort=true
     &specHashify=true
     &specIncludeInactive=false
```

**Validation Rules:**

Per `src/Validator/Specification.php`:
- Label: required, string
- Slug: required, string, unique per subcategory
- Status: “Active” or “Inactive”
- InputType: Cannot change once created
- Select options: unique labels and values
- Range fields: min < max, valid precision

---

### 2.2 nest/classifieds (Admin Tools)

### Category Manager (`assets/categoryManager/`)

**Purpose:** Admin interface for managing categories, subcategories, and their properties.

**Tech Stack:**
- React with Redux
- Material-UI
- react-window (for virtualized rendering of large lists)

**Key Features:**

**Configurable Columns** (`src/config/index.js`):

```jsx
const rowConfig = [
  { name: 'Title', scope: ['category', 'subCategory'], permanent: true },
  { name: 'Featured Price', scope: ['subCategory'], changedIndicator: 'featuredPriceChanged' },
  { name: 'Listing Fee', scope: ['subCategory'], changedIndicator: 'listingFeeChanged' },
  { name: 'Listing Type', scope: ['subCategory'], changedIndicator: 'listingTypeChanged' },
  { name: 'Pricing', scope: ['subCategory'], changedIndicator: 'pricingTypeChanged' },
  { name: 'Price Drop', scope: ['subCategory'], changedIndicator: 'priceDropThresholdChanged' },
  { name: 'Specifications', scope: ['subCategory'], actionScope: [] }, // Read-only
  { name: 'Hidden', scope: ['subCategory'], changedIndicator: 'hiddenSellFormFieldsChanged' },
  // ... more columns
];
```

**SubCategory Properties Managed:**
- `featurePrice` - Cost to feature a listing
- `listingFee` / `listingRentalFee` - Upfront posting fees
- `renewFee` / `renewRentalFee` - Renewal fees
- `maxPrice` - Maximum listing price allowed
- `limitRenew` / `maxRenewCount` - Renewal limits
- `listingTypes` - Which listing types are allowed (Sale, Wanted, Rent, Service)
- `pricingType` - Price field behavior (“regular”, “zero”, “free”)
- `priceDropThreshold` - Price drop notification settings
- `hiddenSellFormFields` - Fields to hide on sell form
- `subscription` - Stripe subscription settings
- `metaPageTitle` / `metaDescription` - SEO metadata

**Backend Integration:**

Uses `nest/classifieds/src/Lib/CategoryManager.php`:
- Endpoints mapped via `/classifieds/tools-proxy/category-manager/{method}`
- Methods like `getCategoryTree()`, `updateCategory()`, `addSubCategory()`, etc.

**Workflow:**
1. Edit categories in “In Progress” collection
2. Review pending changes
3. Publish to production (copies to `generalCategory`)
4. Auto-clears Memcache on publish
5. Sets `newUntilTime` and `sunsetTime` on publish

---

### Specification Manager (`assets/specificationManager/`)

**Purpose:** Dedicated admin interface for managing specification fields.

**Key Features:**
- Create/edit/delete specification fields
- Drag-and-drop reordering (weight management)
- Import specifications from other subcategories
- Real-time slot availability tracking
- Visual indication of field type availability

**Components:**

- **SpecificationForm** (`src/components/SpecificationForm.js`)
    - Label, slug, status (Active/Inactive)
    - Required checkbox
    - Input type selection (disabled after creation)
    - Type-specific configuration:
        - **Select**: Add/edit/reorder dropdown options
        - **Range**: Min, max, precision, unit
        - **Text**: (Future) Placeholder, validation rules
- **Input Type Options:**
    
    ```jsx
    const inputTypes = [
      { label: 'Select', value: 'select' },
      { label: 'Range, e.g. 12 - 156', value: 'rangeInt' },
      { label: 'Decimal Range, e.g. 12.5 - 156.23', value: 'rangeFloat' },
      // Future: text, textInt, textFloat
    ];
    ```
    
- **Slot Availability** (`src/utils/getSlotsByTypeAvailable.js`)
    - Tracks remaining slots per type
    - Disables input type selection when slots exhausted
    - Shows error: “Sorry, specification slots of this type are not available”

**Redux Actions:**
- `saveSpecification()` - Creates or updates spec
- `updateForm()` - Updates form state
- `reorderByWeight()` - Changes display order

---

### 2.3 m-ksl-classifieds (Legacy Frontend)

**Specification Helper** (`application/helpers/SpecificationHelper.php`):

```php
class SpecificationHelper
{
    public static $specificationKeys = [
        'specSubCatString1', 'specSubCatString2', ..., 'specSubCatString10',
        'specSubCatInt1', 'specSubCatInt2', ..., 'specSubCatInt10',
        'specSubCatFloat1', 'specSubCatFloat2'
    ];
    
    public static function _getSpecs($category, $subCategory, $apiClient, $hashify, $sort)
    {
        // Fetches specifications from m-ksl-classifieds-api
        // Supports hashifying (fieldname as key) and sorting
        // Respects inactive spec feature flag
    }
}
```

**Usage in Views:**
- Sell form renders specification fields dynamically
- Detail page displays specification values
- Search page uses specs for filtering

---

### 2.4 marketplace-graphql (Go/GraphQL Backend)

**Purpose:** GraphQL API layer that exposes category specifications to Next.js frontends.

**Tech Stack:**
- Go (Golang)
- gqlgen (GraphQL code generation)
- Connects to m-ksl-classifieds-api for category data

### Key Components

**CAPI Service** (`services/capi/`):

- **SpecificationsClient** (`specifications.go`)
    - Fetches and caches specifications from m-ksl-classifieds-api
    - 60-minute cache TTL
    - Uses singleflight pattern to prevent thundering herd
    - Exposes methods:
        - `GetSpecifications(ctx, category, subCategory)` - Returns array of specs
        - `GetSpecificationsMap(ctx, category, subCategory)` - Returns map[fieldname]Specification
        - `ListingHasSpecifications(listing)` - Checks if listing has any spec values
- **CategoryTree Client** (`catetoryTree.go`)
    - `GetPricesForCategory()` - Fetches category pricing
    - `GetCategorySeo()` - Fetches SEO metadata
- **GeneralListing Struct** (`classifiedListing.go`)
    
    ```go
    type GeneralListing struct {
        ID                int
        Category          string
        SubCategory       string
        // ... other fields
        
        // Specification fields (10 string, 10 int, 2 float)
        SpecSubCatString1  string
        SpecSubCatString2  string
        // ... through SpecSubCatString10
        
        SpecSubCatInt1     *int
        SpecSubCatInt2     *int
        // ... through SpecSubCatInt10
        
        SpecSubCatFloat1   *float64
        SpecSubCatFloat2   *float64
    }
    ```
    

**Query Resolvers** (`graph/queryresolvers/`):

- **legacy-searchfilters-classifieds.go**
    - `getClassifiedFilters()` - Builds filter groups for search page
    - `getSpecificationsFilters()` - Converts specs to SearchFilterComponent
    - `prepareSubCatSpecifications()` - Filters active specs, sorts by weight
    - Converts specifications into GraphQL filter components:
        - `select` → `SelectFilterComponent` (multi-select dropdown)
        - `rangeInt` → `RangeFilterComponent` (integer range)
        - `rangeFloat` → `RangeFilterComponent` (float range, currently cast to int)

**Data Flow:**

```
1. GraphQL Query (from Next.js frontend)
   ↓
2. SearchListingsConnectionResolver
   ↓
3. SpecificationsClient.GetSpecifications()
   ↓
4. CAPI.Fetch("/category-filters")
   ↓
5. m-ksl-classifieds-api (Symfony)
   ↓
6. MongoDB generalCategory collection
   ↓
7. Cache result for 60 minutes
   ↓
8. Transform to GraphQL types
   ↓
9. Return to frontend
```

### GraphQL Schema

**Types** (`graph/schema/types.listings.graphqls`):

```graphql
type ClassifiedListing implements Listing {
  id: Int!
  title: String!
  category: String!
  subCategory: String!
  # ... other fields
  
  """
  A list of all special features the listing includes.
  """
  specification: [Specification]
}

type Specification {
  label: String!        # e.g., "Brand"
  value: String!        # e.g., "apple"
  labelName: String     # Alternative display name
  valueName: String     # Alternative value display
}

input SpecificationInput {
  label: String!
  value: String!
}
```

**Category Types** (`graph/schema/types.categories.graphqls`):

```graphql
type CategorySeo {
  """
  Category SEO page title
  """
  metaPageTitle: String
  """
  Category SEO Description
  """
  metaDescription: String
}
```

**Search Filter Types** (`graph/schema/types.search.graphqls`):

Specifications are exposed as `SearchFilterComponent` objects:
- `SelectFilterComponent` - For select dropdowns
- `RangeFilterComponent` - For integer/float ranges
- `OptionFilterComponent` - For switches/toggles

### Specification Resolution

**Listing Detail Page:**
When a listing is fetched, specifications are resolved from raw fieldnames to human-readable labels:

```go
// In query resolver
listing := fetchListingFromCAPI(id)  // Has specSubCatString1: "apple"
specs, _ := specificationsClient.GetSpecifications(ctx, listing.Category, listing.SubCategory)

// Map fieldnames to labels
result := []model.Specification{}
for _, spec := range specs {
    if value := getValueFromListing(listing, spec.FieldName); value != "" {
        result = append(result, model.Specification{
            Label: spec.Label,      // "Brand"
            Value: value,           // "apple"
        })
    }
}
```

**Search Filters:**
Specifications become search filters dynamically based on category/subcategory selection:

```go
// prepareSubCatSpecifications() transforms specs
for _, spec := range specifications {
    if spec.Status != "Active" {
        continue  // Skip inactive specs
    }
    
    switch spec.InputType {
    case "select":
        filterGroup := SelectFilterGroup{
            Label: spec.Label,
            FieldName: spec.FieldName,
            Values: spec.InputConfig.Values,
        }
        // Convert to SearchFilterComponent
        
    case "rangeInt":
        filterGroup := IntRangeFilterGroup{
            Label: spec.Label,
            FieldName: spec.FieldName,
            Min: int(spec.InputConfig.Min),
            Max: int(spec.InputConfig.Max),
            OpenEndedMin: spec.InputConfig.OpenEndedMin,
            OpenEndedMax: spec.InputConfig.OpenEndedMax,
        }
        // Convert to SearchFilterComponent
        
    case "rangeFloat":
        // Similar to rangeInt but with float values
    }
}
```

### Caching Strategy

**Two-Level Caching:**

1. **SpecificationsClient Cache** (60 minutes)
    - In-memory cache within the Go application
    - Prevents repeated API calls to m-ksl-classifieds-api
    - Uses singleflight to dedupe concurrent requests
    - Automatic refresh on expiration
2. **Memcache (via CAPI)** (1 hour)
    - m-ksl-classifieds-api caches responses in Memcache
    - Shared across all API consumers
    - Invalidated on category publish

### Key Features

**Specification Filtering & Sorting:**
- Only `Active` specifications exposed to frontend
- Sorted by weight (descending), then slug (ascending)
- Select option values sorted by:
- `alpha` - Alphabetical by value
- `weight` - By weight field only
- `noSort` - As-is order (with weight priority)

**Number Formatting:**
Special handling for certain specification fieldnames:

```go
var NumberFormatConfig = map[string]model.NumberFormatType{
    "length":                model.NumberFormatTypeLocale,
    "grossvehicleweight":    model.NumberFormatTypeLocale,
    "mileage":               model.NumberFormatTypeLocale,
    "weight":                model.NumberFormatTypeLocale,
    // ... etc
}
```

**Open-Ended Ranges:**
Supports “any” minimum or maximum values:
- `OpenEndedMin: true` → defaults min to 0
- `OpenEndedMax: true` → defaults max to 100,000,000

### API Endpoints Used

```
GET /category-filters
  → Returns all categories/subcategories with their specifications
  → Cached for 60 minutes in SpecificationsClient

GET /category-tree?category=X&subCategory=Y&options=...
  → Returns pricing and other category metadata

GET /category-seo?category=X&subCategory=Y
  → Returns SEO metadata for category pages
```

### Testing

Comprehensive test coverage in `specifications_test.go`:
- Concurrent request deduplication
- Cache expiration behavior
- Specification mapping
- `ListingHasSpecifications()` edge cases

**Example Test Data:**

```go
{
    "category": "Appliances",
    "subCategory": "Sewing Machines",
    "specifications": [
        {
            "status": "Active",
            "isRequired": false,
            "label": "Brand",
            "slug": "brand",
            "inputType": "select",
            "fieldname": "specSubCatString1",
            "inputConfig": {
                "sort": "alpha",
                "values": [
                    {"label": "BERNINA", "value": "bernina", "weight": 0},
                    {"label": "Brother", "value": "brother", "weight": 0}
                ]
            }
        }
    ]
}
```

---

### 2.5 marketplace-frontend (Next.js)

**Current State:**
- Consumes GraphQL API from marketplace-graphql
- Frontend components fetch specifications via GraphQL queries
- Displays specs on listing detail pages
- Uses specs to build dynamic search filters

**Integration Points:**
- `apps/ksl-marketplace/app/sell/` - Sell form (fetches specs for selected category)
- `apps/ksl-marketplace/app/listing/[id]/` - Listing detail page (displays spec values)
- Search/filter components (renders dynamic filters based on specs)

**GraphQL Queries Used:**

```graphql
query GetClassifiedListing($id: Int!) {
  classifiedListing(id: $id) {
    id
    title
    category
    subCategory
    specification {
      label
      value
    }
  }
}

query GetSearchFilters($filters: ListingFilters!) {
  searchListings(filters: $filters) {
    filters {
      label
      components {
        ... on SelectFilterComponent {
          name
          label
          options {
            label
            option {
              ... on SearchFilterStringValue {
                value
              }
            }
          }
        }
      }
    }
  }
}
```

---

## 3. Data Flow & Lifecycle

### 3.1 Creating a Specification Field

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Admin opens Specification Manager                        │
│    - Selects category/subcategory                           │
│    - Views existing specifications                          │
│    - Sees available slot counts                             │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Admin creates new specification                          │
│    - Enters label: "Brand"                                  │
│    - Slug auto-generated: "brand"                           │
│    - Selects inputType: "select"                            │
│    - Adds options: Apple, Samsung, etc.                     │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. POST to m-ksl-classifieds-api                            │
│    /category/subcategory/specification/create               │
│    {                                                        │
│      category: "Community",                                 │
│      subCategory: "Pets",                                   │
│      specification: {                                       │
│        label: "Brand",                                      │
│        slug: "brand",                                       │
│        inputType: "select",                                 │
│        inputConfig: { values: [...] }                       │
│      }                                                      |
│    }                                                        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. CategoryInProgressHelper::createSpecification()          │
│    - Validates label and slug uniqueness                    │
│    - Calls getNextAvailableSpecFieldname()                  │
│      → Returns "specSubCatString1"                          │
│    - Adds fieldname to specification object                 │
│    - Sets weight based on current spec count                │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. GeneralCategoryInProgressCollection::createSpec()        │
│    MongoDB Update:                                          │
│    {                                                        │
│      $push: {                                               │
│        specifications: {                                    │
│          fieldname: "specSubCatString1",                    │
│          label: "Brand",                                    │
│          slug: "brand",                                     │
│          inputType: "select",                               │
│          status: "Active",                                  │
│          weight: 1,                                         │
│          inputConfig: {...}                                 │
│        }                                                    │
│      },                                                     │
│      $set: { specificationsChanged: true }                  │
│    }                                                        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. Specification stored in InProgress collection            │
│    - Not yet live on production site                        │
│    - Visible in admin tools                                 │
│    - Marked as changed for review                           │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Publishing Specifications to Production

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Admin reviews pending changes in Category Manager        │
│    - CategoryManager::getInProgressChanges()                │
│    - Shows diff between InProgress and Prod                 │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Admin clicks "Publish to Production"                     │
│    - CategoryManager::copyInProgressToProd()                │
│    - Validates changes exist                                │
│    - Saves change log to generalLog collection              │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Copy operation                                           │
│    - Reads all from generalCategoryInProgress               │
│    - Removes change tracking flags                          │
│    - Sets newUntilTime for new items (+30 days)             │
│    - Sets sunsetTime for deprecated items (+30 days)        │
│    - Deletes all from generalCategory                       │
│    - Inserts cleaned data into generalCategory              │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Cache invalidation                                       │
│    - Memcache::delete('general-categories-main')            │
│    - Memcache::delete('general-categories-seo')             │
│    - Delete per-subcategory cache keys                      │
│    - Wait 2 seconds for MongoDB replication                 │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Sync InProgress with Prod                                │
│    - Copy Prod back to InProgress                           │
│    - Ensures both in sync for next edit                     │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 Using Specifications in Listings

### Modern Flow (marketplace-frontend → marketplace-graphql)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. User on Next.js sell form                                │
│    - Selects category/subcategory                           │
│    - Frontend executes GraphQL query                        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. GraphQL Query to marketplace-graphql                     │
│    query GetSearchFilters($filters: ListingFilters!) {      │
│      searchListings(filters: $filters) {                    │
│        filters {                                            │
│          label                                              │
│          components {                                       │
│            ... on SelectFilterComponent { ... }             │
│            ... on RangeFilterComponent { ... }              │
│          }                                                  │
│        }                                                    │
│      }                                                      │
│    }                                                        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. marketplace-graphql (Go)                                 │
│    SearchListingsConnectionResolver.getClassifiedFilters()  │
│    → SpecificationsClient.GetSpecifications()               │
│    → Check 60-minute in-memory cache                        │
│    → If expired, fetch from CAPI                            │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. CAPI.Fetch("/category-filters")                          │
│    → m-ksl-classifieds-api                                  │
│    → CategoryHelper::getCategoryTree()                      │
│    → Check Memcache (1 hour TTL)                            │
│    → If miss, query MongoDB                                 │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Transform specs to GraphQL types                         │
│    - Filter to Active specs only                            │
│    - Sort by weight (desc), then slug (asc)                 │
│    - Convert inputType to FilterComponent type              │
│    - Return to Next.js frontend                             │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. Next.js renders dynamic form fields                      │
│    - SelectFilterComponent → Dropdown                       │
│    - RangeFilterComponent → Min/Max inputs                  │
│    - Shows required indicator if isRequired=true            │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. User submits via GraphQL mutation                        │
│    mutation CreateListing($input: ListingInput!) {          │
│      createListing(input: $input) {                         │
│        id                                                   │
│        specification { label value }                        │
│      }                                                      │
│    }                                                        │
│    Input includes:                                          │
│    specification: [                                         │
│      {label: "specSubCatString1", value: "golden-retriever"}│
│    ]                                                        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 8. marketplace-graphql → CAPI                               │
│    POST /listing/create                                     │
│    Body includes raw fieldnames:                            │
│    {                                                        │
│      specSubCatString1: "golden-retriever"                  │
│      specSubCatInt1_min: 8                                  │
│      specSubCatInt1_max: 12                                 │
│    }                                                        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 9. Listing stored with spec fieldnames                      │
│    - MongoDB general collection                             │
│    - Elasticsearch index for search                         │
│    - Spec values in raw fieldname format                    │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 10. Display on listing detail page                          │
│     GraphQL query fetches listing:                          │
│     query GetListing($id: Int!) {                           │
│       classifiedListing(id: $id) {                          │
│         specification {                                     │
│           label    // "Breed"                               │
│           value    // "golden-retriever"                    │
│           valueName // "Golden Retriever"                   │
│         }                                                   │
│       }                                                     │
│     }                                                       │
│     → marketplace-graphql resolves fieldnames to labels     │
│     → Next.js displays: "Breed: Golden Retriever"           │
└─────────────────────────────────────────────────────────────┘
```

### Legacy Flow (m-ksl-classifieds → m-ksl-classifieds-api)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. User on PHP sell form                                    │
│    - Selects category/subcategory                           │
│    - Frontend calls SpecificationHelper::_getSpecs()        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. REST API call to m-ksl-classifieds-api                   │
│    GET /category-tree                                       │
│    ?category=Community                                      │
│    &subCategory=Pets                                        │
│    &options={"showFields":["specifications"],               │
│              "specSort":true,                               │
│              "specHashify":false}                           │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. CategoryHelper::getCategoryTree()                        │
│    - Fetches from Memcache if available                     │
│    - Otherwise queries MongoDB with aggregation             │
│    - Filters: only Active specs, sorted by weight           │
│    - Caches for 1 hour                                      │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Sell form renders specification fields                   │
│    - Select type → Dropdown with options                    │
│    - RangeInt type → Two number inputs (min-max)            │
│    - RangeFloat type → Two decimal inputs (min-max)         │
│    - Shows required indicator if isRequired=true            │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. User submits listing with spec values                    │
│    POST /listing/create                                     │
│    {                                                        │
│      category: "Community",                                 │
│      subCategory: "Pets",                                   │
│      title: "Golden Retriever Puppies",                     │
│      price: 800,                                            │
│      specSubCatString1: "golden-retriever",  // Breed       │
│      specSubCatInt1_min: 8,                   // Age (weeks)│
│      specSubCatInt1_max: 12,                                │
│      ...                                                    │
│    }                                                        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. Listing stored with spec fieldnames                      │
│    - MongoDB general collection                             │
│    - Elasticsearch index for search                         │
│    - Spec values stored in raw fieldname format             │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 7. Display on listing detail page                           │
│    - CategoryHelper::getMappedListingSpecifications()       │
│    - Maps "specSubCatString1" → "Breed"                     │
│    - Maps "golden-retriever" → "Golden Retriever" (label)   │
│    - Renders as "Breed: Golden Retriever"                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Key Design Patterns & Features

### 4.1 Two-Stage Publishing

**InProgress → Production Pattern:**
- All changes staged in `generalCategoryInProgress`
- Reviewed before going live
- Atomic deployment (all-or-nothing)
- Change tracking via flags (`specificationsChanged`, etc.)
- Audit log in `generalLog` collection

### 4.2 Field Allocation Strategy

**Fixed Slot System:**
- Pre-allocated fieldnames in MongoDB/Elasticsearch schema
- No dynamic field creation (avoids schema changes)
- `specSubCatString1` through `specSubCatString10`
- `specSubCatInt1` through `specSubCatInt10`
- `specSubCatFloat1` through `specSubCatFloat2`

**Advantages:**
- Consistent database schema
- Elasticsearch mapping doesn’t change
- Easy to query/index
- No schema migrations needed

**Limitations:**
- Hard limit of 22 specs per subcategory
- Cannot add more without schema changes
- Deleted specs leave “holes” in allocation

### 4.3 Caching Strategy

**Multi-Layer Caching:**

1. **Memcache** (1 hour TTL)
    - `general-categories-main` - Full category tree (no specs, no SEO)
    - `general-categories-seo` - SEO data only
    - `general-categories-c-{cat}-s-{subcat}` - Specific subcategory (with specs)
2. **Cache Invalidation:**
    - On publish to production
    - Manual clear via admin tools
    - Auto-bypass in non-prod environments
3. **Cache Keys:**
    
    ```php
    // Main tree
    'general-categories-main'
    
    // SEO tree
    'general-categories-seo'
    
    // Specific subcategory
    'general-categories-c-community-s-pets'
    ```
    

### 4.4 Change Tracking

**Changed Flags:**
- `specificationsChanged`
- `featuredPriceChanged`
- `listingFeeChanged`
- `metaDataChanged`
- `listingTypeChanged`
- `pricingTypeChanged`
- `priceDropThresholdChanged`
- `hiddenSellFormFieldsChanged`
- `subscriptionChanged`

**Purpose:**
- Visual indicators in admin UI
- Change diff reporting
- Removed on publish to production

### 4.5 Deprecation & Sunset

**Lifecycle States:**

1. **Active** - Normal operation
2. **New** - Recently added (badge for 30 days)
3. **Deprecated** - Marked for removal, no new listings
4. **Sunset** - No longer visible to users

**Timestamps:**
- `newUntilTime` - When to remove “new” badge
- `sunsetTime` - When to completely hide

**Moved Categories:**
- `moved: true` - Category was relocated
- `newCategory` / `newSubcategory` - Destination
- Used for redirects and user messaging

---

## 5. API Reference

### 5.1 Get Category Tree

```
GET /category-tree
```

**Query Parameters:**
- `category` (string, optional) - Filter to specific category
- `subCategory` (string, optional) - Filter to specific subcategory
- `options` (JSON string, optional):

```json
{
  "keyType": "title",              // "title" | "id" | "array"
  "showFields": ["specifications"], // Additional fields to include
  "showSunsetItems": false,        // Include deprecated items
  "hideDeprecated": false,         // Hide deprecated items
  "noCache": false,                // Bypass cache
  "showListingCounts": false,      // Include active listing counts
  "inprogress": false,             // Use InProgress collection
  "specSort": true,                // Sort specifications by weight
  "specHashify": false,            // Use fieldname as key
  "specIncludeInactive": false     // Include inactive specs
}
```

**Response:**

```json
{
  "data": {
    "categoryTree": {
      "Community": {
        "id": 123,
        "title": "Community",
        "subCategories": {
          "Pets": {
            "id": 456,
            "title": "Pets",
            "featurePrice": 7.00,
            "listingTypes": {
              "Sale": true,
              "Wanted": true,
              "Rent": false,
              "Service": false
            },
            "pricingType": "regular",
            "specifications": [
              {
                "fieldname": "specSubCatString1",
                "label": "Breed",
                "slug": "breed",
                "status": "Active",
                "inputType": "select",
                "weight": 1,
                "inputConfig": {
                  "values": [
                    {"label": "Golden Retriever", "value": "golden-retriever", "weight": 1},
                    {"label": "Labrador", "value": "labrador", "weight": 2}
                  ],
                  "sort": "alpha"
                }
              }
            ]
          }
        }
      }
    }
  }
}
```

### 5.2 Create Specification

```
POST /category/subcategory/specification/create
```

**Request Body:**

```json
{
  "category": "Community",
  "subCategory": "Pets",
  "specification": {
    "label": "Brand",
    "slug": "brand",
    "status": "Active",
    "inputType": "select",
    "isRequired": false,
    "inputConfig": {
      "values": [
        {"label": "Apple", "value": "apple", "weight": 1},
        {"label": "Samsung", "value": "samsung", "weight": 2}
      ],
      "sort": "alpha"
    }
  }
}
```

**Response:**

```json
{
  "data": {
    "message": "Specification created",
    "fieldname": "specSubCatString1"
  },
  "meta": {
    "availableSpecFieldTypes": {
      "string": 9,
      "int": 10,
      "float": 2
    }
  }
}
```

### 5.3 Update Specification

```
PUT /category/subcategory/specification/update
```

**Request Body:**

```json
{
  "category": "Community",
  "subCategory": "Pets",
  "specification": {
    "fieldname": "specSubCatString1",
    "label": "Brand (Updated)",
    "slug": "brand",
    "status": "Active",
    "inputType": "select",
    "inputConfig": {
      "values": [...]
    }
  }
}
```

**Validation Rules:**
- Cannot change `inputType` after creation
- `label` and `slug` must be unique within subcategory
- For select: option labels and values must be unique
- For ranges: `min` < `max`

### 5.4 Update Specification Weights

```
PUT /category/subcategory/specification/weights
```

**Request Body:**

```json
{
  "category": "Community",
  "subCategory": "Pets",
  "fieldWeightArray": [
    {"fieldname": "specSubCatString1", "weight": 2},
    {"fieldname": "specSubCatString2", "weight": 1},
    {"fieldname": "specSubCatInt1", "weight": 3}
  ]
}
```

**Purpose:** Reorder specification fields for display

---

## 6. Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                         PRESENTATION LAYER                         │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌────────────────────────┐         ┌──────────────────────────┐   │
│  │ marketplace-frontend   │         │ m-ksl-classifieds        │   │
│  │ (Next.js)              │         │ (Legacy PHP)             │   │
│  │ - Modern UI            │         │ - Legacy UI              │   │
│  │ - GraphQL queries      │         │ - REST API calls         │   │
│  └───────────┬────────────┘         └───────────┬──────────────┘   │
│              │                                  │                  │
│              │ GraphQL                          │ REST             │
│              │                                  │                  │
└──────────────┼──────────────────────────────────┼──────────────────┘
               │                                  │
               ▼                                  │
┌─────────────────────────────────────────────────┼──────────────────┐
│                      API LAYER                  │                  │
├─────────────────────────────────────────────────┼──────────────────┤
│                                                 │                  │
│  ┌─────────────────────────────────┐            │                  │
│  │ marketplace-graphql (Go)        │            │                  │
│  │ ┌─────────────────────────────┐ │            │                  │
│  │ │ SpecificationsClient        │ │            │                  │
│  │ │ - 60min cache               │ │            │                  │
│  │ │ - Singleflight dedup        │ │            │                  │
│  │ └─────────────────────────────┘ │            │                  │
│  │ ┌─────────────────────────────┐ │            │                  │
│  │ │ Query/Mutation Resolvers    │ │            │                  │
│  │ │ - Transform to GraphQL types│ │            │                  │
│  │ │ - Filter Active specs       │ │            │                  │
│  │ └─────────────────────────────┘ │            │                  │
│  └───────────────┬─────────────────┘            │                  │
│                  │                              │                  │
│                  │ HTTP (JSON)                  │ HTTP (JSON)      │
│                  ▼                              ▼                  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ m-ksl-classifieds-api (Symfony)                              │  │
│  │ ┌─────────────────────┐    ┌────────────────────────────┐    │  │
│  │ │ CategoryController  │    │ CategoryHelper             │    │  │
│  │ │ - getCategoryTree() │    │ - getCategoryTree()        │    │  │
│  │ │ - getSubCategorySpecs│   │ - getMappedListingSpecs()  │    │  │
│  │ └─────────────────────┘    └────────────────────────────┘    │  │
│  │ ┌──────────────────────────────────────────────────────────┐ │  │
│  │ │ CategoryInProgressHelper                                 │ │  │
│  │ │ - createSpecification()                                  │ │  │
│  │ │ - updateSpecification()                                  │ │  │
│  │ │ - validateSpecification()                                │ │  │
│  │ └──────────────────────────────────────────────────────────┘ │  │
│  └─────────────┬───────────────────┬────────────────────────────┘  │
│                │                   │                               │
└────────────────┼───────────────────┼───────────────────────────────┘
                 │                   │
                 │ MongoDB           │ Memcache
                 │                   │
┌────────────────┼───────────────────┼───────────────────────────────┐
│               DATA LAYER           │                               │
├────────────────┼───────────────────┼───────────────────────────────┤
│                ▼                   ▼                               │
│  ┌────────────────────────┐  ┌────────────────┐                  │
│  │ MongoDB                │  │ Memcache       │                  │
│  │ - generalCategory      │  │ - 1hr TTL      │                  │
│  │ - generalCategoryInProg│  │ - Auto-clear   │                  │
│  │ - generalLog           │  │   on publish   │                  │
│  └────────────────────────┘  └────────────────┘                  │
│                                                                    │
│  ┌────────────────────────┐                                       │
│  │ Elasticsearch          │                                       │
│  │ - general index        │                                       │
│  │ - Spec field mappings  │                                       │
│  └────────────────────────┘                                       │
└────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        ADMIN TOOLS LAYER                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌────────────────────────┐         ┌──────────────────────────┐  │
│  │ categoryManager        │         │ specificationManager     │  │
│  │ (React)                │         │ (React)                  │  │
│  │ - Manage categories    │         │ - CRUD specifications    │  │
│  │ - Set pricing          │         │ - Drag & drop reorder    │  │
│  │ - Publish to prod      │         │ - Import from other cats │  │
│  └───────────┬────────────┘         └──────────┬───────────────┘  │
│              │                                  │                   │
│              │ REST API                         │ REST API          │
│              │                                  │                   │
│              ▼                                  ▼                   │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │ nest/classifieds/src/Lib/CategoryManager.php                 │ │
│  │ - getCategoryTree()                                           │ │
│  │ - updateCategory()                                            │ │
│  │ - addSubCategory()                                            │ │
│  │ - copyInProgressToProd()                                      │ │
│  └───────────────────────────────────────────────────────────────┘ │
│              │                                                      │
│              │ MongoDB (generalCategoryInProgress)                 │
│              ▼                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

```
┌────────────────────────────────────────────────────────────────────┐
│                         PRESENTATION LAYER                         │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌────────────────────────┐         ┌──────────────────────────┐   │
│  │ marketplace-frontend   │         │ m-ksl-classifieds        │   │
│  │ (Next.js)              │         │ (Legacy PHP)             │   │
│  │ - Modern UI            │         │ - Legacy UI              │   │
│  │ - GraphQL queries      │         │ - REST API calls         │   │
│  └───────────┬────────────┘         └───────────┬──────────────┘   │
│              │                                  │                  │
│              │ GraphQL                          │ REST             │
│              │                                  │                  │
└──────────────┼──────────────────────────────────┼──────────────────┘
               │                                  │
               ▼                                  │
┌─────────────────────────────────────────────────┼──────────────────┐
│                      API LAYER                  │                  │
├─────────────────────────────────────────────────┼──────────────────┤
│                                                 │                  │
│  ┌─────────────────────────────────┐            │                  │
│  │ marketplace-graphql (Go)        │            │                  │
│  │ ┌─────────────────────────────┐ │            │                  │
│  │ │ SpecificationsClient        │ │            │                  │
│  │ │ - 60min cache               │ │            │                  │
│  │ │ - Singleflight dedup        │ │            │                  │
│  │ └─────────────────────────────┘ │            │                  │
│  │ ┌─────────────────────────────┐ │            │                  │
│  │ │ Query/Mutation Resolvers    │ │            │                  │
│  │ │ - Transform to GraphQL types│ │            │                  │
│  │ │ - Filter Active specs       │ │            │                  │
│  │ └─────────────────────────────┘ │            │                  │
│  └───────────────┬─────────────────┘            │                  │
│                  │                              │                  │
│                  │ HTTP (JSON)                  │ HTTP (JSON)      │
│                  ▼                              ▼                  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ m-ksl-classifieds-api (Symfony)                              │  │
│  │ ┌─────────────────────┐    ┌────────────────────────────┐    │  │
│  │ │ CategoryController  │    │ CategoryHelper             │    │  │
│  │ │ - getCategoryTree() │    │ - getCategoryTree()        │    │  │
│  │ │ - getSubCategorySpecs│   │ - getMappedListingSpecs()  │    │  │
│  │ └─────────────────────┘    └────────────────────────────┘    │  │
│  │ ┌──────────────────────────────────────────────────────────┐ │  │
│  │ │ CategoryInProgressHelper                                 │ │  │
│  │ │ - createSpecification()                                  │ │  │
│  │ │ - updateSpecification()                                  │ │  │
│  │ │ - validateSpecification()                                │ │  │
│  │ └──────────────────────────────────────────────────────────┘ │  │
│  └─────────────┬───────────────────┬────────────────────────────┘  │
│                │                   │                               │
└────────────────┼───────────────────┼───────────────────────────────┘
                 │                   │
                 │ MongoDB           │ Memcache
                 │                   │
┌────────────────┼───────────────────┼───────────────────────────────┐
│               DATA LAYER           │                               │
├────────────────┼───────────────────┼───────────────────────────────┤
│                ▼                   ▼                               │
│  ┌────────────────────────┐  ┌────────────────┐                    │
│  │ MongoDB                │  │ Memcache       │                    │
│  │ - generalCategory      │  │ - 1hr TTL      │                    │ 
│  │ - generalCategoryInProg│  │ - Auto-clear   │                    │
│  │ - generalLog           │  │   on publish   │                    │
│  └────────────────────────┘  └────────────────┘                    │
│                                                                    │
│  ┌────────────────────────┐                                        │
│  │ Elasticsearch          │                                        │
│  │ - general index        │                                        │
│  │ - Spec field mappings  │                                        │
│  └────────────────────────┘                                        │
└────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        ADMIN TOOLS LAYER                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌────────────────────────┐         ┌──────────────────────────┐    │
│  │ categoryManager        │         │ specificationManager     │    │
│  │ (React)                │         │ (React)                  │    │
│  │ - Manage categories    │         │ - CRUD specifications    │    │
│  │ - Set pricing          │         │ - Drag & drop reorder    │    │
│  │ - Publish to prod      │         │ - Import from other cats │    │
│  └───────────┬────────────┘         └──────────┬───────────────┘    │
│              │                                  │                   │
│              │ REST API                         │ REST API          │
│              │                                  │                   │
│              ▼                                  ▼                   │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ nest/classifieds/src/Lib/CategoryManager.php                  │  │
│  │ - getCategoryTree()                                           │  │
│  │ - updateCategory()                                            │  │
│  │ - addSubCategory()                                            │  │
│  │ - copyInProgressToProd()                                      │  │ 
│  └───────────────────────────────────────────────────────────────┘  │
│              │                                                      │
│              │ MongoDB (generalCategoryInProgress)                  │
│              ▼                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## 7. Appendix: Example Category Data

### Example: Community > Pets Subcategory

```jsx
{
  "_id": ObjectId("..."),
  "id": 456,
  "type": "subCategory",
  "parent_id": 123,
  "title": "Pets",
  "featurePrice": 7.00,
  "listingTypes": {
    "Sale": true,
    "Wanted": true,
    "Rent": false,
    "Service": false
  },
  "pricingType": "regular",
  "priceDropThreshold": {
    "type": "percentage",
    "value": 5
  },
  "specifications": [
    {
      "fieldname": "specSubCatString1",
      "label": "Type",
      "slug": "type",
      "status": "Active",
      "inputType": "select",
      "weight": 1,
      "isRequired": true,
      "inputConfig": {
        "values": [
          {"label": "Dog", "value": "dog", "weight": 1},
          {"label": "Cat", "value": "cat", "weight": 2},
          {"label": "Bird", "value": "bird", "weight": 3},
          {"label": "Fish", "value": "fish", "weight": 4},
          {"label": "Other", "value": "other", "weight": 5}
        ],
        "sort": "weight"
      }
    },
    {
      "fieldname": "specSubCatString2",
      "label": "Breed",
      "slug": "breed",
      "status": "Active",
      "inputType": "select",
      "weight": 2,
      "isRequired": false,
      "inputConfig": {
        "values": [
          {"label": "Golden Retriever", "value": "golden-retriever", "weight": 1},
          {"label": "Labrador", "value": "labrador", "weight": 2},
          {"label": "German Shepherd", "value": "german-shepherd", "weight": 3},
          // ... more breeds
        ],
        "sort": "alpha"
      }
    },
    {
      "fieldname": "specSubCatInt1",
      "label": "Age (weeks)",
      "slug": "age-weeks",
      "status": "Active",
      "inputType": "rangeInt",
      "weight": 3,
      "isRequired": false,
      "inputConfig": {
        "min": 0,
        "max": 520,  // 10 years
        "unit": "weeks"
      }
    }
  ],
  "metaPageTitle": "Pets for Sale | Dogs, Cats, Birds & More | KSL Classifieds",
  "metaDescription": "Find pets for sale in Utah. Browse dogs, cats, birds, fish, and other animals. Connect with local pet owners and breeders."
}
```

### Example: Listing with Specifications

```jsx
{
  "_id": ObjectId("..."),
  "id": 789,
  "category": "Community",
  "subCategory": "Pets",
  "title": "Golden Retriever Puppies - AKC Registered",
  "description": "Beautiful golden retriever puppies...",
  "price": 800,
  "photos": [...],
  "memberId": 12345,
  "displayTime": ISODate("2024-01-15T10:00:00Z"),
  "status": "Active",
  
  // Specification values (raw fieldnames)
  "specSubCatString1": "dog",
  "specSubCatString2": "golden-retriever",
  "specSubCatInt1_min": 8,
  "specSubCatInt1_max": 12,
  
  // Standard fields
  "location": {...},
  "seller": {...}
}
```

# Jobs to Specifications Migration Considerations

**Key Challenge:** Jobs has 38 categories with no subcategories, while the classifieds specification system is designed for category → subcategory hierarchies with specs defined at the subcategory level.

**Analyzed Repositories:**
- `m-ksl-jobs` - Current jobs system with hard-coded field options
- `m-ksl-classifieds-api` - Source of truth for specifications system

---

## 1. Current Jobs Field Structure

### 1.1 Current Hard-Coded Fields That Should Become Specifications

From `site/application/libs/BaseOptions/BaseOptions.php`:

| Field | Type | Options | Currently Used For |
| --- | --- | --- | --- |
| `employerStatus` | Select (single) | 7 options (Full-time, Part-time, Contract, Temporary, Seasonal, Internships, Weekend Only) | Job type - Required field |
| `educationLevel` | Select (single) | 5 options (None, Advanced Degree, 4-year Degree, 2-year Degree, High School) | Minimum education required - Searchable facet |
| `yearsOfExperience` | Select (single) | 6 options (None, 1-2 years, 3-4 years, 5-7 years, 8-10 years, >10 years) | Minimum experience required - Searchable facet |
| `companyPerks` | Multi-select | 12+ options (Work remote, Dog-friendly, Catering, etc.) | Benefits/perks offered - Searchable facet |
| `payRangeType` | Select (single) | 2 options (hourly, salary) | Pay structure selector |
| `salaryFrom` / `salaryTo` | Integer range | 0 - unlimited | Salary range in dollars |
| `hourlyFrom` / `hourlyTo` | Integer range | 0 - unlimited | Hourly wage range in dollars |

### 1.2 Fields That Should Remain Standard (Not Specifications)

These fields are core to the listing entity and should NOT become specifications:

- **Identity:** `id`, `memberId`, `category`
- **Content:** `jobTitle`, `companyName`, `description`, `qualifications`, `responsibilities`, `requirements`
- **Contact:** `contactName`, `contactEmail`, `contactPhone`, `displayPhone`, `displayEmail`, `applicationUrl`
- **Location:** `city`, `state`, `zip`, `lat`, `lon`
- **Dates/Status:** `createTime`, `displayTime`, `expireTime`, `status`, `paid`
- **Media:** `photo`
- **Internal:** Billing fields, abuse tracking, feed data, etc.

### 1.3 Current Category Structure

Jobs has **38 categories** with **NO subcategories:**

```php
const CATEGORY_DATA = [
    '1' => 'Accounting & Finance',
    '6' => 'Administrative',
    '11' => 'Architecture & Engineering',
    '27' => 'Automotive',
    '21' => 'Biotech & Science',
    '5' => 'Business & Management',
    '29' => 'Child Care & Elder Care',
    '19' => 'Civic',
    '7' => 'Construction & Skilled Trades',
    '28' => 'Cosmetology & Beauty',
    '8' => 'Customer Service',
    '3' => 'Design & Creative',
    '10' => 'Education & Training',
    '37' => 'Government & Military',
    '16' => 'Healthcare',
    '12' => 'Hospitality & Travel',
    '38' => 'Human Resources',
    '14' => 'Information Technology',
    '39' => 'Insurance',
    '30' => 'Janitorial & Housekeeping',
    '22' => 'Law Enforcement & Security',
    '15' => 'Legal',
    '17' => 'Manufacturing, Mechanical & Operations',
    '2' => 'Marketing, Advertising & PR',
    '40' => 'Non-Profit & Volunteering',
    '32' => 'Nursing',
    '36' => 'Pharmaceutical',
    '33' => 'Real Estate',
    '43' => 'Restaurant & Food Service',
    '41' => 'Retail',
    '20' => 'Sales',
    '23' => 'Software Development',
    '35' => 'Sports & Media',
    '42' => 'Telecommunications',
    '24' => 'Transportation & Logistics',
    '45' => 'UI/UX & Web Designer',
    '26' => 'Veterinary Services',
    '44' => 'Warehouse & Distribution',
    '9' => 'Writing & Editorial',
    '18' => 'Other'
];
```

**Key Observation:** All job categories share the same set of filterable attributes (job type, education, experience, perks, pay). Unlike classifieds where each subcategory has unique specs (e.g., “Breed” for Pets, “Make/Model” for Vehicles), Jobs specifications are universal across all categories.

---

## 2. Migration Strategy Options

**Approach:** Convert job categories to subcategories, duplicate all common specifications in each.

**How It Works:**
1. Create a single “Jobs” parent category
2. Convert current 38 job categories into subcategories
3. Each subcategory gets an identical copy of the 7 common specifications

---

## 3. Jobs-Specific Specification Definitions

### 3.1 Proposed Category-Level Specifications (Jobs Category)

All specifications defined at category level, automatically apply to all 38 job subcategories.

### Specification 1: Job Type (REQUIRED)

```jsx
{
  fieldname: "specCatString1",
  label: "Job Type",
  slug: "job-type",
  status: "Active",
  inputType: "select",
  weight: 1,
  isRequired: true,
  appliesTo: "all",
  inputConfig: {
    values: [
      {label: "Full-time", value: "ft", weight: 1},
      {label: "Part-time", value: "pt", weight: 2},
      {label: "Contract", value: "ct", weight: 3},
      {label: "Temporary", value: "temp", weight: 4},
      {label: "Seasonal", value: "sj", weight: 5},
      {label: "Internships", value: "inter", weight: 6},
      {label: "Weekend Only", value: "week", weight: 7}
    ],
    sort: "weight"
  }
}
```

**Migration Notes:**
- Maps to current `employerStatus` field
- Currently required field in Jobs
- Used as primary search filter

### Specification 2: Education Level

```jsx
{
  fieldname: "specCatString2",
  label: "Education Level",
  slug: "education-level",
  status: "Active",
  inputType: "select",
  weight: 2,
  isRequired: false,
  appliesTo: "all",
  inputConfig: {
    values: [
      {label: "Advanced Degree", value: "0", weight: 1},
      {label: "4-year Degree", value: "1", weight: 2},
      {label: "2-year Degree", value: "2", weight: 3},
      {label: "High School", value: "3", weight: 4},
      {label: "None", value: "4", weight: 5}
    ],
    sort: "weight"
  }
}
```

**Migration Notes:**
- Maps to current `educationLevel` field
- Optional but commonly used
- Heavy search facet

### Specification 3: Years of Experience

```jsx
{
  fieldname: "specCatString3",
  label: "Years of Experience",
  slug: "years-of-experience",
  status: "Active",
  inputType: "select",
  weight: 3,
  isRequired: false,
  appliesTo: "all",
  inputConfig: {
    values: [
      {label: "None", value: "5", weight: 1},
      {label: "1-2 years", value: "0", weight: 2},
      {label: "3-4 years", value: "4", weight: 3},
      {label: "5-7 years", value: "1", weight: 4},
      {label: "8-10 years", value: "2", weight: 5},
      {label: ">10 years", value: "3", weight: 6}
    ],
    sort: "weight"
  }
}
```

**Migration Notes:**
- Maps to current `yearsOfExperience` field
- Optional
- Heavy search facet

### Specification 4: Pay Range Type

```jsx
{
  fieldname: "specCatString4",
  label: "Pay Type",
  slug: "pay-type",
  status: "Active",
  inputType: "select",
  weight: 4,
  isRequired: false,
  appliesTo: "all",
  inputConfig: {
    values: [
      {label: "Hourly", value: "hourly", weight: 1},
      {label: "Salary", value: "salary", weight: 2}
    ],
    sort: "weight"
  }
}
```

**Migration Notes:**
- Maps to current `payRangeType` field
- Determines which pay range fields to show (hourly vs salary)
- Consider making this a radio button in UI

### Specification 5: Salary Range

```jsx
{
  fieldname: "specCatInt1",
  label: "Salary Range (Annual)",
  slug: "salary-range",
  status: "Active",
  inputType: "rangeInt",
  weight: 5,
  isRequired: false,
  appliesTo: "all",
  inputConfig: {
    min: 0,
    max: 1000000,
    unit: "USD",
    openEndedMin: false,
    openEndedMax: true
  }
}
```

**Migration Notes:**
- Maps to current `salaryFrom` and `salaryTo` fields
- Stored as `specCatInt1_min` and `specCatInt1_max`
- Consider adding validation: only required if payRangeType = “salary”

### Specification 6: Hourly Rate Range

```jsx
{
  fieldname: "specCatInt2",
  label: "Hourly Rate",
  slug: "hourly-rate",
  status: "Active",
  inputType: "rangeInt",
  weight: 6,
  isRequired: false,
  appliesTo: "all",
  inputConfig: {
    min: 0,
    max: 500,
    unit: "USD/hour",
    openEndedMin: false,
    openEndedMax: true
  }
}
```

**Migration Notes:**
- Maps to current `hourlyFrom` and `hourlyTo` fields
- Stored as `specCatInt2_min` and `specCatInt2_max`
- Consider adding validation: only required if payRangeType = “hourly”

### Specification 7: Company Perks (Multi-Select)

**Challenge:** Current specification system only supports single-select dropdowns. `companyPerks` is a multi-select array.

**Option 7B: Keep as Standard Field (RECOMMENDED)**

Keep `companyPerks` as a standard array field, NOT a specification. Reasons:
- Multi-select support would require extending specification system further
- Perks are more like “features” or “tags” than structured specifications
- Already works well as an array field in MongoDB/Elasticsearch
- Saves specification slots for future needs

**Recommendation:** Keep `companyPerks` as standard field for now. Consider adding multi-select support to specifications in a future phase.

**Examples:**
- Healthcare: License Type, Certifications
- IT: Programming Languages, Technologies
- Transportation: CDL Class, Endorsements
- Real Estate: License State

## 4. Migration Checklist

**Backend:**
- [ ] Add new database fields (`specCatString*`, `specCatInt*`, `specCatFloat*`)
- [ ] Update MongoDB schema and add fields to generalCategory collection
- [ ] Implement validation logic for category specifications

**Database:**
- [ ] Add new fields to MongoDB general collection
- [ ] Update Elasticsearch mapping with new fields

**Jobs Category Setup:**
- [ ] Create “Jobs” parent category in production
- [ ] Convert 38 job categories to subcategories under “Jobs”
- [ ] Define 6 category-level specifications for each subcategory in Jobs
- [ ] Publish to production

**marketplace-graphql:**
- [ ] Update `SpecificationsClient` to support jobs specifications if needed
- [ ] Update `GeneralListing` struct with new fields

**Sell Form:**
- [ ] Leverage Classifieds sell form
- [ ] Dynamically render specification fields

**Search/Filter:**
- [ ] Update search page to use specification-based filters

**Detail Page:**
- [ ] Display specification values instead of old field values
- [ ] Format salary/hourly ranges properly
- [ ] Show job type, education, experience from specs