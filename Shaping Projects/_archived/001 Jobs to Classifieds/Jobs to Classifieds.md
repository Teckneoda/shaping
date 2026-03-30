# Jobs to Classifieds Migration

## Project Overview

This project involves migrating the legacy KSL Jobs Vertical into the Classifieds system.
In tandem with this, we will be modernizing the Classifieds API to align with our service oriented architecture in golang.

### Project Goals

1. **Move Jobs Vertical into Classifieds System**: Migrate the legacy KSL Jobs Vertical into the Classifieds system.
2. **Modernize Technology Stack**: Migrate from PHP/Symfony to Golang per ADR requirements of not adding new PHP code
3. **Maintain Feature Parity**: Ensure all existing functionality is preserved during migration
4. **Decommission Legacy System**: Remove the legacy KSL Jobs Vertical from. Additionally begin removal of CAPI codebase.

---

## Current State

### Legacy Jobs Vertical

**Repository**: [`m-ksl-jobs`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-jobs)

### Legacy Classifieds API

**Repository**: [`m-ksl-classifieds-api`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api)

### Key Dependencies

The legacy system integrates with multiple external services:
- **Member API**: User authentication and profile management
- **MyAccount API**: Account operations and preferences
- **KSL API**: Shared KSL services and utilities
- **Stripe**: Payment processing for premium listings
- **Spincar**: 360° vehicle tour integration
- **S3**: Image and media storage
- **Mandrill**: Transactional email delivery
- **Sift**: Fraud detection and prevention
- **PubSub**: Event-driven messaging

---

## Target Architecture

### New Service: Listing Service (Golang)

The new Golang service will be designed as a cloud-native microservice with the following characteristics:

#### Technology Stack
- **Language**: Go 1.21+
- **Web Framework**: TBD (Gin, Echo, or Chi)
- **Database Drivers**: 
  - MongoDB Go Driver
  - MySQL Driver (go-sql-driver/mysql)
  - Elasticsearch Go Client
- **Cache**: Redis (replacing Memcached)
- **API Documentation**: OpenAPI 3.0 / Swagger
- **Observability**: Prometheus metrics, structured logging, distributed tracing

#### Service Boundaries

The Listing Service will be responsible for:
- Listing lifecycle management (create, read, update, delete)
- Search and filtering
- Category and taxonomy management
- Photo and media management
- Dealer operations
- Favorites and saved searches
- Abuse reporting and moderation

#### What Stays External

The following will remain as external service dependencies:
- Authentication (Member API)
- Payment processing (Stripe + internal payment service)
- Email delivery (Mandrill or replacement)
- Image storage and processing (S3 + image service)
- Fraud detection (Sift)

---

## Migration Strategy

### Phased Approach

#### Phase 1: Core Listing Operations (MVP)
**Goal**: Establish foundation and migrate critical paths

- [ ] Authentication integration
- [ ] Core listing CRUD (create, read, update, delete)
- [ ] Listing search functionality
- [ ] Photo upload and management
- [ ] Basic category operations

**Success Criteria**: Can create, view, edit, and search listings

---

#### Phase 2: Supporting Features
**Goal**: Add user-facing features for complete experience

- [ ] Categories and filters (full implementation)
- [ ] Favorites and saved searches
- [ ] Member-specific operations
- [ ] Dealer management and profiles
- [ ] Listing metadata and support endpoints

**Success Criteria**: Feature parity with legacy system for end users

---

#### Phase 3: Advanced Features
**Goal**: Migrate specialized and integration features

- [ ] Surveys and statistics
- [ ] Abuse reporting and moderation
- [ ] Tours/Spincar integration
- [ ] Payment processing integration
- [ ] Notifications (price drops, expirations)
- [ ] Spotlight/featured listings

**Success Criteria**: All user-facing features migrated

---

#### Phase 4: Administrative & Edge Cases
**Goal**: Complete migration with admin tools and edge cases

- [ ] Management endpoints (batch operations)
- [ ] Archive operations
- [ ] Homepage aggregation endpoints
- [ ] Legacy endpoint deprecation
- [ ] Performance optimization

**Success Criteria**: Legacy system can be decommissioned

---

## Project Artifacts

### Documentation

- **[Listing Service Outline](file:///Users/cpies/code/AI-Agents/Shaping%20Projects/Jobs%20to%20Classifieds/Listing%20Service%20Outline.md)**: Comprehensive endpoint inventory and technical reference
- **API Specifications**: OpenAPI/Swagger specs (TBD)
- **Data Models**: Entity relationship diagrams and schema definitions (TBD)
- **Architecture Decision Records**: Key technical decisions and rationale (TBD)

### Code Repositories

- **Legacy**: [`m-ksl-classifieds-api`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api)
- **New Service**: TBD (to be created in appropriate organization)

---

## Next Steps

### Immediate Actions

1. **[Define Golang Service Structure](#golang-service-structure)**: Determine package organization, routing framework, and middleware architecture
2. **[Design Data Layer](#data-layer-design)**: Plan data access patterns for MongoDB, MySQL, and Elasticsearch
3. **[Create API Specifications](#api-specifications)**: Document OpenAPI specs for Phase 1 endpoints
4. **[Plan Authentication Strategy](#authentication-strategy)**: Design JWT integration with Member API
5. **[Establish Testing Strategy](#testing-strategy)**: Define unit, integration, and E2E testing approach
6. **[Plan Deployment](#deployment-plan)**: Design containerization, CI/CD, and infrastructure

### Decision Points

> [!IMPORTANT]
> The following decisions need to be made before implementation begins:

1. **Web Framework Selection**: Gin vs Echo vs Chi vs stdlib
2. **Cache Strategy**: Redis configuration and caching patterns
3. **Database Connection Pooling**: Connection limits and retry strategies
4. **API Versioning**: URL-based vs header-based versioning
5. **Deployment Target**: Kubernetes, Cloud Run, or other platform
6. **Monitoring Stack**: Prometheus + Grafana vs vendor solution

---

## Golang Service Structure

### Proposed Package Organization

```
listing-service/
├── cmd/
│   └── server/           # Application entry point
│       └── main.go
├── internal/
│   ├── api/              # HTTP handlers and routing
│   │   ├── handlers/     # Request handlers
│   │   ├── middleware/   # HTTP middleware
│   │   └── routes.go     # Route definitions
│   ├── domain/           # Business logic and entities
│   │   ├── listing/      # Listing domain
│   │   ├── category/     # Category domain
│   │   ├── dealer/       # Dealer domain
│   │   └── ...
│   ├── repository/       # Data access layer
│   │   ├── mongo/        # MongoDB repositories
│   │   ├── mysql/        # MySQL repositories
│   │   └── elasticsearch/ # Search repositories
│   ├── service/          # Business services
│   │   ├── listing/      # Listing service
│   │   ├── auth/         # Authentication service
│   │   └── ...
│   └── pkg/              # Internal shared packages
│       ├── config/       # Configuration management
│       ├── logger/       # Logging utilities
│       └── errors/       # Error handling
├── pkg/                  # Public packages (if any)
├── api/                  # API specifications
│   └── openapi/          # OpenAPI/Swagger specs
├── deployments/          # Deployment configurations
│   ├── docker/           # Dockerfiles
│   └── k8s/              # Kubernetes manifests
├── scripts/              # Build and utility scripts
├── tests/                # Integration and E2E tests
├── go.mod
├── go.sum
└── README.md
```

---

## Data Layer Design

### Database Access Patterns

#### MongoDB (Primary Data Store)
- **Collections**: listings, categories, dealers, favorites, surveys, abuse_reports
- **Access Pattern**: Repository pattern with interfaces
- **Connection**: Connection pool with configurable limits
- **Transactions**: Use when needed for multi-document operations

#### MySQL (Secondary Data Store)
- **Tables**: TBD (need to identify which data lives in MySQL)
- **Access Pattern**: Repository pattern matching MongoDB
- **Connection**: Connection pool with prepared statements

#### Elasticsearch (Search)
- **Indices**: listings, categories
- **Access Pattern**: Search service abstraction
- **Sync Strategy**: Event-driven updates via PubSub

#### Redis (Cache)
- **Use Cases**: 
  - API response caching
  - Session data
  - Rate limiting
  - Frequently accessed metadata
- **TTL Strategy**: Configurable per data type

---

## API Specifications

### OpenAPI/Swagger

All endpoints will be documented using OpenAPI 3.0 specification. Each endpoint will include:
- Request/response schemas
- Authentication requirements
- Error responses
- Example payloads
- Rate limiting information

### Versioning Strategy

**Recommendation**: URL-based versioning (`/v1/listings`, `/v2/listings`)
- Clear and explicit
- Easy to route and deprecate
- Industry standard

---

## Authentication Strategy

### JWT Integration

The service will integrate with the existing Member API for authentication:

1. **Token Validation**: Validate JWT tokens issued by Member API
2. **Token Refresh**: Support token refresh flow
3. **Anonymous Access**: Support anonymous tokens for public endpoints
4. **Middleware**: JWT validation middleware for protected routes

### Authorization

- **Role-based**: Admin, dealer, member, anonymous
- **Resource-based**: Owner can edit their own listings
- **Scope-based**: Different token scopes for different operations

---

## Testing Strategy

### Unit Tests
- **Coverage Target**: 80%+ for business logic
- **Framework**: Go standard testing package + testify
- **Mocking**: Interfaces for all external dependencies

### Integration Tests
- **Database**: Use test containers for MongoDB, MySQL
- **External Services**: Mock external APIs
- **Framework**: Go standard testing + testcontainers

### E2E Tests
- **Scope**: Critical user journeys
- **Environment**: Staging environment
- **Tools**: TBD (possibly Postman/Newman or custom Go tests)

### Performance Tests
- **Load Testing**: k6 or similar
- **Benchmarks**: Go benchmark tests for critical paths
- **Targets**: TBD based on current system metrics

---

## Deployment Plan

### Containerization

**Docker**: Multi-stage builds for optimized images
```dockerfile
# Build stage
FROM golang:1.21-alpine AS builder
# ... build steps

# Runtime stage
FROM alpine:latest
# ... minimal runtime
```

### CI/CD Pipeline

1. **Build**: Compile, run tests, build Docker image
2. **Test**: Run integration and E2E tests
3. **Deploy**: 
   - Dev: Auto-deploy on merge to main
   - Staging: Auto-deploy with manual approval
   - Production: Manual deployment with rollback capability

### Infrastructure

**Kubernetes** (recommended):
- Horizontal Pod Autoscaling
- Health checks and readiness probes
- ConfigMaps and Secrets for configuration
- Service mesh for observability (optional)

### Monitoring & Observability

- **Metrics**: Prometheus + Grafana
- **Logging**: Structured JSON logs
- **Tracing**: OpenTelemetry for distributed tracing
- **Alerts**: Critical error rates, latency, availability

---

## Risk Assessment

### Technical Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Data migration complexity | High | Phased approach, extensive testing |
| Performance regression | High | Load testing, gradual rollout |
| External service dependencies | Medium | Circuit breakers, fallback strategies |
| MongoDB/MySQL schema differences | Medium | Comprehensive data mapping documentation |

### Business Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feature gaps during migration | High | Maintain legacy system in parallel |
| User experience disruption | High | Backward compatibility, gradual rollout |
| Timeline delays | Medium | Phased delivery, MVP approach |

---

## Success Metrics

### Performance
- API response time: p95 < 200ms (improvement over legacy)
- Search latency: p95 < 500ms
- Throughput: Support 2x current traffic

### Reliability
- Uptime: 99.9%+
- Error rate: < 0.1%

### Development
- Test coverage: 80%+
- Deployment frequency: Daily to staging
- Mean time to recovery: < 30 minutes

---

## Timeline (Estimated)

- **Phase 1 (MVP)**: 8-10 weeks
- **Phase 2 (Supporting Features)**: 6-8 weeks
- **Phase 3 (Advanced Features)**: 6-8 weeks
- **Phase 4 (Admin & Cleanup)**: 4-6 weeks

**Total**: 24-32 weeks (6-8 months)

> [!NOTE]
> Timeline assumes dedicated team of 2-3 engineers and may vary based on actual complexity discovered during implementation.

---

## References

- **[Listing Service Outline](file:///Users/cpies/code/AI-Agents/Shaping%20Projects/Jobs%20to%20Classifieds/Listing%20Service%20Outline.md)**: Complete endpoint inventory
- **[Research Guidelines](file:///Users/cpies/code/AI-Agents/Shaping%20Projects/Claude.md)**: Documentation conventions
- **Legacy Repository**: [`m-ksl-classifieds-api`](file:///Users/cpies/code/AI-Agents/Research%20Repos/Legacy/m-ksl-classifieds-api)
