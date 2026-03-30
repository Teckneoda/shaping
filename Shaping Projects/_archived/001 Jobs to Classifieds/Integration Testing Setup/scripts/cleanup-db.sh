#!/bin/bash
# Cleanup script for integration test database

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================"
echo "WARNING: Database Cleanup"
echo "========================================"
echo
echo "This will COMPLETELY DROP the classifieds_test database!"
echo "All data will be permanently deleted."
echo
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Check if MongoDB is running
if ! mongosh --eval "db.adminCommand('ping')" --quiet > /dev/null 2>&1; then
    echo "ERROR: MongoDB is not running"
    exit 1
fi

echo
echo "Dropping database..."
mongosh --file "$PROJECT_DIR/test-data/cleanup-database.js"

echo
echo "========================================"
echo "Database cleanup complete!"
echo "========================================"
echo
echo "To re-create the database, run:"
echo "  ./scripts/setup-db.sh"
echo
