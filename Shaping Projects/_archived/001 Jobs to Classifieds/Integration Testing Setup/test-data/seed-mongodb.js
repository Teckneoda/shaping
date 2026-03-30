// MongoDB Seeding Script for Integration Tests
// This script seeds the classifieds_test database with test data for CAPI and listing-http-rest integration testing

// Switch to test database
db = db.getSiblingDB('classifieds_test');

print('Seeding classifieds_test database...');

// ============================================================================
// 1. Seed idTracker collection
// ============================================================================
print('Seeding idTracker collection...');

db.idTracker.deleteMany({});
db.idTracker.insertOne({
  _id: 9,
  name: 'General Ad',
  seq: 1000 // Start test IDs at 1000
});

print('✓ idTracker collection seeded');

// ============================================================================
// 2. Seed general_dealer collection
// ============================================================================
print('Seeding general_dealer collection...');

db.general_dealer.deleteMany({});
db.general_dealer.insertMany([
  // Dealer 1 - With Active Limit (High volume dealer)
  {
    memberId: 2345678,
    dealerName: 'Southern Idaho RV and Marine',
    city: 'Jerome',
    state: 'ID',
    zip: '83338',
    limits: {
      status: 'Active',
      limitType: 'General',
      limitNumber: 500
    },
    showMoreListingsBySellerCarousel: true,
    transferNumber: '5555555555',
    transferTextNumber: '5555555556',
    logo: 'https://img.ksl.com/mx/mplace-classifieds.ksl.com/dealer-logo.png'
  },

  // Dealer 2 - With Transfer Phone Override
  {
    memberId: 12345,
    dealerName: 'Wayne Enterprises, Inc.',
    city: 'Gotham City',
    state: 'UT',
    zip: '84101',
    limits: {
      status: 'Active',
      limitType: 'General',
      limitNumber: 15
    },
    transferNumber: '8015551234',
    transferTextNumber: '8015551235',
    showDealerInfo: true, // This triggers phone override
    address1: '1007 Mountain Drive',
    showMoreListingsBySellerCarousel: false
  },

  // Dealer 3 - No Active Limit (Free dealer)
  {
    memberId: 9876543,
    dealerName: 'Local Family Business',
    city: 'Provo',
    state: 'UT',
    zip: '84601',
    limits: {
      status: 'Inactive',
      limitType: 'General',
      limitNumber: 0
    }
  }
]);

print('✓ general_dealer collection seeded with 3 dealers');

// ============================================================================
// 3. Seed general collection (Listings)
// ============================================================================
print('Seeding general collection...');

db.general.deleteMany({});
db.general.insertMany([
  // Document 1 - Basic Private Seller Listing (Active)
  {
    id: 100,
    memberId: 2615897,
    status: 'Active',
    createTime: NumberLong(1629153094),
    displayTime: NumberLong(1629153897),
    modifyTime: NumberLong(1629153598),
    expireTime: NumberLong(1631745897),
    postTime: NumberLong(1629153897),
    category: 'General',
    subCategory: 'Junk For Sale',
    title: 'Test Item for Sale',
    description: 'Basic test listing for integration tests',
    price: 7600, // $76.00
    marketType: 'Sale',
    sellerType: 'Private',
    city: 'Salt Lake City',
    state: 'UT',
    zip: '84101',
    lat: 40.7608,
    lon: -111.8910,
    latLon: '40.7608,-111.8910',
    latLonSource: 'ZipDatabase',
    name: 'Jimmy Donaldson',
    email: 'jimbo@bob.com',
    emailCanonical: 'jimbo@bob.com',
    homePhone: '8015551111',
    contactMethod: ['messages', 'phoneEmail'],
    postIp: '192.168.1.1',
    sessionId: 'test-session-1',
    postingPlatformName: 'web',
    history: [
      {
        time: NumberLong(1629153094),
        action: 'created',
        comment: 'Listing created'
      }
    ]
  },

  // Document 2 - Dealer with Photos and Complex Data (Active)
  {
    id: 23456789,
    memberId: 2345678,
    status: 'Active',
    createTime: NumberLong(1629153094),
    displayTime: NumberLong(1629153897),
    modifyTime: NumberLong(1629153598),
    expireTime: NumberLong(1631745897),
    postTime: NumberLong(1629153897),
    category: 'Recreational Vehicles',
    subCategory: 'Travel Trailers, Bumper Pull',
    title: 'HIDEOUT 24BHS',
    description: 'Detailed RV description with all the bells and whistles. Perfect for family camping trips.',
    descriptionMarkdown: '**Detailed RV description** with all the bells and whistles.\n\nPerfect for family camping trips.',
    price: 2699500, // $26,995.00
    marketType: 'Sale',
    sellerType: 'Business',
    stockNumber: 'spincarId',
    newUsed: 'New',
    city: 'Jerome',
    state: 'ID',
    zip: '83338',
    lat: 42.7098,
    lon: -114.461,
    latLon: '42.7098,-114.461',
    latLonSource: 'Geocoded',
    name: 'Lucius Fox',
    email: 'lfox@wayneindustries.com',
    emailCanonical: 'lfox@wayneindustries.com',
    cellPhone: '999-999-9999',
    contactMethod: ['messages', 'phoneEmail'],
    photo: [
      {
        id: 'http://img.ksl.com/mx/mplace-classifieds.ksl.com/2345678-1629153094-168072.jpg',
        extension: 'jpg',
        height: '635',
        width: '392',
        uploadTime: NumberLong(1629153096),
        md5: '05d2ff29f1dde832c8325818a06b84a0',
        originalFileName: 'rv-front.jpg',
        filterArray: [
          'marketplace/664x500',
          'marketplace/664x300_cropped',
          'marketplace/400x300_cropped'
        ]
      }
    ],
    dealerData: {
      dealerName: 'Southern Idaho RV and Marine',
      city: 'Jerome',
      state: 'ID',
      zip: '83338',
      activeLimit: true,
      limitNumber: 500
    },
    postIp: '192.168.1.2',
    sessionId: 'test-session-2',
    postingPlatformName: 'web',
    history: [
      {
        time: NumberLong(1629153094),
        action: 'created',
        comment: 'Listing created'
      }
    ]
  },

  // Document 3 - Rental Listing (Active)
  {
    id: 61111111,
    memberId: 222222,
    status: 'Active',
    createTime: NumberLong(1629153094),
    displayTime: NumberLong(1629153897),
    modifyTime: NumberLong(1629153598),
    expireTime: NumberLong(1631745897),
    postTime: NumberLong(1629153897),
    category: 'General',
    subCategory: 'Junk For Sale',
    marketType: 'Rent',
    priceModifier: 'perWeek',
    renewCount: 2,
    title: 'Rental Item',
    description: 'Weekly rental available. Great condition.',
    price: 5000, // $50.00 per week
    sellerType: 'Private',
    city: 'Orem',
    state: 'UT',
    zip: '84057',
    lat: 40.2969,
    lon: -111.6946,
    latLon: '40.2969,-111.6946',
    name: 'Jane Doe',
    email: 'jane@example.com',
    emailCanonical: 'jane@example.com',
    cellPhone: '8015552222',
    contactMethod: ['phone', 'email'],
    rentalRules: ['No smoking', 'Pet friendly', 'First and last month required'],
    postIp: '192.168.1.3',
    sessionId: 'test-session-3',
    postingPlatformName: 'web'
  },

  // Document 4 - Stub Listing (Draft)
  {
    id: 200,
    memberId: 2615897,
    status: 'Stub',
    createTime: NumberLong(1629153094),
    modifyTime: NumberLong(1629153094),
    expireTime: NumberLong(1631745897),
    category: 'Furniture',
    subCategory: 'Dressers',
    title: '',
    description: '',
    price: 0,
    postIp: '192.168.1.1',
    sessionId: 'test-session-4',
    postingPlatformName: 'web',
    history: [
      {
        time: NumberLong(1629153094),
        action: 'created',
        comment: 'Stub created'
      }
    ]
  },

  // Document 5 - Listing with Price Drop History
  {
    id: 300,
    memberId: 2615897,
    status: 'Active',
    createTime: NumberLong(1629153094),
    displayTime: NumberLong(1629153897),
    modifyTime: NumberLong(1629153598),
    expireTime: NumberLong(1631745897),
    postTime: NumberLong(1629153897),
    category: 'Electronics',
    subCategory: 'Computers & Hardware',
    title: 'Gaming Laptop - Price Reduced!',
    description: 'High-performance gaming laptop. Price dropped!',
    price: 75000, // $750.00 (reduced from $1000)
    marketType: 'Sale',
    sellerType: 'Private',
    city: 'Salt Lake City',
    state: 'UT',
    zip: '84101',
    name: 'John Smith',
    email: 'john@example.com',
    emailCanonical: 'john@example.com',
    contactMethod: ['email'],
    reducedPriceData: {
      originalPrice: 100000, // $1000.00
      reducedPrice: 75000, // $750.00
      reducedDate: NumberLong(1629153598),
      thresholdBreach: true,
      percentageReduction: 25
    },
    ribbons: ['price-drop'],
    postIp: '192.168.1.1',
    sessionId: 'test-session-5',
    postingPlatformName: 'web'
  },

  // Document 6 - Pending Activation (for new service testing)
  {
    id: 400,
    memberId: 2615897,
    status: 'Pending',
    createTime: NumberLong(1629153094),
    modifyTime: NumberLong(1629153598),
    expireTime: NumberLong(1631745897),
    category: 'Auto Parts and Accessories',
    subCategory: 'Tires & Wheels',
    title: 'Brand New Tires',
    description: 'Set of 4 brand new all-season tires',
    price: 40000, // $400.00
    marketType: 'Sale',
    sellerType: 'Private',
    city: 'Provo',
    state: 'UT',
    zip: '84601',
    name: 'Jimmy Donaldson',
    email: 'jimbo@bob.com',
    emailCanonical: 'jimbo@bob.com',
    cellPhone: '8015551111',
    contactMethod: ['messages', 'phoneEmail'],
    postIp: '192.168.1.1',
    sessionId: 'test-session-6',
    postingPlatformName: 'web',
    history: [
      {
        time: NumberLong(1629153094),
        action: 'created',
        comment: 'Listing created'
      },
      {
        time: NumberLong(1629153598),
        action: 'pending',
        comment: 'Listing pending activation'
      }
    ]
  }
]);

print('✓ general collection seeded with 6 listings');

// ============================================================================
// 4. Seed general_category collection (simplified category tree)
// ============================================================================
print('Seeding general_category collection...');

db.general_category.deleteMany({});
db.general_category.insertMany([
  {
    category: 'General',
    subCategories: [
      {
        name: 'Junk For Sale',
        maxPrice: 100000000, // $1,000,000
        allowedMarketTypes: ['Sale', 'Wanted'],
        specifications: []
      }
    ]
  },
  {
    category: 'Recreational Vehicles',
    subCategories: [
      {
        name: 'Travel Trailers, Bumper Pull',
        maxPrice: 10000000000, // $100,000,000
        allowedMarketTypes: ['Sale', 'Wanted'],
        specifications: ['condition', 'year', 'make', 'model']
      }
    ]
  },
  {
    category: 'Furniture',
    subCategories: [
      {
        name: 'Dressers',
        maxPrice: 500000000, // $5,000,000
        allowedMarketTypes: ['Sale', 'Rent', 'Wanted'],
        specifications: ['condition', 'material']
      }
    ]
  },
  {
    category: 'Electronics',
    subCategories: [
      {
        name: 'Computers & Hardware',
        maxPrice: 1000000000, // $10,000,000
        allowedMarketTypes: ['Sale', 'Wanted'],
        specifications: ['condition', 'brand', 'model']
      }
    ]
  },
  {
    category: 'Auto Parts and Accessories',
    subCategories: [
      {
        name: 'Tires & Wheels',
        maxPrice: 500000000, // $5,000,000
        allowedMarketTypes: ['Sale', 'Wanted'],
        specifications: ['condition', 'brand', 'size']
      }
    ]
  }
]);

print('✓ general_category collection seeded with 5 categories');

// ============================================================================
// Summary
// ============================================================================
print('\n========================================');
print('Database Seeding Complete!');
print('========================================');
print('Database: classifieds_test');
print('Collections seeded:');
print('  - idTracker: 1 document (seq starts at 1000)');
print('  - general_dealer: 3 dealers');
print('  - general: 6 listings');
print('  - general_category: 5 categories');
print('========================================\n');

print('Test data summary:');
print('  Listings by status:');
print('    - Active: 4');
print('    - Stub: 1');
print('    - Pending: 1');
print('  Listings by type:');
print('    - Private seller: 4');
print('    - Dealer: 2');
print('  Special cases:');
print('    - With photos: 1');
print('    - Rental: 1');
print('    - Price drop: 1');
print('    - Pending activation: 1');
print('========================================\n');

print('Ready for integration testing!');
