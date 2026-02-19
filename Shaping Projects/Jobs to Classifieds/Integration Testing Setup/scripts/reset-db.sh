#!/bin/bash
# Reset script for integration test database

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================"
echo "Resetting Integration Test Database"
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

# Reset the database
echo "Resetting database..."
mongosh --file "$PROJECT_DIR/test-data/reset-database.js"

echo
echo "========================================"
echo "Database reset complete!"
echo "========================================"
echo
echo "The database has been reset to its initial state."
echo "All test-created data (ID > 1000) has been removed."
echo
