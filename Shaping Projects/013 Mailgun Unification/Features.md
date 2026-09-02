# Mailgun Unification — Features

Target architecture: product services call one central authenticated email endpoint. The endpoint publishes to the Pub/Sub topic `Public_SendEmail`. One downstream service consumes the topic and delivers through the configured provider. See [Services.md](Services.md) for the full sender inventory with code locations.

Terms used in this document:
- **Central endpoint** — `POST https://api.ddm.io/emailer-queue`, served by `ksl-emailer-queue-endpoint`.
- **Email topic** — the Pub/Sub topic `Public_SendEmail` in GCP project `ddm-platform`.
- **Consumer** — the `emailer-mandrill-transactional` Cloud Function in `ksl-emailer-queue`.
- **Shared PHP library** — the `deseretdigital/email` Composer package.

## F1 — Central pipeline hardening (Phase 1, highest priority)

Modernize the consumer and make its contract provider-neutral. A Go rewrite with Datadog tracing is the preferred shape. The rewrite decision is open (Q2).

Required fixes, found in the current consumer code:
1. Do not throw after a successful Mandrill fallback. The current code throws, Pub/Sub retries, and the user gets duplicate emails (`messageHandler.ts:98`).
2. Do not re-encode attachment content for Mandrill. The current code double-encodes base64 and corrupts attachments (`mandrill.ts:17-20`).
3. Accept template-only messages. The current code rejects a message that has a `template` but no `body` or `plain_text` (`index.ts:120-123`).
4. Throw real `Error` objects from the Mandrill sender. The current plain-object throw defeats the `SendError` check and logs full email bodies.
5. Support recipient isolation in the Mailgun sender. A multi-recipient send currently shows all addresses to every recipient.
6. Remove `DEBUG=1` from production. The current setting logs full email payloads (PII).
7. Add a dead-letter queue to the email topic path. Today the only behavior is endless retry until message retention expires.
8. Attach a schema to the email topic, or enforce the contract at the central endpoint.
9. Add end-to-end observability: Datadog tracing and consistent logs from endpoint to provider result. The current consumer has zero APM.
10. Resolve the sending-domain mismatch. The whitelist allows `ksl.com`, `utah.com`, and `thememories.com`, but all Mailgun traffic sends through the single `MAILGUN_DOMAIN=ksl.com`.
11. Document that the Mandrill fallback silently drops `template` and `delivery_time`. Preserve or remove that behavior deliberately.

## F2 — Central endpoint adoption

Move services that publish directly to the email topic onto the central endpoint. Close the endpoint contract gaps first:
- Verify or add form support for `tags` and `delivery_time`. Every direct publisher sets tags. The Caramel feedback email needs `delivery_time` (+24 h).
- `isolate_recipients` and attachments are already in the endpoint contract.
- Confirm HTML `body` semantics when no template is used.
- The two feeds endpoint clients hardcode their form fields and cannot pass `template` at all. Extend them (or the shared client from this feature) before any feeds email uses a template.

Inter-service authentication exists. The endpoint accepts a member JWT (`Bearer`) and a service token (`ddm-jwt`, added 2026-06-16, used by the feeds services). The blocker comment in m-ksl-homes ("not setup for inter-service authentication yet") appears stale. Verify, then unblock the cron-driven senders.

Services to move (Tier B in Services.md): listing-http-rest, listing-ps-price-drop, subscription-ps-event-listener, profile-http-rest, dealer-ps-notifications, third-party-caramel-http-webhook, marketplace-graphql (2 resolvers).

Extract one shared Go endpoint client into `marketplace-backend/lib/golang/`. Three near-identical copies exist today (feeds-ps-syncer, feeds-ps-transformer, listing-jobs-http-rest).

## F3 — Shared PHP library unified adapter (Phase 2)

Add a unified adapter (central endpoint, or Pub/Sub) to `AdapterFactory` in the shared PHP library. The six consumer apps then migrate through configuration: `ksl-api`, `ksl`, `sms-api`, `ksl-news-crons`, `dado`, `m-ksl-jobs`. Mark `BrontoAdapter` and `AmazonSESAdapter` as deprecated.

## F4 — ksl-api completion

- Remove the per-vertical gate. `PubSubEmail::shouldSendThroughMailgun()` allows only `cars` and `classifieds`. All other verticals fall to Mandrill.
- Migrate the Mandrill-only methods: general `sendMandrillEmail`, `sendMandrillEmailJSON`, `sendAutoAssignedFeaturedEmail`; cars `sendEmailToAE`, `sendAdfPhoneContactMandrill`; common `sendFeedbackEmail`; the six Pick'em senders; `HomieEmailHelper`.
- Keep the saved-search alert endpoints working during migration. Active callers: `saved-search-email-service`, `saved-search-alert-workers`, and the ksl-api alerts workers. This traffic explains the "unexplained CAPI email endpoint" observation.

## F5 — Classifieds direct integrations (Phase 4a)

Replace the direct Mandrill SDK path in `m-ksl-classifieds-api`: `MandrillWrapper`, `MandrillClientFactory`, and the five `TemplateEmailSender` email types (price drop, seller expiration, buyer expiration, thank-you, dealer monthly report). `m-ksl-alert-workers` drives two of these over HTTP and migrates for free. Remove the stale `utm_source=ddm-bronto` parameters.

## F6 — Homes, Jobs, Rent stragglers (Phase 4b)

These repos already use the central endpoint for their main flows. Migrate the remaining direct sends:
- m-ksl-homes: `sendExpireEmail`, `sendEmailToPO`, `sendListingAlertEmail`, `sendCommunityAlertEmail`, `sendRentAlertEmail`, `sendMandrillEmailJSON`, and the Homie PHPMailer error mailer.
- m-ksl-jobs: `JobsEmailer`, the saved-searches monthly report, the client usage report, and six promo-code report sends.
- mieten (Rent): six direct Mandrill SDK sends (tenant screening, invoices, trial expiration, listing expiration, reconciliation report).
- ksl: the two `form_emailer_mandrill_responsive.php` contact-form senders.

## F7 — Member pipeline (Phase 3)

Pipeline today: `ksl-member` (Python) and `member-backend` (Go) publish member events. The `mailchimp-email-service` (Python, Trufty) consumes them. **Correction (2026-09-02): the service no longer sends through Mandrill.** It renders Jinja2 HTML templates in code and publishes the rendered body to `Public_SendEmail` (settings.toml `MAILGUN_PUBLISH_TOPIC`), so delivery already goes through the central pipeline to Mailgun. The package's "member pipeline → Mandrill" picture is stale.

Remaining Phase 3 work: move the 7 Jinja templates (9 actions) into Mailgun templates (see F10), switch the publish to the central endpoint, and reconcile the two topic names found in code (`mailchimp-member` in project `mailchimp-340018` vs `member-mailchimp-events`). TOTP still depends on the Python service and currently borrows the fraud_attempt template ("until design can give us a template for 2FA"). Confirm ownership and the migration plan with Justin Carmony and Chris Ward (Q4).

## F8 — Credential remediation (cross-cutting, do first)

Rotate and move to managed secrets, independent of slice timing:
- One Mandrill API key literal appears in 12 files: 9 in `ksl-api` (including `library/MandrillEmailHelper.php:20` and two test files) and 3 in `m-ksl-jobs`.
- A committed key file: `ksl-api/public_html/sports/v2/mandrill.ini`.
- A second, different Mandrill key in `m-ksl-jobs/crons/regular-actions/statsFromMandrill.php:62`.
- An airlock API key in `ksl-api/examples/general/airlock/SendMandrillEmail.php:5`.
- Hard-coded Bronto SOAP credentials in `ksl-news-api/src/Helper/BrontoEmailHelper.php`.

## F9 — Dead-code cleanup (Phase 6)

Remove only after traffic and ownership verification:
- `mailgun-service` repo — already archived (2024-01). It was one-commit boilerplate with no Mailgun code.
- `AmazonSESAdapter` — zero call sites found in code. The Datadog zero-traffic claim in SC-383437 is not verified; run the query before removal.
- `mandrill_messages_etls` Airflow DAG — present in both `dbi-dags` and `dbi-dags-airflow3`. Its presence in the Airflow 3 repo suggests it is still scheduled. Check the Airflow UI (Q5).
- Dead Mandrill secret plumbing in `m-ksl-cars-api` and `m-ksl-cars-ui` (Terraform/CI only; no sender code remains).
- Vendored dead libraries: PHPMailer in `ksl-global`, Swift Mailer in `nest-tools`.
- Fork archival after migration: `mandrill-api-php`, `bronto-api-php-client`; drop the Bronto dependency from `ksl-api/composer.json`.
- The orphan pull subscription `Prod_SharedFeatures_SendEmail` on the email topic (verify no consumer first).

## F10 — Template migration to Mailgun (cross-cutting)

Every email whose HTML lives in application code must move into a Mailgun-hosted template. The publish then references the template by name (`template` + `template_variables`), so the email renders correctly and the design has one home. This applies ADR 067 to the legacy fleet. The full inventory is in [Services.md section 5](Services.md).

Current state:
- The modern repos already reference 11 Mailgun template names. Two of those names have drift bugs (a dead 2-listing payment-failed template; README names that do not match code).
- No legacy repo uses a Mailgun template. About 60 emails render HTML in code (Plates PHP, Twig, MJML-in-JS, Jinja2, inline strings) and publish the rendered `body`. About 35 of them are designed HTML emails that should become Mailgun templates.

Work items, in order:
1. Unblock the pipeline (with F1/F2): add `template`/`template_variables` pass-through to the three legacy producer transports (`PubSubEmail.php`, jobs `EmailerQueue.php`, mieten `sendEmailToQueue.js`) and the two feeds clients. Fix the consumer's template-only rejection and the Mandrill-fallback template drop first — until then every template send needs a `plain_text` fallback, and a fallback delivery would send an empty email.
2. Define the template process: naming convention, in-repo source of truth (MJML), and an upload path (Mailgun templates API, not console paste). Today the only workflow is manual console paste, and names have already drifted.
3. Migrate templates per phase, converging duplicates (legacy CAPI thank-you vs the existing `classifieds thank you`; legacy jobs application emails vs the existing jobs templates; the three saved-search alert designs per vertical).
4. Preserve or improve plain-text: authored `.text.php` variants exist for the ksl-api general emails but are dropped on the pub/sub path today. Do not lose them in migration.

Known hazards (details in Services.md 5.3/5.5): cars `${IF()}`/`${ENDIF}` conditional syntax; pre-rendered HTML loops that should become `{{#each}}` arrays; CID/embedded images and a runtime-generated chart in the CAPI dealer report; CMS-driven Pick'em content; white-label jobs confirmation banners; the dynamic `ksl` form emailer.

## Additional sender locations (stretch)

These senders are out of the core slices. Document them; migrate them when their owners agree:
- `pinpoint-beeswax` — AdOps campaign alerts (Mandrill).
- `gcp-cloud-functions` dragnet `send-mandrill-email` — Search team reports. The folder name says Mandrill; the code uses the mailgun.js SDK.
- `ddm-python-packages/ddm_mandrill` — shared Python Mandrill helper.
- KSL News senders: iWitness (`ksl-news-web-v2`), Pick'em crons (`ksl-news-crons`), the live Bronto newsletter signup in `ksl-news-api` (product decision, Q7).
- Direct-topic publishers outside marketplace: `utah-com`, `thememories-rebuild`, `ksl-news-monorepo` events-report-cron, `toolbox`. These are on the topic already; move them to the endpoint later.
- Roughly 35 PHP `mail()` call sites across legacy repos. Most are operational alerts to individual engineers, some to stale personal addresses. Decide: route to the queue, or replace with Slack/Datadog alerts (Q6).
