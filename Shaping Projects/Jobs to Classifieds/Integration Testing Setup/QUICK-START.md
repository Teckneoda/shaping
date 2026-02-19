# Quick Start Guide

## 🚀 Get Started in 3 Steps

### 1️⃣ Start MongoDB
```bash
make dev
```
This starts MongoDB and seeds the test database.

### 2️⃣ Verify Setup
```bash
make verify
```
Confirms all test data is loaded correctly.

### 3️⃣ You're Ready!
```
✅ MongoDB: mongodb://localhost:27017/classifieds_test
✅ 6 test listings loaded
✅ 3 test dealers loaded
✅ 5 categories loaded
```

## 📋 Common Commands

| Command | Purpose |
|---------|---------|
| `make start` | Start MongoDB only |
| `make setup` | Seed database |
| `make reset` | Reset between tests |
| `make verify` | Check database |
| `make stop` | Stop MongoDB |
| `make fresh` | Clean slate |

## 🔍 Quick Checks

### View Test Listings
```bash
mongosh classifieds_test --eval "db.general.find({}, {id:1, title:1, status:1}).pretty()"
```

### View Test Dealers
```bash
mongosh classifieds_test --eval "db.general_dealer.find({}, {memberId:1, dealerName:1}).pretty()"
```

### Check ID Sequence
```bash
mongosh classifieds_test --eval "db.idTracker.findOne({_id: 9})"
```

## 🧪 Test Data IDs

**Test Listings:**
- `100` - Basic active listing
- `23456789` - Dealer listing with photos
- `61111111` - Rental listing
- `200` - Stub (draft)
- `300` - Price drop example
- `400` - Pending activation

**Test Dealers:**
- `2345678` - Southern Idaho RV (500 limit)
- `12345` - Wayne Enterprises (15 limit, phone override)
- `9876543` - Local Family (no limit)

**Test Users (JWT):**
- `2615897` - Jimmy Donaldson (standard user)
- `999999` - Admin User (admin)

## 🐛 Troubleshooting

### MongoDB won't start?
```bash
make stop
make start
```

### Database corrupted?
```bash
make fresh
```

### Need help?
```bash
make help
```

Or read the [full README](./README.md)

## 📚 Documentation

- [README.md](./README.md) - Full documentation
- [Integration Testing Plan.md](./Integration%20Testing%20Plan.md) - Master plan
- [PHASE1-COMPLETE.md](./PHASE1-COMPLETE.md) - Phase 1 summary

## ⚡ Next Steps

Phase 1 ✅ Complete - Database setup done!

**Coming in Phase 2:**
- Go test framework
- HTTP clients for CAPI and listing-http-rest
- Response comparison utilities
- Actual integration tests

## 💡 Tips

1. **Always reset between test runs**: `make reset`
2. **Verify after changes**: `make verify`
3. **Use fresh for clean slate**: `make fresh`
4. **Check Makefile for all commands**: `make help`

---

**That's it!** You're ready to start building integration tests. 🎉
