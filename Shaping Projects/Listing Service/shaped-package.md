# Listing Service — Shaped Package

## Overview

The Listing Service is the new validation gateway and persistence layer for marketplace listings. It replaces the existing CAPI listing operations for the Post-a-Listing (PaL) flow, starting with General Classifieds. The service validates all incoming data and either accepts it for storage or rejects it with clear error messages. Data enrichment (geocoding, dealer info, phone normalization, etc.) happens through a series of processing steps alongside the core save operations.

The core **Create Listing** endpoint is complete. This package covers everything remaining to deliver a fully functional service.

---

## What's Already Done

- Project setup, scaffolding, and deployment configuration
- All shared data types and validation error structures
- Authentication middleware
- **Create Listing** — Users can create a draft listing and receive a unique listing ID
- Dealer limit enforcement on create (prevents users from exceeding their allowed listing count)
- Event publishing for listing create operations

---

## Remaining Work

### 1. Get Listing

**As a consumer of the API**, I want to retrieve a listing by its ID so that I can display or process listing data.

**As an unauthenticated visitor**, I want contact information to be hidden from me so that seller privacy is protected.

**As an authenticated listing owner or admin**, I want to see the full listing including all contact details so that I can manage my listing.

**As an active dealer**, I want my business contact information to be visible to potential buyers even when they are not logged in, so that leads can reach me.

---

### 2. Update Listing

**As a listing owner**, I want to update specific fields on my listing without touching others, so that I can refine my listing over time without losing unchanged data.

**As a listing owner**, I want to receive immediate, clear feedback when my data is invalid, so that I can correct it before submitting.

**As a listing owner**, I want to attach spec fields (custom attributes specific to my listing's category) to my listing, so that buyers can filter and find it more easily.

**As the system**, I want to prevent owners from changing the core listing type (category, market type) once a listing is active, so that downstream systems and buyers are not misled by sudden classification changes.

---

### 3. Request Activation

**As a listing owner**, I want to submit my completed listing for activation, so that it can be reviewed and made publicly visible.

**As the system**, I want to validate that all required fields are present and correct before allowing a listing to enter the activation queue, so that only complete and valid listings proceed.

**As the system**, I want to enforce dealer slot limits and category-specific posting restrictions at activation time, so that per-account rules are consistently applied.

**As the system**, I want to verify that the member has a valid payment method or exemption on file before queuing the listing, so that unpaid listings do not enter the activation pipeline.

---

### 4. Activate Listing

**As the fraud validation service**, I want to call an activate endpoint after a listing passes fraud review, so that I can transition it to fully active and visible status.

**As the system**, I want to re-validate all listing fields at activation time, so that any changes made between request-activation and activation do not result in an invalid active listing.

**As a downstream consumer**, I want to receive a public event when a listing becomes active, so that search indexes, notifications, and other systems can react in real time.

---

### 5. Location Enrichment (Sidecar)

**As a listing owner**, I want to enter just my zip code and have my city and state auto-populated with the correct, standardized name, so that my listing appears correctly in location-based searches.

**As the system**, I want to geocode listing locations to lat/lon coordinates, so that distance-based search and map features work accurately.

---

### 6. Dealer Data Enrichment (Sidecar)

**As a dealer**, I want my listing's contact information to automatically reflect my dealership's transfer phone numbers, so that inbound leads are routed correctly without me having to enter them manually.

**As the system**, I want to populate dealer business info on dealer-owned listings, so that buyer-facing displays show accurate dealer context.

---

### 7. Description Markdown Processing (Sidecar)

**As a listing owner**, I want to write my listing description using basic Markdown formatting (bold, lists, etc.), so that I can make my listing easier to read.

**As the system**, I want to convert Markdown descriptions to plain text before saving, so that downstream consumers receive clean, display-ready text.

---

### 8. Phone Number Normalization (Sidecar)

**As the system**, I want to normalize all phone numbers to the international E.164 format before storing them, so that phone data is consistent and usable for contact and fraud detection purposes.

---

### 9. Member Verification Status (Sidecar)

**As a buyer**, I want to see whether a seller is a verified member, so that I can make more informed decisions about who I am engaging with.

**As the system**, I want to look up and persist the seller's verification status when a listing is created or updated, so that the listing record always reflects current verification state.

---

### 10. YouTube Video Parsing (Sidecar)

**As a listing owner**, I want to paste a YouTube link into my listing, so that I can showcase a video of the item I'm selling.

**As the system**, I want to parse the YouTube URL and store a structured video object, so that the video can be consistently rendered on listing detail pages.

---

### 11. Email Canonicalization (Sidecar)

**As the system**, I want to generate a canonical version of each seller's email address, so that fraud detection and duplicate account checks work reliably regardless of email aliasing or formatting variations.

---

### 12. Media Video Asset Cleanup (Sidecar)

**As the system**, I want to delete video assets from the video service when they are removed from a listing, so that orphaned files do not accumulate in storage.

---

### 13. Observability, Polish & Deployment Readiness

**As an on-call engineer**, I want distributed traces and structured logs at every layer of the service, so that I can diagnose issues quickly in production.

**As a developer**, I want a clear README with setup instructions and an API reference, so that I can onboard and contribute without friction.

**As the engineering team**, I want all tests passing and linting clean before the service ships, so that we deploy with confidence.

---

## Out of Scope for This Package

- Jobs, Cars, and Homes listing types (architecture is designed to support them; implementation is a future phase)
- Frontend / GraphQL changes
- Migration of existing listings from CAPI

---

## Open Items

*(To be filled in — extra pieces to be added here)*
