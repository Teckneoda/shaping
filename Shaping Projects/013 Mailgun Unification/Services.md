# Mailgun Unification — Services

Full inventory of transactional email senders, the pipeline they use today, and the code locations that change. Line numbers reflect the 2026-09-02 sync of the local checkouts.

## Mechanism legend

| Code | Meaning | Migration need |
|------|---------|----------------|
| **ENDPOINT** | Calls `POST https://api.ddm.io/emailer-queue` | None (target state) |
| **PUBSUB** | Publishes directly to the `Public_SendEmail` topic | Move to ENDPOINT |
| **DDM-LIB** | Uses `deseretdigital/email` (`AdapterFactory::getAdapter('mandrill', …)`) → direct Mandrill | Migrate (via F3 adapter) |
| **MANDRILL-SDK** | Direct Mandrill/Mailchimp-Transactional SDK or raw API | Migrate |
| **MAIL()** | Raw PHP `mail()` | Decide: queue or Slack/Datadog |
| **PHPMAILER** | PHPMailer via local MTA | Migrate |
| **PROXY** | Calls a ksl-api / CAPI email endpoint; sends nothing itself | Free when its target migrates |
| **DEAD** | No live sender; leftover config/secrets/code | Cleanup only |

---

## 1. Pipeline reference (current state)

### Consumer — [`ksl-emailer-queue`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue)
- `emailer-mandrill-transactional`: Cloud Function gen2 (Node 20/TS), Eventarc-bound to `Public_SendEmail`. Handler: [index.ts](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue/emailer-mandrill-transactional/src/index.ts).
- Provider routing: [getSender.ts](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue/emailer-mandrill-transactional/src/senders/getSender.ts) + [messageHandler.ts](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue/emailer-mandrill-transactional/src/messageHandler.ts). Prod config pins `ROLLOUT_PERCENTAGE=1` → Mailgun is selected 100% of the time. Then the from-domain whitelist applies: exact match on `ksl.com`, `utah.com`, `thememories.com` ([getValidDomains.ts](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue/emailer-mandrill-transactional/src/helpers/getValidDomains.ts)); all other domains go to Mandrill. Default from: `noreply@ksl.com`.
- Message contract: [pubsub-email.ts](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue/emailer-mandrill-transactional/src/types/pubsub-email.ts) (hand-written; snake and camel case accepted via [standardizeMessageFields.ts](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue/emailer-mandrill-transactional/src/helpers/standardizeMessageFields.ts)).
- Known defects: see Features.md F1. The topic has no Pub/Sub schema and no dead-letter queue. Dedupe is a fail-open Firestore lookup. No APM.
- `messages-email-notifications` (GKE, same repo): consumes `Private_SentMessageEventV2` (protobuf schema, DLQ after 5 attempts), renders MJML, publishes `{recipients, subject, body}` to the topic. Highest-volume producer. Upstream: [messages-service](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/messages-service).

### Central endpoint — [`ksl-emailer-queue-endpoint`](https://github.com/deseretdigital/ksl-emailer-queue-endpoint)
- Go. `POST /emailer-queue` (multipart form) → validates → publishes `emails/v1` protobuf to the topic. Routed at `api.ddm.io` (ddm-platform ingress).
- Auth: member JWT (`Bearer`) or service token (`ddm-jwt`, added 2026-06-16).
- Form fields (openapi.yml): `subject`*, `recipient`* (repeated JSON `{email,name}`), `body`, `plain_text`, `from_email` (DDM-owned domain), `from_name`, `reply_to`, `template`, `template_variables` (JSON string), `isolate_recipients`, `attachment` (repeated file). To verify: `tags`, `delivery_time` (needed by Tier B senders).
- TSP approved 2024-02-15; Buyer team owns it.

### Contract — [`ddm-protobuf`](https://github.com/deseretdigital/ddm-protobuf) `proto/emails/v1/email_message.proto`
- 14 fields: subject, body, recipients{email,name}, from_email, from_name, reply_to, attachments{filename,type,content(base64)}, timestamp, plain_text, tags[], template, template_variables (JSON string), delivery_time, isolate_recipients.
- No cc/bcc, no per-recipient variables, no inline-image content_id.
- The topic does not enforce this schema. Publishers split between `json.Marshal` (snake_case) and `protojson.Marshal` (camelCase); the consumer papers over the split with a hand-maintained shim.
- The local checkout is stale (behind 11, dirty) and predates `isolate_recipients`. Repo pins differ across marketplace-backend and marketplace-graphql.

---

## 2. Core email pipeline repos (required)

### ksl-api — [`Legacy/ksl-api`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api)

Topology note: `public_html/classifieds/homes` and `public_html/classifieds/jobs` are symlinks into `m-ksl-homes/site-api` and `m-ksl-jobs/site-api`. Those controllers are counted under their own repos.

Pub/Sub plumbing: [PubSubEmail.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/common/api/classes/PubSub/PubSubEmail.php#L11-L26) — topic const, `$SEND_THROUGH_MAILGUN = true`, and `shouldSendThroughMailgun()` which allows **only `cars` and `classifieds`**. Every other vertical falls to Mandrill.

**General** — [EmailController.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/general/api/controllers/EmailController.php)

| Method | Line | Mechanism | Purpose |
|---|---|---|---|
| sendNewAdEmail | 240 | PUBSUB + DDM-LIB fallback | "Thanks for posting" (tags listing-create) |
| sendAbuseEmail | 433 | PUBSUB + DDM-LIB fallback | abuse notices |
| sendEmailToAdOwner | 578 | PUBSUB + DDM-LIB fallback | buyer→seller contact |
| sendMandrillEmail | 781 | **DDM-LIB only** | generic sender/fallback (key literal at 784) |
| sendMandrillEmailJSON | 828 | **DDM-LIB only** | public arbitrary-payload endpoint; external callers: m-ksl-generalfeeds, m-ksl-classifieds |
| sendMandrillEmailLimitReached | 843 | PUBSUB + fallback | dealer posting limit |
| sendAutoAssignedFeaturedEmail | 938 | **DDM-LIB only** | auto-featured listing notice |
| sendListingAlertEmail | 1044 | PUBSUB + fallback | saved-search alerts (fallback at 1118) |

**Cars** — [EmailController.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/cars/api/controllers/EmailController.php)

| Method | Line | Mechanism | Purpose |
|---|---|---|---|
| _sendEmailPriceIsLower | 273 | PUBSUB | internal low-price alert |
| sendEmailToAE | 338 | **DDM-LIB only** | AE spend notification |
| sendEmailToAdOwnerMandrill | 458 | PUBSUB + fallback | email seller |
| sendNewAdMandrillEmail | 603 | PUBSUB + fallback | listing confirmation |
| sendUserToUserMandrillEmail | 1004 | PUBSUB + fallback | user-to-user |
| sendSavedSearchesReport | 1100 | PUBSUB + fallback | monthly report |
| sendMandrillExpireEmail | 1212 | PUBSUB + fallback | expiration warning |
| sendWantToListInventoryEmail | 1284 | PUBSUB + fallback | dealer inventory interest |
| sendMandrillEmail | 1363 | DDM-LIB | shared fallback (key literal at 1370) |
| sendClientDashboardEmail(s) | 1417/1475 | PUBSUB | dealer dashboard |
| sendContactInfoUpdatedEmail | 1502 | PUBSUB + fallback | contact info updated |
| sendAdfPhoneContactMandrill | 1704 | **DDM-LIB only** | ADF phone/text leads (batch driver: scripts/sendAdfPhoneContactEmail.php:127) |
| _sendAdfEmail | 1753 | PUBSUB | ADF XML lead |
| sendListingAlertEmail | 1985 | PUBSUB + fallback | saved-search alerts |
| _sendStatusEmail | 2449 | PUBSUB + fallback | price drop / expiring favorites |

**Other ksl-api senders**

| Location | Mechanism | Purpose |
|---|---|---|
| [common EmailController sendFeedbackEmail:54-146](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/common/api/controllers/EmailController.php#L54-L146) | **DDM-LIB only** | site feedback (key literal at 125) |
| [MandrillEmailHelper.php:15-50](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/library/MandrillEmailHelper.php#L15-L50) | DDM-LIB | static helper; **key literal at line 20** |
| [HomieEmailHelper.php:74,131](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/library/Classifieds/Homes/HomieEmailHelper.php#L74) | DDM-LIB | Homie realtor leads |
| PickemController:536; PickemAdminController:446, 561, 645, 886, 956 | DDM-LIB | six Pick'em senders (key literals; also committed sports/v2/mandrill.ini) |
| ReportThisAdController:156-186 | DDM-LIB | ad feedback (key from config — good pattern) |
| IwitnessController:503; EmailNotificationHandler:37; GeneralNotification:71; CommonError:25 | MAIL() | ops/error alerts |
| alerts/v1 workers (AlertWorker:155-182, AlertTrait, MatchTrait) | PROXY | saved-search alert drivers → per-vertical email endpoints |
| members BrontoController (both versions) | DEAD | all methods return "No longer available"; composer still pulls bronto-api-php-client |
| MemberController forgotPassword:419 / resendActivation:445 | EXTERNAL | delegates to member-api (outside these repos — confirm path separately) |

### m-ksl-classifieds-api (CAPI) — [`Legacy/m-ksl-classifieds-api`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api)

All sends are direct Mandrill SDK. Key arrives via Symfony secret `MAILER_DSN` (no literal).

| Location | Mechanism | Purpose |
|---|---|---|
| [MandrillWrapper.php:69-96](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Library/Mandrill/MandrillWrapper.php#L69-L96) | MANDRILL-SDK | core sender (send at 94) |
| [TemplateEmailSender.php](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-classifieds-api/src/Service/TemplateEmailSender.php) 56 / 87 / 110 / 229 / 313 | MANDRILL-SDK | price drop; seller expiration; buyer expiration; thank-you (stale `utm_source=ddm-bronto` at 251-254); dealer monthly report |
| Callers: PriceDropController:230, ExpirationController:183/311, ListingController:1294, DealerMonthlyStatEmail:177 | — | routes `/price-drop/notifications`, `/expiration/notify-seller`, `/expiration/notify-buyers` |
| Driver: [m-ksl-alert-workers](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-alert-workers) PriceDropWorkerCommand:53, ExpirationWorkerCommand:53 | PROXY | migrates for free |

### m-ksl-homes — [GitHub](https://github.com/deseretdigital/m-ksl-homes) (no local checkout)

Best model for the migration: eight methods already use the ENDPOINT via `site-api/utils/sendEmailToQueue.php` (sendEmail, sendEmailToAdOwner, sendEmailToBuilder, sendNewAdEmail, sendAbuseEmail, sendAbuseQueueEmail, sendTourCommunityEmail).

Remaining DDM-LIB sends in `site-api/api/controllers/EmailController.php`: sendExpireEmail (211), sendEmailToPO (749), sendListingAlertEmail (868), sendCommunityAlertEmail (1149), sendRentAlertEmail (1288), sendMandrillEmailJSON (1707). The blocker comment at 912-913 says the endpoint lacks inter-service auth. That auth now exists (`ddm-jwt`) — verify and unblock. Also: `HomesMandrill/Mandrill.php` wraps the shared library; Homie PHPMailer at `site/application/libs/Homie/Mailer.php:18-36`; GSM secret `home_mandrill` (no literal).

### m-ksl-jobs — [`Legacy/m-ksl-jobs`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs)

Main flows already ENDPOINT ([EmailerQueue.php:34](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/api/common/EmailerQueue.php#L34); EmailController 334/598/627/657/701; ApplicationEmailer; PromocodeUsage; JobsFeedReport).

| Remaining | Mechanism | Note |
|---|---|---|
| [JobsEmailer.php:162-193](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/namespaces/Email/JobsEmailer.php#L162-L193) | DDM-LIB | key literal at line 11 |
| crons SavedSearchesReport:16-22; clientFacingUsageReport:82; promo-code reports (6 sends) | DDM-LIB | report crons |
| [statsFromMandrill.php:62,136](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/crons/regular-actions/statsFromMandrill.php#L62) | Mandrill API (read) | **second key literal**; Mandrill analytics dependency that breaks when traffic moves |
| ~20 `mail()` sites (expireJobs, autorefresh, ListingModel, JobsError, …) | MAIL() | ops alerts |

### mieten (Rent) — [`Legacy/mieten`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/mieten)

ENDPOINT already: `web/src/utils/sendEmailToQueue.js`, sendEmailToListingOwner:145, sendEmailToSales:42, sendListingActivationEmail:104. Remaining MANDRILL-SDK: tenant/sendEmail:383, invoiceMember:260+341, sendTrialExpirationNotice:147, reconcileTenantScreening:116, sendExpirationEmails:203. Secrets via Docker/GSM (no literals). (Not in project.json; covered under F6.)

### saved-search path (two hops, both required repos)

- [`saved-search-alert-workers`](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-alert-workers) — PROXY. [RecordNotify.php:352-380](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-alert-workers/src/Library/SavedSearch/RecordNotify.php#L352-L380) POSTs per-vertical ksl-api endpoints from [Config.php](file:///Users/cpies/code/shaping/Research%20Repos/saved-search-alert-workers/src/Library/SavedSearch/Config.php) (cars:95, jobs:172, homes:312, communities:377, rent:467, general:541) at `api3.ksl.com`. Ad-hoc form payload; log keys still say `mandrillResponse`.
- [`saved-search-email-service`](https://github.com/deseretdigital/saved-search-email-service) — PROXY (Go, no local checkout). Consumes `Prod_SavedSearchEmail`; POSTs six ksl-api endpoints with a ksl-api nonce; parses Mandrill-shaped responses (soft/hard-bounce, spam reject_reason). This traffic explains the "unexplained CAPI email endpoint" observation in the package notes.
- Migration implication: moving saved-search alerts to the central endpoint moves template rendering and member-email lookup out of ksl-api. This is the largest single work item.

### marketplace-backend — [`marketplace-backend`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend)

**Tier A — already on the ENDPOINT:**

| Service | Location | Emails |
|---|---|---|
| listing-jobs-http-rest | [send_email.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-jobs-http-rest/internal/client/send_email.go) (member JWT) | employer notification + applicant confirmation; templates `jobs-employer-notification`, `jobs-application-confirmation`; resume attachments |
| feeds-ps-syncer | [emailer.go](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/feeds/services/feeds-ps-syncer/internal/routing/emailer.go) (`ddm-jwt`) | feed report + 5 dealer alert types |
| feeds-ps-transformer | internal/routing/emailer.go (copy of the above) | failure report + dealer alerts |

The two feeds clients are byte-identical; the jobs client adds attachments. Extract one shared client (`marketplace-backend/lib/golang/`).

**Tier B — direct PUBSUB (move to ENDPOINT):**

| Service | Location | Emails / template | Notes |
|---|---|---|---|
| listing-http-rest | [send_email.go:45-149](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-http-rest/internal/pubsub/send_email.go#L45-L149) | thank-you; `classifieds thank you` | protojson |
| listing-ps-price-drop | [send_email.go:50-186](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-backend/apps/listing/services/listing-ps-price-drop/internal/client/send_email.go#L50-L186) | `classifieds price drop notification` | only `IsolateRecipients` user; UTF-8 recipient validation |
| subscription-ps-event-listener | domain.go:229-332 | Stripe payment failed/succeeded | json.Marshal |
| profile-http-rest | zendesk_email_client.go:111-149 | 4 fraud/abuse alerts → support@ksl.com | feature-flagged |
| dealer-ps-notifications | app.go:533-687 | dealer leads (ADF XML or HTML `dealer - user contact event`) | topic name hard-coded main.go:27; only sender that nacks on failure |
| third-party-caramel-http-webhook | app.go:580-933 | `caramel - buyer submits offer`; `caramel offer feedback` | feedback uses `delivery_time` +24 h; Firestore dedupe |

### marketplace-graphql — [`marketplace-graphql`](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql)

| Location | Mechanism | Purpose | Notes |
|---|---|---|---|
| [businesspackageemailsender.go:16-113](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/businesspackageemailsender.go#L16-L113) | PUBSUB | Homes business-package leads → homes@deseretdigital.com | 240-line inline HTML body; new Pub/Sub client per request, never closed |
| [phone-deny-list.go:307-337](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/queryresolvers/phone-deny-list.go#L307-L337) | PUBSUB | deny-list alert → support@ksl.com | copy-paste of the above pattern |
| [email-owner.go:137,191](file:///Users/cpies/code/shaping/Research%20Repos/marketplace-graphql/graph/mutationresolvers/email-owner.go#L137) | PROXY | sendEmailToAdOwner (general + cars) | likely the highest-volume email at KSL; legacy-owned |
| send-car-dealer-inventory-email.go:17 | PROXY | dealer inventory interest | |

### m-ksl-myaccount-v2 — [`m-ksl-myaccount-v2`](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2)

PROXY only: [email-seller.ts:74-92](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/pages/api/v1/listings/%5Bvertical%5D/%5Bid%5D/email-seller.ts#L74-L92) routes to general/cars/homes `sendEmailToAdOwner`; rent goes through the mieten GraphQL mutation (already ENDPOINT).

### Shared PHP library — [`deseretdigital/email`](https://github.com/deseretdigital/email) (no local checkout)

`AdapterFactory` supports `mandrill`, `bronto`, `amazonses`. Composer consumers: `dado`, `ksl`, `ksl-api`, `ksl-news-crons`, `sms-api` (+ `m-ksl-jobs` via JobsEmailer). Call sites beyond ksl-api: ksl-news-crons (CMSEmailProcessor:15-16, pickemAdminEmailer, pickemProcessor, PickemEmail), sms-api (EmailServiceProvider:6-7,22; env `EMAIL_TOKEN_MANDRILL`), ksl (form_emailer_mandrill_responsive ×2), dado (helpers/email/classes/model.php:4,24). `AmazonSESAdapter` has zero call sites org-wide.

### Member pipeline (Phase 3 repos; not in project.json)

| Component | Location | Role |
|---|---|---|
| ksl-member (Python) | api/member_api/common/emails.py | publishes to `projects/mailchimp-340018/topics/mailchimp-member` |
| member-backend (Go) | member-http-rest internal/pubsub/notify.go | publishes; env `MAILCHIMP_TOPIC` default `member-mailchimp-events` — reconcile the two names |
| trufty-microservices/mailchimp-email-service (Python) | Generate_email.py, Processor.py | consumes member events, renders Jinja2 HTML from `html_templates/*.html`, and **publishes the rendered `body` to `Public_SendEmail`** (settings.toml `MAILGUN_PUBLISH_TOPIC`; comment: "until we have an API for mailgun requests"). The "→ Mandrill" picture in the package is stale. From `support@ksl.com` → Mailgun. TOTP borrows fraud_attempt.html "until design can give us a template for 2FA" |

---

## 3. Additional sender locations (stretch)

| Repo | Location | Mechanism | Purpose |
|---|---|---|---|
| ksl | logic/resources/form_emailer_mandrill_responsive.php; resources/contact/… | DDM-LIB | contact forms |
| ksl | bronto/* (incl. unsubscribe.php), newsletterSync.php | Bronto | newsletter (product decision) |
| ksl-news-api | src/Helper/BrontoEmailHelper.php (+ MemberProvider/MemberService) | Bronto SOAP, live | newsletter signup; **hard-coded creds** |
| ksl-news-crons | CMSEmailProcessor, pickemAdminEmailer, pickemProcessor, PickemEmail | DDM-LIB | CMS + Pick'em sends |
| ksl-news-web-v2 | src/Providers/LandingPageProvider.php | iWitness sends | News |
| sms-api | app/Providers/EmailServiceProvider.php:6-7,22 | DDM-LIB | via `EMAIL_TOKEN_MANDRILL` |
| dado | helpers/email/classes/model.php:4,24; modules/member/controllers/member.php | DDM-LIB + Bronto | email + newsletter signup |
| gcp-cloud-functions | dragnet/gcloud_functions/send-mandrill-email/index.js | mailgun.js (despite name) | Search team reports |
| pinpoint-beeswax | services/etl-beeswax-alerts | Mandrill | AdOps campaign alerts |
| ddm-python-packages | ddm_mandrill/mandrill.py | Mandrill | shared Python helper |
| dbi-dags + dbi-dags-airflow3 | dags/mandrill_messages_etls.py | Mandrill API (read) | BigQuery ETL; presence in the Airflow 3 repo suggests it is still scheduled |
| utah-com | microservices/brochure-emailer + 4 routes | PUBSUB | already on topic; move to endpoint later |
| thememories-rebuild | app/services/email/publishToQueue.ts | PUBSUB | same |
| ksl-news-monorepo | services/events-report-cron/main.go | PUBSUB | same |
| toolbox | app/constants/globals.ts + env | PUBSUB | same |
| m-ksl-classifieds | Listing.php:443-477, SellController:699, util/sendBatchEmail.php | PROXY | + 4 `mail()` error alerts |
| m-ksl-generalfeeds | classes/RedFlagReport.php:208-250 | PROXY → sendMandrillEmailJSON | dealer feed red flags |
| nest | tools/homes/abuse/api/HomesAbuseEmail.php:24-50 | PROXY | 10 abuse templates |
| nest-tools | general/expire/emailexpireads.php:92-107 | PROXY | **parses Mandrill `reject_reason`** — response-shape coupling |
| m-ksl-myaccount | favorites controllers ×4; Util.php:118 | PROXY + MAIL() | mail() goes to a stale personal address |
| m-ksl-cars | application/models/Listing.php:1028-1045 | PROXY | email seller |
| m-ksl-cronlogger / m-ksl-classfeeds / m-ksl-fraudTools | cronLogger.php:212; load.php:28,257; quickFraud/dailyReport.php:27 | MAIL() | ops alerts |

**No-sender repos (verified; cleanup only):** m-ksl-cars-api (dead `MANDRILL_API_KEY` TF/CI plumbing + `null://` Swiftmailer config), m-ksl-cars-ui (dead TF secret; the old email-support.js is gone), m-ksl-alerts, ksl-carfeeds, phoney, push-notifications-service, marketplace-reports, listing-pricing, images-services, saved-search-percolation, marketplace-frontend, ksl-global (vendored PHPMailer, unused), nest-tools vendored Swift Mailer (unused), mailgun-service (archived 2024-01; was empty boilerplate).

---

## 4. Services to create or change (summary)

| Service / component | Action |
|---|---|
| ksl-emailer-queue consumer | Rewrite (Go, Datadog) or harden in place; fix the 11 F1 items |
| ksl-emailer-queue-endpoint | Add/verify `tags` + `delivery_time`; confirm `ddm-jwt` path; becomes the only publish surface |
| Public_SendEmail topic | Add DLQ; add or enforce schema; retire orphan sub `Prod_SharedFeatures_SendEmail` |
| deseretdigital/email | New unified adapter; deprecate Bronto/SES adapters |
| ksl-api | Remove vertical gate; migrate Mandrill-only methods; keep alert endpoints during transition |
| m-ksl-classifieds-api | Replace MandrillWrapper + TemplateEmailSender sends |
| m-ksl-homes / m-ksl-jobs / mieten / ksl | Migrate listed stragglers |
| Member pipeline | Confirm owner; migrate 6 email types; keep TOTP path until ported |
| saved-search-email-service + saved-search-alert-workers | Re-point from ksl-api endpoints to the central endpoint (with template/lookup relocation) |
| Shared Go endpoint client | New: extract to marketplace-backend/lib/golang/ |
| Credentials | No rotation (Q10, pending Trufty/Platform confirmation): delete literals per-repo during migration; Mandrill account shutdown at package end invalidates both keys; revoke the airlock key separately; delete mandrill.ini |
| Mailgun template library | Create ~35 templates from in-code renders (section 5); extend producer transports + feeds clients to pass `template`; console-managed with a checked-in registry (Q12) |
| Bronto newsletter path (F11) | Migrate signup (ksl-news-api, dado) and unsubscribe (ksl) off Bronto; archive bronto-api-php-client; destination pending Q15 (product) |

---

## 5. Template migration inventory (Mailgun templates)

Target state (per [ADR 067](https://app.notion.com/p/31e2ac5cb23580eaa6e7c949c7a5b2bc)): transactional emails use Mailgun-hosted templates, referenced by name in the publish (`template` + `template_variables`). Today only the modern repos do this. Every legacy sender renders HTML in code and ships it as `body`, so those emails cannot benefit from central template management and break rendering guarantees.

### 5.1 Mailgun template names already in use (modern repos)

| Template name | Sender | Location |
|---|---|---|
| `jobs-employer-notification` | listing-jobs-http-rest | send_email.go:26 |
| `jobs-application-confirmation` | listing-jobs-http-rest | send_email.go:27 |
| `classifieds thank you` | listing-http-rest | send_email.go:21 |
| `classifieds price drop notification` | listing-ps-price-drop | send_email.go:23 |
| `classifieds subscription receipt` | subscription-ps-event-listener | domain.go:194 |
| `classifieds two listing subscription receipt` | subscription-ps-event-listener | domain.go:196 |
| `classifieds subscription payment failed` | subscription-ps-event-listener | domain.go:246 (hardcoded) |
| `classifieds 2 listings subscription payment failed` | subscription-ps-event-listener | domain.go:213 — **dead: the failed path hardcodes the single-listing name at :246, so this never sends** |
| `dealer - user contact event` | dealer-ps-notifications | app.go:621 |
| `caramel - buyer submits offer` | third-party-caramel | app.go:931 |
| `caramel offer feedback` | third-party-caramel | app.go:874 |

Known drift (console-driven template management):
- The jobs `email-templates/README.md` names the templates `jobs-application-employer` / `jobs-application-applicant`; the code uses different names. The README's example code block is wrong.
- The price-drop spec names the template `general-listing-price-drop` / `listing-price-drop`; the code uses `classifieds price drop notification`.
- 9 of the 11 names have no in-repo artifact at all (no MJML, no HTML, no variable manifest). Only the two jobs templates have checked-in source, and that source is a manually pasted mirror of the Mailgun console, not rendered at runtime.

### 5.2 Pipeline gaps that block template adoption

These changes must land before the template migration can start:
1. **Producer transports cannot pass a template.** `ksl-api` [PubSubEmail.php:26-71](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/common/api/classes/PubSub/PubSubEmail.php#L26-L71), `m-ksl-jobs` [EmailerQueue.php:25-32](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/m-ksl-jobs/site-api/api/common/EmailerQueue.php#L25-L32), and `mieten` sendEmailToQueue.js:44-56 only forward subject/body/from/reply-to/recipients. The endpoint, the protobuf, and the consumer all support `template` + `template_variables` already.
2. **The two feeds endpoint clients also lack the field** (feeds-ps-syncer emailer.go:141-160, feeds-ps-transformer emailer.go:127-146).
3. ~~The consumer rejects template-only messages~~ **Fixed upstream** (verified 2026-09-02): the gate now accepts `template` without `body`/`plain_text`.
4. **The Mandrill fallback silently drops `template`** — a template-only email that falls back sends empty. F1 must resolve this before legacy volume moves onto templates.
5. Template variables ride as one JSON string; there are no per-recipient variables. `isolate_recipients` now works end-to-end (verified 2026-09-02: Mailgun batch-splitting with recipient-variables; Mandrill `preserve_recipients:false`) but stays opt-in with a warning log (Q9). Batch sends that personalize per recipient (saved-search alerts) set the flag or publish per recipient.

### 5.3 Emails to move into Mailgun templates

Counts: about 60 emails render in code today; about 35 are designed HTML emails that should become Mailgun templates. Line numbers are from the 2026-09-02 checkouts.

**ksl-api — general classifieds** (Plates renderer EmailController.php:178; templates under `general/api/template/emailTemplates/`)

| Email | Sender | In-code template | Text variant |
|---|---|---|---|
| Thanks for posting | EmailController.php:240 | create.php (+ layout, footer) | create.text.php (rendered, then dropped on pub/sub path) |
| Abuse/moderation notices — 23 types | :433 (type map :36-176) | abuse/{1..23}_*.php (46 files) | .text.php each, dropped |
| Contact listing owner | :578 | owner.php | owner.text.php, dropped |
| Dealer posting limit | :843 | email/limitTemplate.php ({%var%} substitution) | strip_tags |
| Saved-search alert | :1044 | alert.php (+ alert-email.mjml source) | alert.text.php, dropped |
| Auto-assigned featured | :938 (Mandrill-only) | autoassignslot.php | autoassignslot.text.php |

**ksl-api — cars** (substitution helper :2620 with `${IF(x)}…${ENDIF}` conditionals — porting hazard)

| Email | Sender | In-code template | Notes |
|---|---|---|---|
| New frontline listing | :603 | templates/new-frontline-ad.html (+ .txt, .mjml) | real text variant exists |
| Dealer Exchange listing live | :734 | new-backlot-ad.html | text is inline PHP (:775-786, has TODO) |
| Cars saved-search alert | :1985 | listing-alert.html + inline listing rows :2041-2128 + carousel :2195 | no text; listing rows should become `{{#each}}` |
| Listing status (price drop / expiring ×3) | :2449 | ad-status.html (+ .txt, .mjml) | `${IF(isOwner)}` conditional |
| Email seller (user-to-user) | :1004 | inline HTML :1035-1052 | inline text |
| Contact ad owner (lead) | :458 | text-only (:523-538, html empty) | template optional |
| Contact info updated | :1502 | inline HTML :1534-1543 | no text |
| Expiration warning (@deprecated) | :1212 | inline HTML :1232-1241 | check before porting |
| Want-to-list / low-price / SS stats report | :1284 / :273 / :1100 | inline text or HTML table | internal; template optional |
| ADF XML leads | :1753, :1704 | inline ADF XML | **stays in code** — machine format |
| Client Dashboard PDF | :1417 | body is `&nbsp;` + PDF attachment | template optional |

Dead cars templates to confirm and delete: featured-dates.{html,txt,mjml}, payment-info.{html,txt}.

**ksl-api — common / sports / news**

| Email | Sender | Source | Notes |
|---|---|---|---|
| Feedback email | common EmailController:54 | caller-supplied body | template optional |
| Pick'em invitation | PickemController:500 | inline one-line text | template optional |
| Pick'em winner / invite-all / recap | PickemAdminController:440/516/623 | HTML from KSL CMS story XML + inline blocks | **content is editorial, CMS-driven** — scope decision Q14 |
| Report This Ad | ReportThisAdController:61 | inline HTML :145-152 | small template |

**m-ksl-classifieds-api** (Twig; `getTextBody()` is never set — zero plain-text coverage in the repo)

| Email | Twig template | Mailgun candidate |
|---|---|---|
| Price drop / seller expiring / buyer expiring | templates/emails/listing-status.twig (+ MJML sources) | one template, variables incl. isPriceDrop |
| Thanks for listing | thank-you.twig | `classifieds thank you` already exists in Mailgun for the modern sender — likely converge |
| Dealer monthly report | dealer-report.twig | **hazard: embedded CID images + runtime-generated donut chart PNG** — needs hosted images (Q13) |

**m-ksl-homes** (PHP templates + MJML sources under site-api/api/emailTemplates/)

| Email | Template files | Today |
|---|---|---|
| New ad, to-ad-owner, to-builder, tour community | newAdEmail.php, toAdOwnerEmail.php, toBuilderEmail.php, tourCommunityEmail.php (+ .mjml each) | rendered in code, `body` → endpoint |
| Homes/community/rent saved-search alerts | alertEmailCommon.php, alertEmailCommonNew.php, alertEmailCommonWithOthers.php (+ .mjml) | rendered in code → Mandrill |
| Buy listing expire | buyExistingExpireEmail.php (+ .mjml) | → Mandrill |
| Homie realtor emails | homieProEmail.php, homieUpgradeSteps.php | → Mandrill via ksl-api helper |
| Abuse queue notices | abuseQueue/ set | `body` → endpoint |

**m-ksl-jobs** (Plates; endpoint sends pass `body` only)

| Email | Template | Notes |
|---|---|---|
| Posting/transaction confirmation (10 subject variants) | emailTemplates/confirmation.php + partials + white-label banners (ksljobs / siliconslopes) | one Mailgun template with a brand variable, or one per label (Q14) |
| Jobs saved-search alert | alert.php | |
| Authorized user added / invitation | authorizedUser.php, authorizedUserInvitation.php | |
| Application → employer / applicant | application/recievedApplication.php, senderConfirmation.php | the modern jobs service already has Mailgun templates for the same purpose — converge |
| Report crons (BBU, promo codes, feed, SS stats, client usage) | inline strings + CSV attachments | template optional (internal) |

Orphan: highContractUsageNotification.php (zero references).

**mieten** (inline MJML in JS, `mjml2html` at runtime; direct-Mandrill sends set `text: ''`)

| Email | Template module |
|---|---|
| Tenant screening result | web/src/emailTemplates/screeningEmail.js |
| Invoice paid / charge declined | memberInvoice.js (2 branches) |
| Trial expiring/expired | trialExpiration.js |
| Rent listing expiring | inline in crons/src/sendExpirationEmails.js:34 |
| Listing-owner inquiry | inquiryEmail.js |
| Contact sales | contactSalesEmail.js |
| Listing activation | listingActivation.js |

Orphan: featuredDatesConfirmation.js (212 lines, no callers).

**ksl-emailer-queue / messages-email-notifications**

| Email | Source | Notes |
|---|---|---|
| "You received a message on KSL.com" | inline MJML in buildEmail.ts:11-120 | highest-volume email family; no plain text; header image is the KSL Jobs logo on all verticals |

**trufty-microservices / mailchimp-email-service** (Jinja2, rendered in code, `body` → Public_SendEmail)

| Email | Template file |
|---|---|
| account_suspended, email_lockout, fraud_attempt, social_link_verification, totp (borrows fraud_attempt.html), user_suspended, verification_email, member_info_change + social_account_connected (borrow fraud_attempt.html) | html_templates/*.html (7 files, 9 actions) |

**marketplace-graphql**

| Email | Source | Notes |
|---|---|---|
| Business package interest | businesspackageemailsender.go getBody:163-409 — MJML compiled by hand, pasted as a Go string; the MJML lives in a comment | prime conversion target |
| Phone deny-list alert | phone-deny-list.go:293-306 | text-only, but placed in the HTML `body` field — at minimum move it to `plain_text` |

### 5.4 Keep in code (not template candidates)

- ADF XML dealer leads (machine format for dealer CRMs) — dealer-ps-notifications adf.go and ksl-api cars :1753/:1704.
- Plain-text operational emails: profile-http-rest Zendesk alerts (4), feeds reports and alerts (8), internal stats reports. ADR 067 templates target designed emails; text-only internal mail can stay `plain_text`.
- The `ksl` CMS form emailer (form_emailer_mandrill_responsive.php): the body is generated from arbitrary CMS-defined form fields. A generic form-submission template is possible; otherwise it stays body-based (Q14).
- PDF-attachment carriers (cars Client Dashboard, jobs/mieten CSV reports).

### 5.5 Plain-text strategy and process gap

- Authored text variants exist only in ksl-api general (all Plates emails + 23 abuse types) and cars (new-frontline-ad.txt, ad-status.txt). The pub/sub path currently **drops** the rendered text — only `body` is published. Fix this during migration, or text coverage regresses further.
- Everything else is machine-derived (`strip_tags`), duplicated HTML, an empty string, or absent. Each new Mailgun template needs a text-fallback decision (Q11).
- Process gap: no versioning, CI, or API-based upload exists for Mailgun templates anywhere. The only documented workflow (jobs email-templates/README.md) is "compile MJML locally, paste into the Mailgun console", and its template names already drifted from the code. Naming is inconsistent (`classifieds thank you` vs `jobs-employer-notification` vs `dealer - user contact event`).
- **Decision (Q12)**: templates stay managed in the Mailgun console; a checked-in template registry (name, owner, variables, source reference) stops the name drift. No CI upload in this package.
- **Decision (Q11)**: the build team picks the plain-text strategy. Constraint: preserve the authored `.text.php` variants — the pub/sub path drops them today.
