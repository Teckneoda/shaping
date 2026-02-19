#!/bin/bash
# Verification script for integration test database

set -e

echo "========================================"
echo "Verifying Integration Test Database"
echo "========================================"
echo

# Check if MongoDB is running
if ! mongosh --eval "db.adminCommand('ping')" --quiet > /dev/null 2>&1; then
    echo "ERROR: MongoDB is not running"
    echo "Start MongoDB with: docker-compose -f docker-compose.minimal.yml up -d"
    exit 1
fi

echo "✓ MongoDB is running"
echo

# Verify database exists
DB_EXISTS=$(mongosh --quiet --eval "db.getSiblingDB('classifieds_test').getCollectionNames().length" 2>/dev/null || echo "0")

if [ "$DB_EXISTS" -eq "0" ]; then
    echo "ERROR: classifieds_test database does not exist"
    echo "Run: ./scripts/setup-db.sh"
    exit 1
fi

echo "✓ classifieds_test database exists"
echo

# Verify collections
echo "Checking collections..."

LISTING_COUNT=$(mongosh --quiet classifieds_test --eval "db.general.countDocuments()" 2>/dev/null || echo "0")
DEALER_COUNT=$(mongosh --quiet classifieds_test --eval "db.general_dealer.countDocuments()" 2>/dev/null || echo "0")
CATEGORY_COUNT=$(mongosh --quiet classifieds_test --eval "db.general_category.countDocuments()" 2>/dev/null || echo "0")
IDTRACKER_EXISTS=$(mongosh --quiet classifieds_test --eval "db.idTracker.countDocuments()" 2>/dev/null || echo "0")

echo "  general collection: $LISTING_COUNT documents (expected: 6)"
echo "  general_dealer collection: $DEALER_COUNT documents (expected: 3)"
echo "  general_category collection: $CATEGORY_COUNT documents (expected: 5)"
echo "  idTracker collection: $IDTRACKER_EXISTS documents (expected: 1)"
echo

# Verify data integrity
ALL_CHECKS_PASSED=true

if [ "$LISTING_COUNT" -ne "6" ]; then
    echo "✗ Listing count mismatch"
    ALL_CHECKS_PASSED=false
fi

if [ "$DEALER_COUNT" -ne "3" ]; then
    echo "✗ Dealer count mismatch"
    ALL_CHECKS_PASSED=false
fi

if [ "$CATEGORY_COUNT" -ne "5" ]; then
    echo "✗ Category count mismatch"
    ALL_CHECKS_PASSED=false
fi

if [ "$IDTRACKER_EXISTS" -ne "1" ]; then
    echo "✗ idTracker not found"
    ALL_CHECKS_PASSED=false
fi

# Verify specific test listings
echo "Verifying test listings..."

TEST_LISTING_IDS=(100 23456789 61111111 200 300 400)
for ID in "${TEST_LISTING_IDS[@]}"; do
    EXISTS=$(mongosh --quiet classifieds_test --eval "db.general.countDocuments({id: $ID})" 2>/dev/null || echo "0")
    if [ "$EXISTS" -eq "1" ]; then
        echo "  ✓ Listing ID $ID exists"
    else
        echo "  ✗ Listing ID $ID missing"
        ALL_CHECKS_PASSED=false
    fi
done

echo

# Verify idTracker sequence
ID_SEQ=$(mongosh --quiet classifieds_test --eval "db.idTracker.findOne({_id: 9}).seq" 2>/dev/null || echo "0")
echo "ID Tracker sequence: $ID_SEQ (expected: 1000)"

if [ "$ID_SEQ" -ne "1000" ]; then
    echo "✗ ID Tracker sequence incorrect"
    ALL_CHECKS_PASSED=false
fi

echo

# Summary
echo "========================================"
if [ "$ALL_CHECKS_PASSED" = true ]; then
    echo "✓ All verification checks PASSED"
    echo "========================================"
    echo
    echo "Database is ready for integration testing!"
    echo
    echo "Connection string: mongodb://localhost:27017/classifieds_test"
    exit 0
else
    echo "✗ Some verification checks FAILED"
    echo "========================================"
    echo
    echo "Please re-seed the database:"
    echo "  ./scripts/setup-db.sh"
    exit 1
fi
