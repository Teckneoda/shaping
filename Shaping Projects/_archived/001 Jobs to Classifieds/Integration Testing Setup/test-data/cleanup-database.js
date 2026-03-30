// MongoDB Database Cleanup Script for Integration Tests
// This script completely removes all test data and drops the test database

// Switch to test database
db = db.getSiblingDB('classifieds_test');

print('========================================');
print('WARNING: This will DROP the entire classifieds_test database!');
print('========================================\n');

print('Dropping classifieds_test database...');

// Drop the entire database
db.dropDatabase();

print('✓ Database dropped successfully\n');

print('========================================');
print('Database Cleanup Complete!');
print('========================================');
print('To re-create the test database, run:');
print('  mongosh --file seed-mongodb.js');
print('========================================\n');
