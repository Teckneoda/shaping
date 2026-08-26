# PAL Image Uploads Still Tied to Legacy CAPI — Features

## Architecture (working solution)

**Staged object + GraphQL commit** (per the [Photo Uploads Architecture design doc](https://app.notion.com/p/3c72ac5cb23580bdbb59f0a6719f9dd0) and the OPS-approved framing):

```
Browser ──(1) GraphQL get-signed-URL mutation────► marketplace-graphql ──► listing-side signed-URL endpoint
        ◄── signed POST policy {url, fields, storageKey}                  (GenerateSignedPostPolicyV4)
Browser ──(2) multipart POST file bytes──────────► private STAGING bucket (only non-GraphQL call)
Browser ──(3) GraphQL commit mutation (storageKey + position)─► marketplace-graphql
                └► listing-side commit endpoint: authz → image-http-rest (by object ref)
                   → write photo doc onto listing → synchronous response {url, renditions}
Staging object expires via bucket lifecycle rule.
```

Everything the front end sees stays the same in character: one commit call, synchronous result, URLs returned, explicit ordering, the same rendition contract. File bytes never travel through GraphQL.

> **HARD CONSTRAINT: all new endpoints live inside marketplace-backend.** No new endpoints in ksl-api or Capi (changing the *internals* of an existing legacy endpoint — e.g. shimming `storeListingImage` — is allowed; adding routes is not). Cars image uploads must be accomplished within marketplace-backend, not ksl-api.

---

## F1. Get signed URL (GraphQL `beginListingPhotoUpload` + listing-side endpoint)

- New mutation `beginListingPhotoUpload(input: {listingId, listingType, filename, contentType})` returning `{url, fields: JSON!, storageKey}` — named to match the existing convention (`beginProfileImageUpload`, `beginVideoUpload`, `beginJobApplyFileUpload`).
  - **A separate mutation, not a reuse of `beginProfileImageUpload`.** The profiles mutation ([mutation.profile.graphqls:19-20](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/schema/mutation.profile.graphqls#L19-L20), resolver [begin-profile-image.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/begin-profile-image.go)) can't serve listings: its input is only `mimeType` (no listing to authorize/count against), it targets the **Profiles image-upload service and its bucket/async pipeline** (`IMAGES_SERVICE_URL /image-upload/signed-url` with hardcoded `context: "profile"` — uploading there would trigger the profile attach subscriber, wrong bucket/lifecycle, no renditions), it has the side effect of creating a profile image-status doc, and its `SignedURLResponse` lacks the `storageKey` the commit step needs. GraphQL changes must be additive-only, so its input can't be extended. Reuse the *pattern* from `beginJobApplyFileUpload` instead; sharing a generic result type (`{url, fields, storageKey}`) across future flows is fine.
  - Model: `beginJobApplyFileUpload` — [mutation.job-apply-upload.graphqls](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/schema/mutation.job-apply-upload.graphqls), resolver [job-apply-upload.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/job-apply-upload.go)
  - Use `@hasRole(role: "MEMBER", useLowSecurity: true)` — sellers idle on the form (precedent documented in the jobs schema).
- New listing-side backend endpoint generates a **signed POST policy** (never a bare signed PUT — only a POST policy can cap size):
  - Model: [listing-jobs-http-rest storage.go:70-121](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-jobs-http-rest/internal/storage/storage.go#L70-L121) — `ConditionContentLengthRange`, `x-goog-meta-member-id` pinning, custom-time lifecycle.
  - Object key encodes the uploader: `staging/member/{memberId}/{uuid}` (service/admin scopes per design doc). Existing convention: `staging/{memberId}/{uuid}/{type}.{ext}` ([buildStorageKey](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-jobs-http-rest/internal/storage/storage.go#L208-L211)).
- **NEW private staging bucket** (required — the serving bucket `gcsb-ddm-images` is public-read with GET-only CORS: [google-storage.tf:11-42](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/media/services/image-http-rest/.tf/google-storage.tf#L11-L42)). TF model: [ksl-jobs-apply-staging bucket](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-jobs-http-rest/.tf/google-storage.tf#L31-L96) — uniform access, POST CORS with explicit ksl.com origin list (GCS CORS has no wildcards), lifecycle delete on `days_since_custom_time`, abort-incomplete-multipart rule.
- Enforce **photo-count limit and rate limit at the get-signed-URL step** (fail before the user spends upload bandwidth), and re-check at commit.
- Authorization at get-signed-URL AND at commit (listing may be deleted/sold/transferred in between).

## F2. Commit-by-reference (GraphQL + listing-side endpoint)

- New mutation committing `storageKey` (+ intended position, + optional description for Cars) to a listing; **synchronous** response carrying the final CDN URL, dimensions, and rendition set — the sell form displays the photo immediately from this response.
- Listing-side endpoint behavior (this intermediary is **the majority of the work**, required under every transport option):
  1. Verify caller may modify the listing — bouncer + ownership policy already exist: [validation_middleware.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/bouncer/validation_middleware.go), [policy.go:38-64](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/domain/policy.go#L38-L64)
  2. Verify the staged object — key format + double ownership check (key-derived memberId == caller AND object metadata matches): model [verifyStorageKeyFormat / verifyObjectOwnership](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-jobs-http-rest/internal/storage/storage.go#L213-L294)
  3. Invoke image-http-rest with the object reference + the vertical's rendition list (F3, F4)
  4. Write the photo doc onto the listing with atomic append semantics (legacy precedent: `$push` "so we don't overwrite photos added asynchronously" — [GeneralCollection.php:184-238](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Db/Mongo/GeneralCollection.php#L184-L238))
  5. Return per-image results (partial batch failure is normal: 8 uploaded, 3 fail)
- **Idempotent on the staged object name** — a double-click or retry commits once and returns the same image.
- Carry a correlation identifier from get-signed-URL through commit; signed-URLs-issued count vs commit count = abandonment-rate health metric.

## F3. image-http-rest: accept a source by reference

- Today the service accepts **multipart bytes only** (`r.FormFile("image")` — [app.go:266](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/media/services/image-http-rest/app.go#L266)); confirmed no object-ref or URL source exists. This is net-new work and the single highest-leverage change (serves browser path and, later, feeds).
- Add a **storage-object reference** input form `{bucket, object}` alongside multipart. Internal read primitive already exists: [storage.GetReader/ReadImage](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/services/media/shared-image-packages/storage/storage.go#L162-L194).
- **Multipart stays permanently** — required by: the Capi/ksl-api legacy shims (old mobile apps post multipart for years), server-generated bytes (e.g. jobs padding step), and dev/support/ops curl tooling.
- **External-URL form is deferred** (feeds optimization only; SSRF surface requiring host restrictions, internal-range and metadata-endpoint blocking, size caps, timeouts — see design doc §4/§5 and Q6).

## F4. Vertical-aware photo endpoints on listing-http-rest (the intermediary)

listing-http-rest has **no photo endpoints today** ([routes.go:20-41](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/routes.go#L20-L41)); reorder exists only as `PUT /listing/{id}` `photoOrder` ([update.go:296-299](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/domain/update.go#L296-L299)). It also has **no vertical concept**: the store is hard-bound to Mongo `classifieds.general*` ([mongo.go:13-37](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/store/mongo.go#L13-L37)) and every domain/handler interface is typed on `ClassifiedListing`. **Both verticals route through this service** (user decision), so Cars enters via a deliberate seam — not by teaching the Classifieds domain about Cars.

### The divergence seam (new `internal/photo` package)

```
routes.go  POST /listing/{id}/photo → handler (bouncer → types.Caller, unchanged)
                                          │
                             internal/photo/registry.go
                             PhotoService interface:
                               AddPhoto / EditPhoto / DeletePhoto / DeleteAllPhotos
                               (each impl owns its listing-ownership check)
                             Registry{ map[Vertical]PhotoService }
                                ├── CLASSIFIED → classifiedPhotoService  (Mongo classifieds.general + ImageClient)
                                └── CAR        → carPhotoService         (Mongo classifieds.auto + ImageClient
                                                                          + Public_CarsListingEvent publisher)
```

Design rules, each grounded in an existing in-repo pattern:
- **Registry keyed by a typed `Vertical` enum**, unknown → error. Copies the in-service `policy.Registry` idiom ([policy.go:19-36](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/policy/policy.go#L19-L36)) and dealer-http-rest's `VerticalUpdater` seam ([vertical_updater.go:10-13](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/dealer/containers/dealer-http-rest/domain/vertical_updater.go#L10-L13), [dealer_updater.go:12-53](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/dealer/containers/dealer-http-rest/domain/dealer_updater.go#L12-L53) — which shipped with the cars branch stubbed, proving the shape). Enum + legacy-string adapter copied from asset-http-rest ([asset.go:15-90](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/media/services/asset-http-rest/internal/types/asset.go#L15-L90)); normalize inbound `car|cars`→`CAR` like [listing-ps-update-video-url](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-ps-update-video-url/model/graphql.go#L219-L228).
- **Vertical is an explicit request field, never inferred** — the service has no way to infer it (no car documents in its store).
- **Do NOT route through `domain.ListingDomain` or the sidecar `Chain`** — both are hard-typed on `*types.ClassifiedListing` ([chain.go:14-27](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/sidecar/chain.go#L14-L27)); forcing a car listing into that type would leak Classifieds fields into the Cars path.
- **Ownership is per-impl**: Classifieds reads its own store (existing `policy.go` check); Cars resolves the owner via ksl-api (F6) — each returns the standard `ForbiddenError{ListingNotOwnerMsg}` so handler error-mapping stays unchanged.
- **Compile-time seam enforcement**: `var _ PhotoService = (*carPhotoService)(nil)` per impl (the trick feeds documents on its `UpstreamClient`).
- **Two source forms on AddPhoto/EditPhoto**: a staged `storageKey` (browser flow, F1–F2) or **multipart bytes** (service callers: the feed syncer, the Capi/ksl-api shims, the jobs-migration processor). Same intermediary, two byte-arrival paths.
- **Delete-all** endpoint alongside per-photo delete (feeds' `empty_destructive` path needs a home — see F8).

| Endpoint (new) | Replaces (legacy Capi) | Legacy reference |
|---|---|---|
| Add/commit photo (staged ref) | `POST /listings/{id}/photos` | [ListingController.php:1513](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ListingController.php#L1513) |
| Edit photo in place | `POST /listings/{id}/photos/{photoId}` | [ListingController.php:1612](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ListingController.php#L1612) |
| Per-photo delete | `DELETE /listings/{id}/photos/{photoId}` | [ListingController.php:1706](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ListingController.php#L1706) |
| Reorder (exists) | `PUT /listings/{id}` `photoOrder` | [ListingController.php:872-875](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/ListingController.php#L872-L875) |

- Per-photo delete also closes the known split where `deletePhoto` must always route to CAPI ([legacy-listing.go:371-385](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/legacy-listing.go#L371-L385) — the comment explicitly anticipates this endpoint).
- **Edit-in-place** preserves current semantics: fetch the original from GCS + the edited bytes → image-http-rest (original as `image`, edited as `renditionsImage`) → new imageId/URL **is** the cache-busting rename → merge photo doc at the same index, stamp `cropMD5`/`userEdit`/`cropTime` → async-delete old files. Legacy behavior: [ImageHelper::editImageToImageApi :432-487](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Helper/ImageHelper.php#L432-L487). Note: the browser sends **only the edited JPEG**; the "two files" are assembled server-side (verified — corrects the design doc's premise).
- **Rendition-list selection moves here.** Recipes/geometry already live in [rendition-recipes.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/media/services/image-http-rest/domain/renditions/rendition-recipes.go); the per-vertical *chooser* moves out of the legacy repos, which today hold three divergent copies:
  - Capi (7): [S3ImageUploader.php:16-33](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Service/S3ImageUploader.php#L16-L33)
  - ksl-api General (6 — **missing `classified/adPic1`**): [ListingController.php:36-48](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/general/api/controllers/ListingController.php#L36-L48)
  - ksl-api Cars (11, inline): [ListingController.php:2519-2538](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/cars/api/controllers/ListingController.php#L2519-L2538)
- Retiring the PHP write path eventually removes the do-not-remove BSON shims for PHP's empty-array `renditions` quirk ([listing.go:901-929](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/types/listing.go#L901-L929) — "can be removed when PHP retires — but not before").

## F5. Frontend PAL migration (marketplace-frontend)

- Swap the two allowlisted legacy server actions to the new mutations, behind a rollout gate:
  - [addPhoto.ts](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/sell/%5B%5B...id%5D%5D/actions/addPhoto.ts) → get signed URL + direct GCS POST + commit (upload pattern exists in [useUploadSlot.ts:74-120](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/listing/%5Bid%5D/components/Contact/useUploadSlot.ts#L74-L120) and PAL's own video uploader)
  - [updatePhoto.ts](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/apps/ksl-marketplace/app/sell/%5B%5B...id%5D%5D/actions/updatePhoto.ts) → new edit mutation
  - DR-009 lists both as temporary exceptions scheduled for exactly this migration ([009-external-api-graphql-routing.md](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-frontend/.decisions/009-external-api-graphql-routing.md))
- Behavior to preserve (all verified in current code):
  - jpeg/png/gif, 10MB client cap; per-image failure handling; blob-URL preview + spinner until real URL
  - 3-concurrent upload queue with stable tile order; index 0 = main image (4:3 crop lock)
  - Stepper blocks "Next" while uploads are in flight
  - Sell form displays `?filter=classified/adPic1` (fallback `classified/mobile_adPic1`) — the commit response must return URLs for which this rendition already exists
- Delete and reorder are already on GraphQL (`deletePhoto`, `updateListing.photoOrder`) — unchanged, though commit should return whatever identity `photoOrder`/`deletePhoto` need (see Q3).
- Fixes-by-replacement: the latent `memberId`=listingId bug in addPhoto.ts:40 disappears with the action.

## F6. Cars support (goal #2 — native in listing-http-rest, direct write to `classifieds.auto`)

Same get-signed-URL mutation and staging bucket; same commit mutation and endpoint — the divergence lives inside listing-http-rest (the F4 registry), not in GraphQL and not in a separate service (resolves Q5). Synchronous, because the shared PAL Media component gives Cars the same must-display-immediately UX. **Per the hard constraint, no new ksl-api endpoints: `carPhotoService` performs the Cars write-back itself.** Research made this feasible and bounded:

- **Cars listings live in `classifieds.auto` on the SAME Mongo cluster + database listing-http-rest already uses** (`mplace-mongo.ksl.com/classifieds` — [boosts cron maps cars→`auto`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-cron-boosts/app.go#L64-L69); [auto-renew reads `general,auto` in prod](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-cron-auto-renew/.tf/kubernetes-deploy.tf#L29-L30)). Adding the collection is one line on the existing client; only a **write grant** for the service's Mongo user is new (Q16).
- **Elasticsearch sync is free**: the cars ES index (`cars-listings`) is fed by a Mongo **change-stream connector** watching `auto` ([m-ksl-cars-api connector, `fullDocument: updateLookup`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-cars-api/connector/src/change-identifier.js#L36-L41)) — **not** by Pub/Sub. Correct Mongo writes propagate to ES on their own; never write ES directly (the connector's merge would clobber it).

**`carPhotoService` operations** (full side-effect map from the [storeListingImage walk :2445-2645](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/cars/api/controllers/ListingController.php#L2445-L2645) — no dealer counters, no modifyTime, no memcache bust on photo add):
1. **Ownership natively**: `findOne` on `auto` (criteria: 40-hex id → `{backlot.auctionId}`, else `{id: int}`), compare the doc's `memberId` to the caller. No ksl-api read needed — resolves Q13.
2. **image-http-rest** with the staged ref, matching the legacy call exactly: `vertical: 'classifieds'` (yes — even for cars), **`objectId` = the auctionId string for Backlot** (the generated filename encodes it and `isBacklotPhoto` filtering depends on it), the Cars 11-rendition list. Compute **`preMd5` = MD5 of the raw staged bytes before processing** — feeds dedupe on it ("do not remove without written consent from the feeds person").
3. **Write-back**: one `findOneAndUpdate` (ReturnDocument: After, 3 attempts / 1s apart): `$push` the exact **10-field cars photo doc** — `id, upload_time (BSON date, snake_case), extension, md5, preMd5, height, width, description, originalFilePath, originalFileName`; **no `filterArray`** (that's Classifieds vocabulary) — plus `backlot.photoOrder` in the same update when the listing has `backlot`. Never touch `modifyTime`/`displayTime`/counters (bumping modifyTime re-sorts SRP and re-partitions BigQuery).
4. **Publish `Public_CarsListingEvent`** (project `ddm-platform`; binary `cars.v4.Listing` built from the post-update doc, with PubSubVehicle's whitelist semantics: status/newUsed/titleType uppercased, sellerType→DEALERSHIP|FSBO, all times epoch-ms, `backlot` excluded; swallow publish errors like legacy does). This feeds **BigQuery + Google Shopping + dealer-url-scraper — not ES**; skipping it delays Shopping eligibility for a listing's first photo. Needs publisher IAM on the externally-owned topic and a full listing→proto mapping layer that doesn't exist in Go yet (Q17). The 10-field photo doc maps 1:1 onto `cars.v4.Listing.Photo` — no proto change needed.
5. **History**: insert into `classifieds.autoChangeLog` when status ∈ {Active, Moderate, Stub} (audit parity — cheap, recommended).
6. **Edit (replace-at-index)**: delete old bytes first (GCS URLs → `image-batch-delete`; legacy S3 URLs → `photosToDelete` queue), then **one atomic pull+push in a single `findOneAndUpdate`** — two round trips would let the change stream observe a transiently empty `photo[]` and blank the ES photos. The pull must also pull `backlot.photoOrder` (else Backlot ordering silently breaks), and lookups must tolerate http↔https drift on stored ids. The replacement doc keeps the 10-field cars vocabulary — no `cropMD5`/`userEdit` (Q18) — so no proto change here either.
7. Return the image URL + renditions synchronously.

Delete and reorder stay on ksl-api's **existing** endpoints via GraphQL (unchanged — not new endpoints, so allowed); they can migrate to native writes later. Mixed writers on the same `photo` array are safe under Mongo single-document atomicity (the same argument already relied on for Capi + listing-http-rest sharing `classifieds.general`).

**Caution recorded (feeds into Q17):** two marketplace-backend teams previously stopped short of direct cars writes — boosts cron proxies cars to ksl-api ("Cars has extra dealer logic on the ksl-api endpoint", [booster.go:24-26](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-cron-boosts/booster.go#L24-L26)) and dealer-http-rest's cars updater is written but commented out ("We're not ready to process Car updates yet", [dealer_updater.go:44-54](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/dealer/containers/dealer-http-rest/domain/dealer_updater.go#L44-L54)). For **photo adds specifically** the side-effect surface is now exhaustively mapped (steps 1–7 above), but confirm with the Cars team that nothing outside the repos depends on cars photo writes flowing through PHP.

**Fallback (de-risked stepping stone, recorded not recommended):** the commit endpoint stays in listing-http-rest but internally posts the bytes to ksl-api's *existing* `storeListingImage` — satisfies the letter of the constraint and keeps PHP side effects, but keeps cars uploads flowing through ksl-api, adds a processing hop, and provides no real edit.

**Cars photo editing is a live requirement, not a simplification.** An unmerged frontend branch (`feature-pal-use-new-photo-editor-sc-392495`, commit 3b349abc1, 2026-08-26, no PR yet) enables the PAL photo editor for Cars behind Remote Config flag **`CAR_pal_photo_editor`** (allowlist `CAR_pal_redesign_allowed_ids`, cars **stepper** flow only). Because no server-side Cars edit exists, it **fakes replace-in-place client-side**: `replaceCarPhoto()` = `addPhoto` → `deletePhoto` → `savePhotoOrder`, tolerating partial failure (`status: 1` plus a warning when the original couldn't be deleted, leaving a duplicate for the user to remove). The new path's `EditPhoto` on `carPhotoService` (image-http-rest original+edited → new URL → atomic pull+push at the same index, step 6 above) gives Cars a **real, atomic replace** and retires the fake — coordinate with sc-392495 (Q14).

The **async subscriber alternative** (staging-bucket OBJECT_FINALIZE → Pub/Sub → attach subscriber, template [listing-ps-update-video-url](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-ps-update-video-url/app.go#L86-L146)) remains recorded but rejected for the interactive path (no synchronous feedback). ksl-api `storeListingImage` **keeps serving old mobile apps completely unchanged** — it already calls image-http-rest, and mixed writers are safe (see above) — so ksl-api needs zero changes for cars.

## F7. Legacy shim + rollout

- Capi `POST /listings/{id}/photos` **stays alive for years** for old mobile app versions, internally shimmed to the new path (Capi already holds the bytes → multipart form of image-http-rest; staging a bucket round-trip would be pointless). ksl-api `storeListingImage` stays alive too but needs **no changes at all** — it already writes `classifieds.auto` + calls image-http-rest, and the new native writer coexists safely (single-document atomicity).
- Rollout mirrors the Capi→listing-rest prior art: Firebase Remote Config gate (`use_listing_rest` family — [gate.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/services/listingrestgate/gate.go)), member allowlist → 5% → 25% → 50% → 100% with bake periods, gate degrades to kill switch ([specs/016 quickstart](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/specs/016-classifieds-dp-listing-rest/quickstart.md)). Web sell form before mobile.
- Behavior that must be preserved across rollout: MD5 fields on photo docs, cache-busting rename on edit, the full existing rendition set and URL contract.

## F8. Feed-system-ready endpoint contract

The feed system's migration off Capi photo upload is **already designed and waiting on this project** — its specs say so explicitly: *"when the Listing Service exposes a photo endpoint in a later tier, only capi.go is swapped out"* ([specs/010 plan.md:201](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/specs/010-feed-system-p1-skeleton/plan.md#L201)), and both its dispatch seam ([upstream.go:58-64](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/feeds/services/feeds-ps-syncer/internal/routing/upstream.go#L58-L64)) and its ksl-api client ([kslapi/client.go:8-13](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/feeds/services/feeds-ps-syncer/internal/kslapi/client.go#L8-L13)) document themselves as one-line-swap bridges. The feed migration itself is a later phase; **the F4 endpoints must satisfy this contract now** so it isn't precluded:

1. **Add** accepts multipart bytes + filename + **`originalFilePath`** (dealer source URL — must round-trip verbatim; it is the feed diff key) + optional `memberId` (server asserts envelope-vs-listing agreement). Returns a non-empty canonical URL + photo id.
2. **Ordering**: appended-in-call-order, first = primary (or an explicit position — strictly better). Feeds uploads strictly sequentially per listing to preserve this.
3. **Read-back**: `GET /listing/{id}` keeps returning `photo[].id` **and** `photo[].originalFilePath` ([listingservice.go:236-239](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/feeds/services/feeds-ps-syncer/internal/routing/listingservice.go#L236-L239); spec 011 FR-130).
4. **Reorder**: keep honoring `PhotoOrder []string` on `PUT /listing/{id}`.
5. **Delete**: per-photo delete + delete-all (feeds' `empty_destructive` path). Bonus: per-photo delete + explicit ordering lets feeds' **destructive nuke-and-reupload collapse into a targeted diff**, eliminating the `PhotoDeleteFailed` mixed-state hazard its executor deliberately doesn't retry ([executor.go:409-415](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/feeds/services/feeds-ps-syncer/internal/domain/executor.go#L409-L415)).
6. **Errors**: clean 4xx-terminal / 5xx-retriable split, no substring matching; structured reasons fix today's "Capi collapses the image service's reason into a generic 500" ([outcome.go:254-267](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/feeds/services/feeds-ps-syncer/internal/types/outcome.go#L254-L267)).
7. **Auth**: `Authorization: ddm-jwt <serviceJWT>` — the credential feeds already uses for every other listing-http-rest call (service role → privileged, ownership check skipped). Pure simplification: retires feeds' `CapiAuth` (~180 lines) and `internal/kslapi/` (~290 lines) plus the `KSL_API_PERSISTENT` secret.
8. **Limits**: body cap ≥ feeds' 10MB fetch cap (note the existing 10MB-fetch vs 25MB-Capi mismatch worth rationalizing); vertical is always `CLASSIFIED` — the feed system has zero Cars code ([artifact/types.go:114-177](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/feeds/services/feeds-ps-syncer/internal/artifact/types.go#L114-L177)).

Bonus payoff: the **jobs-migration processor copies feeds' Capi photo upload verbatim** ([specs/017 research.md:85](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/specs/017-migrate-jobs-listings/research.md#L85)), so this endpoint retires **two** Capi photo callers, not one. Source-URL ingestion (image-http-rest fetching the dealer URL itself) remains a separate, measure-first decision (Q6).

## F9. Explicit non-goals

- **Feeds do not use the staged-upload path** — deliberate decision, recorded so nobody "unifies" it later. feeds-ps-syncer holds bytes server-side; routing via staging adds two hops per photo. Feeds will use the **multipart-bytes form** of the F4 endpoints instead — see F8 for the contract.
- Listing video URLs out of scope (video pipeline already modernized).
- Dealer logo upload (still on S3 — [DealerController.php:46-98](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Controller/DealerController.php#L46)) out of scope.

---

## Nice-to-have additions (not required scope, not open questions)

Pre-existing image-http-rest defects surfaced during research — cheap to pick up while builders are in the service:

1. **20MB cap is likely dead code** — `getUploadParams` parses the form (Go's 32MB default) before `MaxBytesReader` attaches ([app.go:221](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/media/services/image-http-rest/app.go#L221) vs [:257-263](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/media/services/image-http-rest/app.go#L257-L263)).
2. **MD5 is computed on standardized bytes** (post-resize/HEIC-convert), not the original upload ([app.go:307-309](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/media/services/image-http-rest/app.go#L307-L309)) — document or align; note GCS provides `md5Hash` on staged objects for free.
3. **Response key drift**: upload returns `rendition`, GET returns `renditionName` for the same field.
4. **PATCH `/image/{id}/renditions` 400s for service JWTs** (memberId 0 hard-rejected; [app.go:663-674](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/media/services/image-http-rest/app.go#L663-L674)) and re-cuts from the main image so it can't reproduce an edit crop.
5. **Batch delete is a sequential loop** of single Pub/Sub publishes ([app.go:562-614](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/media/services/image-http-rest/app.go#L562-L614)).
6. **Capi stores width/height swapped in Mongo** ([ImageHelper.php:135-136](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Helper/ImageHelper.php#L135-L136)) — the new write path should store them correctly (and note existing data may be swapped).
7. **ksl-api General rendition list is missing `classified/adPic1`** — the rendition PAL displays — while feeds upload through ksl-api. Likely the root cause of feed-sourced listings showing broken photos in PAL (matches the reverted `filterArray` fix, sc-389434). Cheap immediate fix independent of this project: add `classified/adPic1` to that list (+ decide on backfill via PATCH renditions).
