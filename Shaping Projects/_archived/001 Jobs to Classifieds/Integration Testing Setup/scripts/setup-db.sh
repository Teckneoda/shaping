#!/bin/bash
# Setup script for integration test database

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================"
echo "Setting up Integration Test Database"
echo "========================================"
echo

# Check if mongosh is installed
if ! command -v mongosh &> /dev/null; then
    echo "ERROR: mongosh is not installed"
    echo "Please install MongoDB Shell: https://www.mongodb.com/try/download/shell"
    exit 1
fi

# Check if MongoDB is running
if ! mongosh --eval "db.adminCommand('ping')" --quiet > /dev/null 2>&1; then
    echo "ERROR: MongoDB is not running"
    echo "Start MongoDB with: docker-compose -f docker-compose.minimal.yml up -d"
    exit 1
fi

echo "✓ MongoDB is running"
echo

# Seed the database
echo "Seeding database..."
mongosh --file "$PROJECT_DIR/test-data/seed-mongodb.js"

echo
echo "========================================"
echo "Database setup complete!"
echo "========================================"
echo
echo "Connection string: mongodb://localhost:27017/classifieds_test"
echo
echo "To reset the database, run:"
echo "  ./scripts/reset-db.sh"
echo
echo "To clean up completely, run:"
echo "  ./scripts/cleanup-db.sh"
echo
