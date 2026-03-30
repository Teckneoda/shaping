# Integration Testing Setup

This directory contains the infrastructure for integration testing CAPI (PHP) and listing-http-rest (Go) services to verify parity during the Jobs to Classifieds migration.

## Quick Start

### 1. Start MongoDB

```bash
# Start MongoDB in Docker
docker-compose -f docker-compose.minimal.yml up -d

# Wait for MongoDB to be ready
docker-compose -f docker-compose.minimal.yml ps
```

### 2. Seed Test Database

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Seed the database
./scripts/setup-db.sh
```

### 3. Verify Database

```bash
# Connect to MongoDB
mongosh mongodb://localhost:27017/classifieds_test

# Check collections
> show collections
> db.general.countDocuments()  // Should return 6
> db.general_dealer.countDocuments()  // Should return 3
```

## Directory Structure

```
Integration Testing Setup/
├── README.md                    # This file
├── docker-compose.yml           # Full Docker setup (CAPI + listing-http-rest + MongoDB)
├── docker-compose.minimal.yml   # MongoDB only (for local development)
├── scripts/
│   ├── setup-db.sh             # Seed the test database
│   ├── reset-db.sh             # Reset database between test runs
│   └── cleanup-db.sh           # Drop the entire test database
├── test-data/
│   ├── seed-mongodb.js         # Main seeding script
│   ├── reset-database.js       # Reset script
│   └── cleanup-database.js     # Cleanup script
└── tests/                       # (To be created in Phase 2)
    └── integration/
        ├── setup_test.go
        ├── clients/
        ├── comparators/
        └── ...
```

## Test Database Schema

### Database: `classifieds_test`

### Collections:

#### 1. **general** (Listings)
- 6 test listings with IDs 100-400
- Various statuses: Active, Stub, Pending
- Various types: Private seller, Dealer, Rental
- Special cases: Price drops, photos, complex data

#### 2. **general_dealer** (Dealers)
- 3 test dealers
- Different configurations: With limits, transfer phones, etc.

#### 3. **general_category** (Categories)
- 5 categories with subcategories
- Validation rules (maxPrice, allowedMarketTypes)

#### 4. **idTracker** (ID Sequences)
- Sequence generator starting at 1000
- Test-created listings will have IDs > 1000

## Test Data

### Test Listings

| ID | Status | Type | Description |
|----|--------|------|-------------|
| 100 | Active | Private | Basic listing for sale |
| 23456789 | Active | Dealer | RV with photos and dealer data |
| 61111111 | Active | Private | Rental with priceModifier |
| 200 | Stub | Private | Draft listing (minimal fields) |
| 300 | Active | Private | Listing with price drop history |
| 400 | Pending | Private | Pending activation status |

### Test Dealers

| memberId | Name | Limit | Special Features |
|----------|------|-------|------------------|
| 2345678 | Southern Idaho RV | 500 | High volume, transfer numbers |
| 12345 | Wayne Enterprises | 15 | showDealerInfo=true (phone override) |
| 9876543 | Local Family Business | 0 | No active limit |

### Test Users (JWT Payloads)

**Standard User** (memberId: 2615897):
- kslMemberGroup: member
- Name: Jimmy Donaldson
- Email: jimbo@bob.com

**Admin User** (memberId: 999999):
- kslMemberGroup: admin
- Name: Admin User
- Email: admin@ksl.com

## Database Management

### Seed Database
```bash
./scripts/setup-db.sh
```
Creates fresh test database with all seed data.

### Reset Database
```bash
./scripts/reset-db.sh
```
- Removes listings with ID > 1000 (test-created)
- Resets idTracker sequence to 1000
- Keeps original seed data intact

### Cleanup Database
```bash
./scripts/cleanup-db.sh
```
Completely drops the `classifieds_test` database. Use this for full cleanup.

### Manual Database Operations

```bash
# Seed database manually
mongosh --file test-data/seed-mongodb.js

# Reset database manually
mongosh --file test-data/reset-database.js

# Cleanup database manually
mongosh --file test-data/cleanup-database.js
```

## Docker Compose Configurations

### Minimal (MongoDB Only)

Use when running CAPI and listing-http-rest outside of Docker:

```bash
docker-compose -f docker-compose.minimal.yml up -d
```

### Full Stack

Use when running both services in Docker:

```bash
docker-compose up -d
```

**Services:**
- MongoDB on port 27017
- CAPI on port 8081
- listing-http-rest on port 8082

## Connection Strings

### From Host Machine
```
mongodb://localhost:27017/classifieds_test
```

### From Docker Container
```
mongodb://mongodb:27017/classifieds_test
```

### CAPI URL
```
http://localhost:8081
```

### listing-http-rest URL
```
http://localhost:8082
```

## Testing Workflow

### Before Each Test Run
```bash
# Reset database to clean state
./scripts/reset-db.sh
```

### After All Tests
```bash
# Optional: Stop MongoDB
docker-compose -f docker-compose.minimal.yml down

# Optional: Remove data volume
docker-compose -f docker-compose.minimal.yml down -v
```

## Troubleshooting

### MongoDB Not Starting

```bash
# Check Docker logs
docker-compose -f docker-compose.minimal.yml logs mongodb

# Ensure port 27017 is not in use
lsof -i :27017

# Remove old containers/volumes
docker-compose -f docker-compose.minimal.yml down -v
```

### Seed Script Fails

```bash
# Check MongoDB is running
docker-compose -f docker-compose.minimal.yml ps

# Check MongoDB health
mongosh --eval "db.adminCommand('ping')"

# Try manual seeding
mongosh mongodb://localhost:27017/classifieds_test --file test-data/seed-mongodb.js
```

### Cannot Connect to MongoDB

```bash
# Verify MongoDB is accessible
mongosh mongodb://localhost:27017/admin --eval "db.adminCommand('ping')"

# Check network
docker network ls
docker network inspect integration-test-network
```

## Next Steps

### Phase 2: Test Infrastructure (Coming Soon)

Will create:
- Go test framework in `tests/integration/`
- HTTP clients for CAPI and listing-http-rest
- Response comparison utilities
- JWT generation helpers
- MongoDB query helpers

### Phase 3: CRUD Operation Tests

Will implement tests for:
- Create listing
- Get listing
- Update listing
- Delete listing

## Environment Variables

### For CAPI
```env
APP_ENV=test
MONGO_URL=mongodb://mongodb:27017
MONGO_DATABASE=classifieds_test
```

### For listing-http-rest
```env
PORT=8080
PROJECT_ID=ddm-platform-test
MONGO_URL=mongodb://mongodb:27017
MONGO_DATABASE=classifieds_test
CAPI_URL=http://capi:8080
```

## References

- [Integration Testing Plan](./Integration%20Testing%20Plan.md)
- [CAPI Controller Tests](../../../Research%20Repos/Legacy/m-ksl-classifieds-api/tests/Controller/)
- [listing-http-rest](../../../Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/)

## Support

For questions or issues:
1. Check the [Integration Testing Plan](./Integration%20Testing%20Plan.md)
2. Review CAPI test fixtures in `Research Repos/Legacy/m-ksl-classifieds-api/tests/Controller/data/listings/`
3. Consult with the backend team
