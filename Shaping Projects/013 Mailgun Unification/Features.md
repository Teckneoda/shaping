# Mailgun Unification — Features

Target architecture: product services call one central authenticated email endpoint. The endpoint publishes to the Pub/Sub topic `Public_SendEmail`. One downstream service consumes the topic and delivers through the configured provider. See [Services.md](Services.md) for the full sender inventory with code locations.

Terms used in this document:
- **Central endpoint** — `POST https://api.ddm.io/emailer-queue`, served by `ksl-emailer-queue-endpoint`.
- **Email topic** — the Pub/Sub topic `Public_SendEmail` in GCP project `ddm-platform`.
- **Consumer** — the `emailer-mandrill-transactional` Cloud Function in `ksl-emailer-queue`.
- **Shared PHP library** — the `deseretdigital/email` Composer package.

## F1 — Central pipeline hardening (Phase 1, highest priority)

Harden the consumer in place and make its contract provider-neutral (Q1). **Decision (Q2): the Go rewrite is a separate package** — this package fixes the Node consumer's defects and does not rewrite it.

Already fixed upstream (verified 2026-09-02 against the synced checkout): the consumer accepts template-only messages, and `isolate_recipients` works end-to-end in both senders (opt-in with a warning log — Q9).

Required fixes, still present in the current consumer code:
1. Do not throw after a successful Mandrill fallback. The current code throws, Pub/Sub retries, and the user gets duplicate emails.
2. Do not re-encode attachment content for Mandrill. The current code double-encodes base64 and corrupts attachments.
3. Throw real `Error` objects from the Mandrill sender. The current plain-object throw defeats the `SendError` check and logs full email bodies.
4. Remove `DEBUG=1` from production. The current setting logs full email payloads (PII).
5. Add a dead-letter queue to the email topic path. Today the only behavior is endless retry until message retention expires.
6. Attach a schema to the email topic, or enforce the contract at the central endpoint (Q3 makes the endpoint the enforcement point).
7. Add observability the build team can support until the rewrite lands: structured logs end to end; Datadog tracing via dd-trace for Node if cheap, else it ships with the rewrite package.
8. Resolve the sending-domain mismatch. The whitelist allows `ksl.com`, `utah.com`, and `thememories.com`, but all Mailgun traffic sends through the single `MAILGUN_DOMAIN=ksl.com`.
9. Document that the Mandrill fallback silently drops `template` and `delivery_time`. Preserve or remove that behavior deliberately.

## F2 — Central endpoint adoption

**Decision (Q3): the central endpoint is the only blessed publish path.** All direct topic publishes retire, including ksl-api `PubSubEmail`. **Decision (Q8): the endpoint response is fire-and-forget** — one normalized "accepted" result; callers that parse Mandrill rejection detail get rewritten (see F4); bounce handling belongs to the Mailgun verification package (012).

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
- Retire `PubSubEmail` entirely once ksl-api sends go through the central endpoint (Q3).
- Rewrite the response parsers to fire-and-forget (Q8): `saved-search-email-service` bounce branches, `nest-tools` emailexpireads, homes EmailController response checks. Rejection detail stops being available synchronously; bounce data moves to project 012.

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

## F8 — Credential end-of-life (cross-cutting)

**Direction (Q10, pending confirmation by the Trufty and Platform teams):** no rotation. The migration deletes each key literal as its repo moves off Mandrill, and the Mandrill account shuts down at package end — which invalidates both exposed Mandrill keys, including every copy in git history. The same pattern applies to the Bronto SOAP credentials via the Phase 5 migration (F11).

The exposure inventory (all live until the shutdowns):
- One Mandrill API key literal in 12 files: 9 in `ksl-api` (including `library/MandrillEmailHelper.php:20` and two test files) and 3 in `m-ksl-jobs`.
- A committed key file: `ksl-api/public_html/sports/v2/mandrill.ini`.
- A second, different Mandrill key in `m-ksl-jobs/crons/regular-actions/statsFromMandrill.php:62`.
- Hard-coded Bronto SOAP credentials in `ksl-news-api/src/Helper/BrontoEmailHelper.php`.
- An airlock API key in `ksl-api/examples/general/airlock/SendMandrillEmail.php:5` — **not covered by any shutdown**; verify and revoke it separately (Q10).

Open with Trufty & Platform (Q10): is the months-long exposure window during the build acceptable, or do the two Mandrill keys get rotated at package start anyway?

## F9 — Dead-code cleanup (Phase 6)

Remove only after traffic and ownership verification:
- `mailgun-service` repo — already archived (2024-01). It was one-commit boilerplate with no Mailgun code.
- `AmazonSESAdapter` — zero call sites found in code. The Datadog zero-traffic claim in SC-383437 is not verified; run the query before removal.
- `mandrill_messages_etls` Airflow DAG — present in both `dbi-dags` and `dbi-dags-airflow3`. **Decision (Q5): no Airflow action in this package.** Document for the reporting owner that this migration eliminates the Mandrill traffic that feeds the DAG and its BigQuery tables; the DAG's retirement is theirs to schedule.
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
1. Unblock the pipeline (with F1/F2): add `template`/`template_variables` pass-through to the three legacy producer transports (`PubSubEmail.php` — retiring per Q3, so its senders go straight to the endpoint — jobs `EmailerQueue.php`, mieten `sendEmailToQueue.js`) and the two feeds clients. The consumer's template-only rejection is already fixed upstream; the Mandrill-fallback template drop remains — resolve it (F1) before legacy volume moves onto templates.
2. **Decision (Q12):** templates stay managed in the Mailgun console. Add a checked-in template registry (name, owner, variables, source reference) to stop the name drift. No CI upload pipeline in this package.
3. Migrate templates per phase, converging duplicates (legacy CAPI thank-you vs the existing `classifieds thank you`; legacy jobs application emails vs the existing jobs templates; the three saved-search alert designs per vertical).
4. Plain-text: **the build team decides the strategy (Q11)**. Constraint: do not lose the authored `.text.php` variants that exist today — the pub/sub path already drops them.

Scope edges settled (Q14): Pick'em emails stay CMS/body-based; the jobs confirmation becomes one Mailgun template with a brand variable (ksljobs / siliconslopes); the `ksl` form emailer stays body-based. All three still migrate transport to the central endpoint. Still open: the CAPI dealer report with CID images and a generated chart (Q13).

Known hazards (details in Services.md 5.3/5.5): cars `${IF()}`/`${ENDIF}` conditional syntax; pre-rendered HTML loops that should become `{{#each}}` arrays; the Q13 dealer report.

## F11 — Bronto newsletter migration (Phase 5)

**Decision (Q7): fully in scope.** Move the live Bronto newsletter integrations off Bronto:
- `ksl-news-api`: `BrontoEmailHelper` SOAP signup path (`MemberProvider` → `MemberService::confirmSubscription`), plus the `BrontoAdProvider` "Bronto ads" feature (migrate or deprecate).
- `ksl`: the `bronto/` directory, including the unsubscribe flow (`bronto/unsubscribe.php`) and `newsletterSync.php`.
- `dado`: newsletter signup on account creation (`modules/member/controllers/member.php`).
- After migration: archive the `bronto-api-php-client` fork, drop the Bronto composer dependency from `ksl-api`, and remove the hard-coded SOAP credentials (F8).

Blocker: **Q15** — the replacement destination for newsletter subscriptions is a product decision. Shape the code moves now; the build waits on that decision.

## Additional sender locations (stretch)

These senders are out of the core slices. Document them; migrate them when their owners agree:
- `pinpoint-beeswax` — AdOps campaign alerts (Mandrill).
- `gcp-cloud-functions` dragnet `send-mandrill-email` — Search team reports. The folder name says Mandrill; the code uses the mailgun.js SDK.
- `ddm-python-packages/ddm_mandrill` — shared Python Mandrill helper.
- KSL News senders: iWitness (`ksl-news-web-v2`) and the Pick'em crons (`ksl-news-crons`). The Bronto newsletter work moved into scope as F11.
- Direct-topic publishers outside marketplace: `utah-com`, `thememories-rebuild`, `ksl-news-monorepo` events-report-cron, `toolbox`. These are on the topic already; move them to the endpoint later.
- Roughly 35 PHP `mail()` call sites across legacy repos. Most are operational alerts to individual engineers, some to stale personal addresses. **Decision (Q6): route them through the queue — confirmed as a stretch goal of this package.**
