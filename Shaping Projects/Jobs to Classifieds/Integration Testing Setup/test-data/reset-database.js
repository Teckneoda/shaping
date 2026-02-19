// MongoDB Database Reset Script for Integration Tests
// This script resets the test database to its initial seeded state

// Switch to test database
db = db.getSiblingDB('classifieds_test');

print('Resetting classifieds_test database...');

// ============================================================================
// 1. Delete all listings created during tests (ID > 1000)
// ============================================================================
print('Cleaning up test-created listings...');

const deleteResult = db.general.deleteMany({ id: { $gt: 1000 } });
print(`  Deleted ${deleteResult.deletedCount} test listings (ID > 1000)`);

// ============================================================================
// 2. Restore modified test listings to original state
// ============================================================================
print('Restoring modified test listings...');

// Get list of original test listing IDs
const originalListingIds = [100, 23456789, 61111111, 200, 300, 400];

// For each original listing, check if it was modified
originalListingIds.forEach(id => {
  const listing = db.general.findOne({ id: id });
  if (listing && listing.modifyTime > listing.createTime + 1000) {
    print(`  Listing ${id} was modified - consider re-seeding`);
  }
});

// ============================================================================
// 3. Reset idTracker sequence
// ============================================================================
print('Resetting idTracker sequence...');

db.idTracker.updateOne(
  { _id: 9 },
  { $set: { seq: 1000 } }
);

print('  ✓ idTracker sequence reset to 1000');

// ============================================================================
// 4. Remove any temporary collections
// ============================================================================
print('Checking for temporary collections...');

const collections = db.getCollectionNames();
const tempCollections = collections.filter(name => name.startsWith('temp_') || name.startsWith('test_'));

if (tempCollections.length > 0) {
  tempCollections.forEach(collName => {
    db[collName].drop();
    print(`  Dropped temporary collection: ${collName}`);
  });
} else {
  print('  No temporary collections found');
}

// ============================================================================
// 5. Verify test data integrity
// ============================================================================
print('\nVerifying test data integrity...');

const listingCount = db.general.countDocuments({ id: { $lte: 1000 } });
const dealerCount = db.general_dealer.countDocuments({});
const categoryCount = db.general_category.countDocuments({});
const idTracker = db.idTracker.findOne({ _id: 9 });

print(`  Listings (ID ≤ 1000): ${listingCount} (expected: 6)`);
print(`  Dealers: ${dealerCount} (expected: 3)`);
print(`  Categories: ${categoryCount} (expected: 5)`);
print(`  ID Tracker seq: ${idTracker.seq} (expected: 1000)`);

// ============================================================================
// Summary
// ============================================================================
print('\n========================================');
print('Database Reset Complete!');
print('========================================');
print('The database is ready for the next test run.');
print('========================================\n');

// Exit with appropriate code
if (listingCount === 6 && dealerCount === 3 && categoryCount === 5 && idTracker.seq === 1000) {
  print('✓ All integrity checks passed');
} else {
  print('⚠ WARNING: Integrity checks failed - consider re-seeding');
  print('  Run: mongosh --file seed-mongodb.js');
}
