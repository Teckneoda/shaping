# Saved Search & Alerts

## Table of Contents

- [Summary](#summary)
    - [Updates In General To Support Having Job Listings In General](#updates-in-general-to-support-having-job-listings-in-general)
    - [Migration](#migration)
- [Original Discovery](#original-discovery)
    - [Executive Summary](#executive-summary)
        - [Current State](#current-state)
        - [Key Findings](#key-findings)
        - [Architecture Overview](#architecture-overview)
        - [System Architecture Diagram](#system-architecture-diagram)
    - [Repository Comparison Matrix](#repository-comparison-matrix)
    - [CAPI Deep Dive](#capi-deep-dive)
        - [Overview](#overview)
        - [CAPI Architecture](#capi-architecture)
        - [REST Endpoints](#rest-endpoints)
        - [Data Flow: Create Saved Search](#data-flow-create-saved-search)
        - [Key Business Logic](#key-business-logic)
        - [KSL API Integration](#ksl-api-integration)
        - [MongoDB Direct Read](#mongodb-direct-read)
        - [Homepage Integration](#homepage-integration)
    - [Data Flow Analysis](#data-flow-analysis)
        - [Creating a Saved Search](#creating-a-saved-search)
        - [Fetching Saved Searches](#fetching-saved-searches)
        - [My Account Management Flow](#my-account-management-flow)
        - [Classifieds Frontend Flow](#classifieds-frontend-flow)
    - [API Endpoints Mapping](#api-endpoints-mapping)
    - [Feature Comparison](#feature-comparison)
    - [Technology Stack Comparison](#technology-stack-comparison)
    - [My Account Integration](#my-account-integration)
    - [Migration Considerations](#migration-considerations)
    - [Appendix: Code References](#appendix-code-references)
    - [UI](#ui)
        - [Jobs](#jobs)
        - [Classifieds](#classifieds)

# Summary

## Updates In General To Support Having Job Listings In General

The underlying ability to save a search for listings in General is built out.  There looks to be some [searchable fields](https://www.notion.so/Jobs-Listing-Fields-For-Moving-Into-General-Classifieds-2bd2ac5cb2358085a57ada835369a06f?pvs=21) that will need to be added to General’s SRP that will need to be added to General’s Saved Searches.

- Update Saved Search creation / editing / viewing to have the new searchable fields (viewing and saving the values to the saved search).
- Update the Saved Search processor to use those fields when looking at newly activated listings to see if they match.

## Migration

The following is if business decides to try to duplicate the user’s Job Saved Searches in General Classifieds.

We could go through the all the existing Saved Searches in Jobs.  For each one do the following:

- Parse the existing Saved Search to see what we have.
- Map fields / values from Jobs to General Classifieds specs.
- Save the updated Saved Search into General.

For a time between when the duplicated Saved Searches are created in General and Jobs is shut down, the user may get more notifications then what they were expecting.

# Original Discovery

**Repositories Analyzed**:
- `marketplace-graphql` (Go GraphQL aggregation layer)
- `m-ksl-classifieds-api` (PHP/Symfony Classifieds REST API - CAPI)
- `m-ksl-jobs` (PHP Jobs backend)
- `m-ksl-myaccount` (PHP My Account frontend)

---

## Executive Summary

### Current State

The saved search functionality is distributed across four repositories with different architectures:

| Repository | Role | Tech Stack | Data Ownership |
| --- | --- | --- | --- |
| **marketplace-graphql** | Aggregation layer | Go/gqlgen | None (calls REST APIs) |
| **m-ksl-classifieds-api (CAPI)** | Classifieds REST API | PHP/Symfony | Partial (reads MongoDB, writes via KSL API) |
| **m-ksl-jobs** | Jobs backend | PHP/MongoDB | Full (owns `jobsSavedSearch` collection) |
| **m-ksl-myaccount** | User management UI | PHP/React | None (calls backend APIs) |

### Key Findings

1. **marketplace-graphql** acts as a thin aggregation layer that calls backend REST APIs (KSL API, CAPI) but does NOT implement saved search mutations for Jobs
2. **m-ksl-classifieds-api (CAPI)** is the Classifieds REST API that provides create/update endpoints for Classifieds saved searches. It proxies to KSL API for persistence but can read directly from MongoDB for listing retrieval
3. **m-ksl-jobs** has a complete, self-contained saved search implementation with direct MongoDB access
4. **m-ksl-myaccount** provides the user-facing management UI for all verticals, proxying to appropriate backends
5. There is **no unified backend** - each vertical (Cars, Classifieds, Jobs, Homes) has separate implementations

### Architecture Overview

---

### System Architecture Diagram

```mermaid
flowchart TB
    subgraph Frontend["Frontend Applications"]
        MF["marketplace-frontend<br/>(Next.js)<br/>• Save Search Modal<br/>• Homepage Module<br/>• Low-Volume Prompt"]
        MCLS["m-ksl-classifieds<br/>(PHP + React)<br/>• Classifieds SRP<br/>• Save Search"]
        MA["m-ksl-myaccount<br/>(PHP + React)<br/>• Manage Searches<br/>• Edit/Delete<br/>• View Alerts"]
        MJ["m-ksl-jobs<br/>(PHP + React)<br/>• Jobs SRP<br/>• Save Search"]
    end

    subgraph GraphQL["GraphQL/API Layer"]
        MG["marketplace-graphql (Go)<br/><br/>Queries:<br/>• fetchSavedSearchAlertCounts<br/>• fetchSavedSearchesListings<br/><br/>Mutations:<br/>• saveSavedSearch (CAR, CLS)<br/>• NOT implemented for JOBS"]
        JG["m-ksl-jobs GraphQL (PHP)<br/><br/>Queries:<br/>• savedSearches<br/>• matchedAlerts<br/><br/>Mutations:<br/>• savedSearchSave<br/>• savedSearchDelete"]
    end

    subgraph REST["Backend REST APIs"]
        KSL["KSL API (PHP)<br/>• Cars saved search<br/>• Common endpoints<br/>• General endpoints"]
        CAPI["CAPI (m-ksl-classifieds-api)<br/>(PHP/Symfony)<br/>• POST /saved-searches/<br/>• PUT /saved-searches/{id}<br/>• GET /homepage/saved-search/{id}/listings"]
        HOMES["Homes API<br/>• Homes saved search"]
        MYACC_API["My Account API<br/>• GET /api/v1/saved-search<br/>• GET /api/v1/saved-search/{id}/alerts"]
    end

    subgraph Storage["Data Storage"]
        MONGO_JOBS["MongoDB (Jobs)<br/>• jobsSavedSearch<br/>• jobsMatchedAlerts<br/>• idTracker"]
        MONGO_CLS["MongoDB (Classifieds)<br/>• generalSavedSearch<br/>• generalMatchedAlerts"]
        MONGO_CARS["MongoDB (Cars)<br/>• carsSavedSearch<br/>• matchedAlerts"]
        ES["Elasticsearch<br/>• general (index)<br/>• cars (index)"]
    end

    MF --> MG
    MCLS --> CAPI
    MA --> MG
    MA --> CAPI
    MA --> JG
    MJ --> JG

    MG --> KSL
    MG --> CAPI
    MG --> HOMES
    JG --> MONGO_JOBS

    CAPI --> KSL
    CAPI --> MONGO_CLS
    CAPI --> ES
    CAPI --> MYACC_API
    KSL --> MONGO_CLS
    KSL --> MONGO_CARS
    HOMES --> MONGO_CARS
```

---

## Repository Comparison Matrix

### marketplace-graphql (Go)

| Aspect | Implementation |
| --- | --- |
| **Language** | Go |
| **Framework** | gqlgen (99designs) |
| **Role** | Aggregation/coordination layer |
| **Data Access** | REST APIs only (KSL API, CAPI) |
| **Supported Verticals** | CAR, CLASSIFIED (mutations); All 6 (queries) |
| **Authentication** | JWT via `access_token_cookie` |
| **Concurrency** | Goroutines, channels, worker pools |

**Key Files**:
- `graph/queryresolvers/saved-search.go` - Fetch alert counts
- `graph/queryresolvers/legacy-listing.go` - Fetch saved searches with listings
- `graph/mutationresolvers/legacy-savedsearch.go` - Save/update mutations
- `services/kslapi/legacy_saved_search.go` - KSL API client

### m-ksl-classifieds-api (CAPI - PHP/Symfony)

| Aspect | Implementation |
| --- | --- |
| **Language** | PHP |
| **Framework** | Symfony |
| **Role** | Classifieds REST API |
| **Data Access** | KSL API (writes), MongoDB (reads), Elasticsearch (search) |
| **Supported Verticals** | CLASSIFIED (general) only |
| **Authentication** | Nonce-based (NonceAuthenticatedInterface) + JWT |
| **Validation** | Excessive search check (25,000 listings max for immediate alerts) |

**Key Files**:
- `src/Controller/SavedSearchController.php` - REST endpoints
- `src/Controller/HomepageController.php` - Homepage saved search listings
- `src/Helper/SavedSearchHelper.php` - Business logic
- `src/Db/Mongo/GeneralSavedSearchCollection.php` - MongoDB reader
- `src/Library/KSL/KslApiClient.php` - KSL API client
- `src/Library/MyAccount/MyAccountApiClient.php` - My Account API client

### m-ksl-jobs (PHP)

| Aspect | Implementation |
| --- | --- |
| **Language** | PHP |
| **Framework** | webonyx/graphql-php |
| **Role** | Full backend with data ownership |
| **Data Access** | Direct MongoDB |
| **Supported Verticals** | JOB only |
| **Authentication** | Session-based (`memberCache`) |
| **Events** | GCP Pub/Sub |

**Key Files**:
- `site-api/namespaces/APIGraphQL/FieldObject/SavedSearchesFieldObject.php` - Query
- `site-api/namespaces/APIGraphQL/FieldObject/SavedSearchSaveFieldObject.php` - Mutation
- `site-api/namespaces/APIGraphQL/FieldObject/SavedSearchDeleteFieldObject.php` - Delete
- `site-api/namespaces/APIGraphQL/FieldObject/MatchedAlertsFieldObject.php` - Alerts
- `site-api/namespaces/APIGraphQL/Type/SavedSearchType.php` - Type definition

### m-ksl-myaccount (PHP + React)

| Aspect | Implementation |
| --- | --- |
| **Language** | PHP (controllers) + React (frontend) |
| **Framework** | Zend Framework 1 |
| **Role** | User management UI |
| **Data Access** | Proxies to backend APIs |
| **Supported Verticals** | ALL (Car, Classified, Job, Home) |
| **Authentication** | Session-based |

**Key Files**:
- `application/controllers/SavedSearchesController.php` - Router
- `application/controllers/SavedSearchesCarController.php` - Cars management
- `application/controllers/SavedSearchesJobController.php` - Jobs management
- `application/controllers/SavedSearchesClassifiedController.php` - Classifieds management
- `library/JobsGraphQLProxy.php` - Jobs GraphQL proxy
- `public/aux/assets/src/SavedSearches/` - React components

---

## CAPI Deep Dive

### Overview

CAPI (`m-ksl-classifieds-api`) is the Classifieds REST API built with Symfony. It serves as an intermediary layer for Classifieds saved search operations, providing REST endpoints that:

1. **Create/Update**: Proxy to KSL API for persistence
2. **Read**: Query MongoDB directly for saved search data
3. **Search**: Use Elasticsearch for listing retrieval
4. **Validate**: Enforce business rules (e.g., excessive search check)

### CAPI Architecture

```mermaid
flowchart TB
    subgraph Clients["Clients"]
        MF["marketplace-frontend"]
        MCLS["m-ksl-classifieds"]
        MG["marketplace-graphql"]
    end

    subgraph CAPI["CAPI (m-ksl-classifieds-api)"]
        CTRL["SavedSearchController"]
        HP["HomepageController"]
        SSH["SavedSearchHelper"]
        HH["HomepageHelper"]
        KSLC["KslApiClient"]
        MAC["MyAccountApiClient"]
        GSC["GeneralSavedSearchCollection"]
    end

    subgraph External["External Services"]
        KSL["KSL API (PHP)"]
        MYACC["My Account API"]
        ES["Elasticsearch"]
        MONGO["MongoDB<br/>generalSavedSearch"]
    end

    MF & MCLS & MG --> CTRL & HP
    CTRL --> SSH
    HP --> HH
    SSH --> KSLC
    SSH --> GSC
    SSH --> ES
    HH --> SSH
    HH --> MAC
    HP --> MAC
    KSLC --> KSL
    MAC --> MYACC
    GSC --> MONGO
    KSL --> MONGO
```

### REST Endpoints

| Endpoint | Method | Controller | Description |
| --- | --- | --- | --- |
| `/saved-searches/` | POST | `SavedSearchController::createSavedSearch` | Create new saved search |
| `/saved-searches/{id}` | PUT | `SavedSearchController::updateSavedSearch` | Update existing saved search |
| `/homepage/saved-search/{id}/listings` | GET | `HomepageController::getSavedSearchListings` | Get listings for homepage carousel |
| `/homepage/get-meta-data` | GET | `HomepageController::getMetaData` | Get homepage data including saved searches |

### Data Flow: Create Saved Search

```mermaid
sequenceDiagram
    participant Client
    participant CAPI as CAPI<br/>SavedSearchController
    participant Helper as SavedSearchHelper
    participant KSL as KSL API
    participant Mongo as MongoDB

    Client->>CAPI: POST /saved-searches/<br/>{memberId, searchName, searchParams, deliveryMethods}
    CAPI->>CAPI: authCheck (validate JWT)
    CAPI->>Helper: createSavedSearch(params)
    Helper->>Helper: parameterCheck (validate required fields)
    Helper->>KSL: getMemberData(memberId)
    KSL-->>Helper: {id, persistent}

    alt Has Immediate Alert
        Helper->>Helper: excessiveSavedSearchCheck()
        Helper->>Helper: getAlertSearchCount() via Elasticsearch
        Note over Helper: Reject if > 25,000 listings
    end

    Helper->>KSL: addSavedSearch({member_id, persistent, searchName, searchParams, vertical: 'general'})
    KSL->>Mongo: Insert into generalSavedSearch
    Mongo-->>KSL: {id}
    KSL-->>Helper: {id}

    alt Has deliveryMethods
        Helper->>KSL: setAlert({savedSearchId, deliveryMethods})
        KSL-->>Helper: success
    end

    Helper-->>CAPI: {id, updateAlertResponse}
    CAPI-->>Client: {data: {}, meta: {savedSearchCreated: true, savedSearchId, ...}}
```

### Key Business Logic

### Excessive Search Check

CAPI enforces a limit of **25,000 listings** for immediate alerts to prevent system overload:

```php
// SavedSearchHelper.phppublic const MAX_LISTING_FOR_IMMEDIATE_ALERT = 25000;public function excessiveSavedSearchCheck(array $searchParams, array $deliveryMethods): bool{
    // Check if email OR push has 'immediately' frequency    if (
        ($deliveryMethods['email']['active'] && $deliveryMethods['email']['frequency'] === 'immediately')
        || ($deliveryMethods['push']['active'] && $deliveryMethods['push']['frequency'] === 'immediately')
    ) {
        $alertSearchCount = $this->getAlertSearchCount($searchParams);        if ($alertSearchCount >= self::MAX_LISTING_FOR_IMMEDIATE_ALERT) {
            return true; // Too broad        }
    }
    return false;}
```

### KSL API Integration

CAPI delegates persistence to KSL API using three endpoints:

| KSL API Endpoint | Purpose |
| --- | --- |
| `classifieds/general/savedSearchesGeneral/addSavedSearch` | Create saved search |
| `classifieds/general/savedSearchesGeneral/updateSavedSearch` | Update saved search |
| `classifieds/general/savedSearchesGeneral/setAlert` | Configure alert delivery |

### MongoDB Direct Read

For performance, CAPI reads saved search data directly from MongoDB rather than through KSL API:

```php
// GeneralSavedSearchCollection.phppublic function getSavedSearch(int $savedSearchId, int $memberId = null): ?array{
    $queryParams = ['id' => $savedSearchId];    if (!empty($memberId)) {
        $queryParams['memberId'] = $memberId;    }
    return $this->generalSavedSearch->findOne($queryParams);}
```

### Homepage Integration

CAPI provides saved search data for the homepage carousel feature:

1. **`getMetaData`**: Fetches user’s saved searches from My Account API
2. **`getSavedSearchListings`**: Returns listings matching a saved search criteria

```mermaid
sequenceDiagram
    participant Frontend
    participant CAPI as CAPI<br/>HomepageController
    participant MyAcc as My Account API
    participant Helper as SavedSearchHelper
    participant ES as Elasticsearch

    Frontend->>CAPI: GET /homepage/get-meta-data
    CAPI->>MyAcc: GET /api/v1/saved-search?vertical=Classifieds
    MyAcc-->>CAPI: [{id, searchName}, ...]
    CAPI-->>Frontend: {savedSearches, customization, ...}

    Frontend->>CAPI: GET /homepage/saved-search/{id}/listings?memberId=X
    CAPI->>Helper: getSavedSearchListings(savedSearchId, memberId)
    Helper->>Helper: getSavedSearch from MongoDB
    Helper->>ES: Search with saved criteria
    ES-->>Helper: [listing1, listing2, ...]
    Helper-->>CAPI: listings array
    CAPI-->>Frontend: {data: [listings]}
```

---

## Data Flow Analysis

### Creating a Saved Search

### Flow 1: Cars/Classifieds (via marketplace-graphql)

```mermaid
flowchart TD
    A["Frontend (marketplace-frontend)"] --> B["GraphQL Mutation: saveSavedSearch"]
    B --> C{listingType?}

    C -->|CAR| D["KSL API (PHP)<br/>POST /classifieds/cars/<br/>savedSearches/createSavedSearch"]
    D --> E[("MongoDB<br/>carsSavedSearch")]

    C -->|CLASSIFIED| F["CAPI (PHP/Symfony)<br/>POST /saved-searches/"]
    F --> G["KSL API (PHP)<br/>POST /classifieds/general/<br/>savedSearchesGeneral/addSavedSearch"]
    G --> H[("MongoDB<br/>generalSavedSearch")]
```

### Flow 1a: Classifieds (via CAPI directly)

```mermaid
flowchart TD
    A["Frontend (m-ksl-classifieds)"] --> B["CAPI<br/>POST /saved-searches/"]
    B --> C["SavedSearchHelper<br/>• parameterCheck<br/>• excessiveSavedSearchCheck"]
    C --> D["KSL API (PHP)<br/>addSavedSearch"]
    D --> E[("MongoDB<br/>generalSavedSearch")]
    C --> F["KSL API (PHP)<br/>setAlert"]
    F --> E
```

### Flow 2: Jobs (via m-ksl-jobs GraphQL)

```mermaid
flowchart TD
    A["Frontend (m-ksl-jobs or m-ksl-myaccount)"] --> B["GraphQL Mutation: savedSearchSave"]
    B --> C["m-ksl-jobs PHP GraphQL"]
    C --> D["Validates member session"]
    D --> E["Validates max 100 saved searches"]
    E --> F["Generates ID from idTracker collection"]
    F --> G["Denormalizes criteria_* fields"]
    G --> H[("MongoDB: jobsSavedSearch.updateOne() (upsert)")]
    H --> I["GCP Pub/Sub: publishJobSavedSearch (event)"]
```

### Fetching Saved Searches

### Flow 1: Alert Counts (marketplace-graphql)

```mermaid
flowchart TD
    A["Frontend"] --> B["GraphQL Query: fetchSavedSearchAlertCounts"]
    B --> C["marketplace-graphql (Go)"]
    C --> D["Spawns 6 goroutines (one per vertical)"]

    D --> E1["CAR"]
    D --> E2["CLASSIFIED"]
    D --> E3["JOB"]
    D --> E4["HOME_BUY"]
    D --> E5["HOME_RENT"]
    D --> E6["HOME_COMMUNITY"]

    E1 & E2 & E3 & E4 & E5 & E6 --> F["KSL API: GET /classifieds/common/<br/>savedSearches/getSavedSearchesForUser"]
    F --> G["Response: VerticalSavedSearch[]"]
```

### Flow 2: Jobs with Matched Alerts (m-ksl-jobs)

```mermaid
flowchart TD
    A["Frontend (m-ksl-myaccount)"] --> B["GraphQL Query: savedSearches"]
    B --> C["m-ksl-jobs PHP GraphQL"]
    C --> D[("Query jobsSavedSearch collection")]
    C --> E{unreadAlertCount<br/>requested?}
    E -->|Yes| F[("MongoDB Aggregation on jobsMatchedAlerts<br/>[$match, $group by savedSearchId, $sum count]")]
    E -->|No| G["Return saved searches"]
    F --> G
```

### My Account Management Flow

```mermaid
flowchart TD
    A["m-ksl-myaccount Frontend (React)"] --> B{Vertical?}

    B -->|Cars| C["SavedSearchesCarController.php<br/>POST /myaccount/saved-searches-car/*"]
    C --> D["KSL API<br/>(common savedSearches endpoints)"]

    B -->|Classifieds| E["SavedSearchesClassifiedController.php<br/>POST /myaccount/saved-searches-classified/*"]
    E --> F["KSL API<br/>(general savedSearchesGeneral endpoints)"]

    B -->|Jobs| G["SavedSearchesJobController.php<br/>POST /myaccount/saved-searches-job/proxy"]
    G --> H["JobsGraphQLProxy"]
    H --> I["m-ksl-jobs GraphQL"]
```

### Classifieds Frontend Flow (m-ksl-classifieds)

```mermaid
flowchart TD
    A["m-ksl-classifieds Frontend (React)"] --> B["Save Search Modal"]
    B --> C["CAPI<br/>POST /saved-searches/"]
    C --> D["SavedSearchHelper"]
    D --> E["KSL API<br/>addSavedSearch + setAlert"]
    E --> F[("MongoDB<br/>generalSavedSearch")]
```

---

## API Endpoints Mapping

### KSL API (Common - Used by Cars)

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/classifieds/common/savedSearches/getSavedSearchesForUser` | GET | Fetch user’s saved searches |
| `/classifieds/common/savedSearches/getAlertsForSavedSearch` | GET | Fetch alerts for a search |
| `/classifieds/common/savedSearches/addSavedSearch` | POST | Create saved search |
| `/classifieds/common/savedSearches/updateSavedSearch` | POST | Update saved search |
| `/classifieds/common/savedSearches/removeSavedSearch` | POST | Delete saved search |
| `/classifieds/common/savedSearches/setAlert` | POST | Enable/configure alert |
| `/classifieds/common/savedSearches/setAllAlertsViewed` | POST | Mark alerts as viewed |
| `/classifieds/common/savedSearches/removeAlert` | POST | Remove single alert |
| `/classifieds/common/savedSearches/batchUpdateViewedAlerts` | POST | Batch mark viewed |

### KSL API (Cars-specific)

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/classifieds/cars/savedSearches/createSavedSearch` | POST | Create car saved search |
| `/classifieds/cars/savedSearches/updateSavedSearch` | POST | Update car saved search |

### CAPI (Classifieds - m-ksl-classifieds-api)

| Endpoint | Method | Purpose | Backend |
| --- | --- | --- | --- |
| `/saved-searches/` | POST | Create saved search | KSL API |
| `/saved-searches/{id}` | PUT | Update saved search | KSL API |
| `/homepage/get-meta-data` | GET | Get homepage data incl. saved searches | My Account API |
| `/homepage/saved-search/{id}/listings` | GET | Get listings for saved search carousel | MongoDB + Elasticsearch |

**Internal KSL API Calls (made by CAPI)**:

| KSL API Endpoint | Method | Purpose |
| --- | --- | --- |
| `classifieds/general/savedSearchesGeneral/addSavedSearch` | POST | Create saved search |
| `classifieds/general/savedSearchesGeneral/updateSavedSearch` | POST | Update saved search |
| `classifieds/general/savedSearchesGeneral/setAlert` | POST | Configure alert delivery |

**Internal My Account API Calls (made by CAPI)**:

| My Account API Endpoint | Method | Purpose |
| --- | --- | --- |
| `/api/v1/saved-search` | GET | Fetch user’s saved searches |
| `/api/v1/saved-search/{id}/alerts` | GET | Fetch alerts for a saved search |

### m-ksl-jobs GraphQL

| Operation | Type | Purpose |
| --- | --- | --- |
| `savedSearches` | Query | Fetch user’s saved searches with alert counts |
| `matchedAlerts` | Query | Fetch alerts for a saved search |
| `savedSearchSave` | Mutation | Create or update saved search |
| `savedSearchDelete` | Mutation | Delete saved search |

---

## Feature Comparison

### Core Features

| Feature | marketplace-graphql | CAPI | m-ksl-jobs | m-ksl-myaccount |
| --- | --- | --- | --- | --- |
| Create Saved Search | ✅ (CAR, CLASSIFIED) | ✅ | ✅ | ✅ (proxy) |
| Update Saved Search | ✅ (CAR, CLASSIFIED) | ✅ | ✅ | ✅ (proxy) |
| Delete Saved Search | ❌ | ❌ | ✅ | ✅ (proxy) |
| Fetch Saved Searches | ✅ | ✅ (via My Account API) | ✅ | ✅ (proxy) |
| Fetch with Listings | ✅ | ✅ (homepage carousel) | ✅ | ❌ |
| Alert Counts | ✅ | ✅ (via My Account API) | ✅ (unread count) | ✅ (display) |
| Mark As Viewed | ❌ | ❌ | ✅ | ✅ (proxy) |

### Alert Configuration

| Feature | marketplace-graphql | CAPI | m-ksl-jobs | m-ksl-myaccount |
| --- | --- | --- | --- | --- |
| Email Alerts | ✅ | ✅ | ✅ | ✅ |
| Push Alerts | Schema only | ✅ | Schema only | Schema only |
| Frequency: Immediately | ✅ | ✅ | ✅ | ✅ |
| Frequency: Daily | ✅ | ✅ | ✅ | ✅ |
| Frequency: Weekly | ✅ | ✅ | ✅ | ✅ |
| Max Search Limit | ❌ | ❌ | ✅ (100) | ❌ |
| Immediate Alert Limit | ❌ | ✅ (25,000 listings) | ❌ | ✅ (1000 listings) |

### Advanced Features

| Feature | marketplace-graphql | CAPI | m-ksl-jobs | m-ksl-myaccount |
| --- | --- | --- | --- | --- |
| Pub/Sub Events | ❌ | ❌ | ✅ | ❌ |
| Translated Params | ❌ | ❌ | ✅ | ❌ |
| Denormalized Criteria | ❌ | ❌ | ✅ | ❌ |
| Category/Subcategory | N/A | ✅ | ✅ | ✅ (fetches) |
| Concurrent Fetching | ✅ (goroutines) | ❌ | ❌ | ❌ |
| Worker Pool | ✅ (10 workers) | ❌ | ❌ | ❌ |
| Elasticsearch Search | ✅ (via services) | ✅ (direct) | ❌ | ❌ |
| MongoDB Direct Read | ❌ | ✅ | ✅ | ❌ |

---

## Technology Stack Comparison

| Aspect | marketplace-graphql | CAPI | m-ksl-jobs | m-ksl-myaccount |
| --- | --- | --- | --- | --- |
| **Backend Language** | Go | PHP | PHP | PHP |
| **Framework** | gqlgen | Symfony | webonyx/graphql-php | Zend Framework 1 |
| **Frontend** | N/A (API only) | N/A (API only) | React + jQuery | React + jQuery |
| **API Type** | GraphQL | REST | GraphQL | REST (proxy) |
| **Database** | None (REST only) | MongoDB (read), KSL API (write) | MongoDB | None (API proxy) |
| **Search** | Elasticsearch (via services) | Elasticsearch (direct) | ❌ | ❌ |
| **Authentication** | JWT | Nonce + JWT | Session | Session |
| **State Management** | N/A | N/A | N/A | Flux pattern |
| **Tracing** | DataDog | ❌ | ❌ | ❌ |
| **Package Manager** | Go modules | Composer | Composer | Composer + npm |

---

## My Account Integration

### Vertical Routing

The `SavedSearchesController` routes users to vertical-specific controllers:

```php
$availableVerticalArray = ['classified', 'car', 'home', 'job'];
// Routes to:
// - /myaccount/saved-searches-classified
// - /myaccount/saved-searches-car
// - /myaccount/saved-searches-job
// - /myaccount/saved-searches-home
```

### Controller Responsibilities

| Controller | Backend API | Features |
| --- | --- | --- |
| `SavedSearchesCarController` | KSL API (common) | CRUD, alerts, options fetch |
| `SavedSearchesClassifiedController` | KSL API (general) | CRUD, alerts, immediate alert limit check |
| `SavedSearchesJobController` | m-ksl-jobs GraphQL | CRUD (via GraphQL proxy) |

### Jobs GraphQL Proxy

My Account proxies Jobs saved search operations through a PHP GraphQL proxy:

```php
class JobsGraphQLProxy {
    public static function executeQuery($config, $shouldJsonDecodeContents = true) {
        // Builds request with member session headers        // POSTs to /classifieds/jobs/graphql/index        // Returns GraphQL response    }
}
```

### React Components Structure

```mermaid
flowchart TD
    ROOT["public/aux/assets/src/SavedSearches/"]

    ROOT --> D1["savedSearchesDefaults.js"]
    ROOT --> D2["savedSearchesCar.js"]
    ROOT --> D3["savedSearchesClassified.js"]
    ROOT --> D4["savedSearchesJob.js"]

    ROOT --> CAR["Car/"]
    CAR --> CARLIST["SavedSearchesCarList/"]
    CARLIST --> CAR1["index.js"]
    CARLIST --> CAR2["store.js"]
    CARLIST --> CAR3["components/"]

    ROOT --> CLS["Classified/"]
    CLS --> CLSLIST["SavedSearchesClassifiedList/"]
    CLSLIST --> CLS1["index.js"]
    CLSLIST --> CLS2["components/"]
    CLS2 --> CLS2A["SavedSearchesClassifiedItems/"]
    CLS2 --> CLS2B["SavedSearchesClassifiedAlerts/"]
    CLS2 --> CLS2C["SaveSearchModal/"]

    ROOT --> JOB["Job/"]
    JOB --> JOBLIST["SavedSearchesJobList/"]
    JOBLIST --> JOB1["index.js"]
    JOBLIST --> JOB2["components/"]
    JOB2 --> JOB2A["SavedSearchesJobItems/"]
    JOB2 --> JOB2B["SavedSearchesAlertsJob/"]
    JOB2 --> JOB2C["SaveSearchModal/"]
```

---

## Migration Considerations

### Current Pain Points

1. **Fragmented Architecture**: Each vertical has separate backend implementations
2. **PHP Deprecation**: Jobs backend uses deprecated PHP
3. **No Unified API**: marketplace-graphql cannot create Jobs saved searches
4. **Duplicate Code**: Similar logic repeated across verticals (CAPI, KSL API, Jobs)
5. **Inconsistent Features**: Jobs has Pub/Sub, others don’t
6. **CAPI as Middleman**: For Classifieds, CAPI acts as unnecessary intermediary that just proxies to KSL API
7. **Mixed Data Access Patterns**: CAPI reads from MongoDB directly but writes via KSL API, creating potential consistency issues

---

## Appendix: Code References

### marketplace-graphql Key Types

```go
// Query response types
type SavedSearchAlertCountResponse struct {    
	VerticalSavedSearches []*VerticalSavedSearch
}
type VerticalSavedSearch struct {    
	Vertical      ListingType
  SavedSearches []*SavedSearch
}
type SavedSearch struct {
  ID               int    
  SearchName       *string    
  SearchParams     *string  // JSON string    
  AlertCount       *int    
  AlertViewedCount *int
}

// Mutation input types
type SavedSearchDeliveryMethods struct {    
	Email *SavedSearchDeliveryProperties
  Push  *SavedSearchDeliveryProperties
}
type SavedSearchDeliveryProperties struct {    
	Active    *bool    
	Frequency *SavedSearchFrequencyType  // immediately, daily, weekly
}
```

### m-ksl-jobs Key Types

```php
// SavedSearch document structure
[
    'id' => int,
    'memberId' => int,    
    'searchName' => string,    
    'searchParams' => string,  // JSON    
    'alert' => bool,    
    'deliveryMethods' => [
        'email' => ['active' => bool, 'frequency' => string],
        'push' => ['active' => bool, 'frequency' => string]
    ],    
    'criteria_category' => array,  // Denormalized    
    'criteria_city' => string,    
    'criteria_*' => mixed,    
    'createTime' => UTCDateTime,    
    'modifyTime' => UTCDateTime
]

// MatchedAlert document structure
[
    '_id' => ObjectId,    
    'savedSearchId' => int,    
    'memberId' => int,    
    'searchName' => string,    
    'listingId' => int,    
    'listingCreateTime' => UTCDateTime,    
    'alertCreateTime' => UTCDateTime,    
    'viewed' => bool
]
```

### CAPI Key Types (PHP)

```php
// Create/Update Saved Search Request Body
[
    'memberId' => int,       // Required: Owner of saved search    
    'searchName' => string,  // Required: Title of saved search    
    'searchParams' => [      // Required: Search criteria        
		    'keyword' => string,        
		    'category' => string|array,        
		    'subCategory' => string|array,        
		    'priceFrom' => string,        
		    'priceTo' => string,        
		    'city' => string,        
		    'zip' => string,        // ... other search params    
		 ],    
		 'deliveryMethods' => [   // Optional: Alert configuration        
				 'email' => [
            'active' => bool,            
            'frequency' => 'immediately'|'daily'|'weekly'        
         ],        
         'push' => [
            'active' => bool,            
            'frequency' => 'immediately'|'daily'|'weekly'        
         ]
    ]
]
// Create Response
[
    'data' => [],    
    'meta' => [
        'savedSearchCreated' => true,        
        'savedSearchId' => int,        
        'dateCreated' => int,           // Unix timestamp        
        'updatedAlertStatus' => bool,   // If deliveryMethods provided        
        'updatedAlertMessage' => string // If deliveryMethods provided    
    ]
]
// MongoDB generalSavedSearch document structure (read by CAPI)
[
    'id' => int,    
    'memberId' => int,    
    'searchName' => string,    
    'searchParams' => string,  // JSON encoded    
    'alert' => bool,    
    'deliveryMethods' => [
        'email' => [
		        'active' => bool, 
		        'frequency' => string
		    ],        
		    'push' => [
				    'active' => bool, 
				    'frequency' => string
				]
    ],  
    'vertical' => 'general',    
    'createTime' => UTCDateTime,    
    'modifyTime' => UTCDateTime
]
```

### m-ksl-myaccount Key Endpoints

```
GET  /myaccount/saved-searches-{vertical}              # Index page
POST /myaccount/saved-searches-{vertical}/get-saved-searches
POST /myaccount/saved-searches-{vertical}/add-saved-search
POST /myaccount/saved-searches-{vertical}/delete-saved-search
POST /myaccount/saved-searches-{vertical}/set-alert
POST /myaccount/saved-searches-{vertical}/get-alerts-for-saved-search
POST /myaccount/saved-searches-{vertical}/delete-alert
POST /myaccount/saved-searches-job/proxy              # Jobs GraphQL proxy
```

## UI

### Jobs

![image.png](Saved%20Search%20&%20Alerts/image.png)

![image.png](Saved%20Search%20&%20Alerts/image%201.png)

![image.png](Saved%20Search%20&%20Alerts/image%202.png)

### Classifieds

![image.png](Saved%20Search%20&%20Alerts/image%203.png)

![image.png](Saved%20Search%20&%20Alerts/image%204.png)