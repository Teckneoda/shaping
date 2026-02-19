.PHONY: help start stop setup reset cleanup verify test

# Default target
help:
	@echo "Integration Testing Setup - Available Commands"
	@echo "=============================================="
	@echo ""
	@echo "Database Management:"
	@echo "  make start      - Start MongoDB container"
	@echo "  make stop       - Stop MongoDB container"
	@echo "  make setup      - Seed test database"
	@echo "  make reset      - Reset database (remove test data)"
	@echo "  make cleanup    - Drop entire test database"
	@echo "  make verify     - Verify database setup"
	@echo ""
	@echo "Testing:"
	@echo "  make test       - Run integration tests (Phase 2+)"
	@echo ""
	@echo "Full Workflow:"
	@echo "  make start      # Start MongoDB"
	@echo "  make setup      # Seed database"
	@echo "  make verify     # Verify setup"
	@echo "  make test       # Run tests"
	@echo "  make reset      # Clean up between test runs"
	@echo ""

# Start MongoDB in Docker
start:
	@echo "Starting MongoDB..."
	docker-compose -f docker-compose.minimal.yml up -d
	@echo "Waiting for MongoDB to be ready..."
	@sleep 5
	@docker-compose -f docker-compose.minimal.yml ps

# Stop MongoDB
stop:
	@echo "Stopping MongoDB..."
	docker-compose -f docker-compose.minimal.yml down

# Stop and remove volumes
stop-all:
	@echo "Stopping MongoDB and removing volumes..."
	docker-compose -f docker-compose.minimal.yml down -v

# Seed the database
setup:
	@chmod +x scripts/setup-db.sh
	@./scripts/setup-db.sh

# Reset database between test runs
reset:
	@chmod +x scripts/reset-db.sh
	@./scripts/reset-db.sh

# Cleanup database completely
cleanup:
	@chmod +x scripts/cleanup-db.sh
	@./scripts/cleanup-db.sh

# Verify database setup
verify:
	@chmod +x scripts/verify-db.sh
	@./scripts/verify-db.sh

# Full setup (start + seed + verify)
full-setup: start
	@sleep 5
	@make setup
	@make verify

# Run integration tests (to be implemented in Phase 2)
test:
	@echo "Integration tests not yet implemented (Phase 2)"
	@echo "Run: go test ./tests/integration/... -tags=integration"

# Quick start for development
dev: full-setup
	@echo ""
	@echo "Development environment ready!"
	@echo "MongoDB: mongodb://localhost:27017/classifieds_test"
	@echo ""

# Clean slate (cleanup + start + setup)
fresh: stop-all
	@sleep 2
	@make full-setup
	@echo ""
	@echo "Fresh database setup complete!"
	@echo ""
