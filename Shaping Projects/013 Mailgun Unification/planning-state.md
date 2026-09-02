# Planning State — Mailgun Unification

## Identified So Far

- **Full sender inventory is complete.** Every known transactional email path is documented in [Services.md](Services.md) with mechanism, file, and line references. [Features.md](Features.md) maps the work to the six Notion package phases.
- **The target architecture already exists.** The central endpoint (`POST api.ddm.io/emailer-queue`, repo ksl-emailer-queue-endpoint) is approved (TSP 2024-02-15), publishes the `emails/v1` protobuf to `Public_SendEmail`, and supports two auth modes: member JWT and service `ddm-jwt` (added 2026-06-16).
- **Three services already call the endpoint** (listing-jobs-http-rest, feeds-ps-syncer, feeds-ps-transformer). Eight m-ksl-homes methods, most m-ksl-jobs flows, and four mieten flows also use it.
- **Seven modern services publish directly to the topic** and should move to the endpoint (Tier B in Services.md).
- **The biggest work item is the saved-search alert path.** It is a two-hop legacy dependency: saved-search-email-service and saved-search-alert-workers POST to six ksl-api endpoints, which render templates and choose the provider. This traffic explains the "unexplained CAPI email endpoint" note in the package.
- **ksl-api routes only `cars` and `classifieds` through the topic** (`PubSubEmail::shouldSendThroughMailgun`). Homes, jobs, rent, and communities alerts still go straight to Mandrill.
- **The stated homes blocker looks stale.** m-ksl-homes EmailController:912-913 says the endpoint lacks inter-service auth. The `ddm-jwt` service auth now exists and is in production use.
- **The consumer has 11 concrete defects** (duplicate sends after fallback, attachment corruption on the Mandrill path, template-only rejection, address leakage on multi-recipient sends, PII logging with DEBUG=1, no DLQ, no schema, no APM, and more — see Features.md F1).
- **Credential exposure is wider than the package states**: one Mandrill key literal in 12 files across ksl-api and m-ksl-jobs, a committed `sports/v2/mandrill.ini`, a second distinct key in `statsFromMandrill.php:62`, an airlock key in `examples/`, and hard-coded Bronto SOAP creds in ksl-news-api.
- **Some cleanup is already done**: the `mailgun-service` repo was archived 2024-01 and only ever held boilerplate; the ksl-api members Bronto endpoints are dead ("No longer available").
- **No NetCore email integration exists anywhere** — the provider decision stays open without code impact.
- project.json now tracks 13 repos (the 5 original + 8 core pipeline repos).

## Still Needs Research

- Verify that endpoint `ddm-jwt` auth unblocks the m-ksl-homes alert emails, and whether the endpoint form supports `tags` and `delivery_time` (Tier B needs both).
- Confirm the Datadog zero-traffic claims for `mailgun-service` and `AmazonsesAdapter`. SC-383437's comment trail shows the claims were written without Datadog access.
- Check the Airflow UI for `mandrill_messages_etls`. The DAG exists in both dbi-dags and dbi-dags-airflow3, so it likely still runs.
- Reconcile the two member-pipeline topic names: `projects/mailchimp-340018/topics/mailchimp-member` (ksl-member) vs `member-mailchimp-events` (member-backend).
- Confirm whether the pull subscription `Prod_SharedFeatures_SendEmail` has any consumer; it looks orphaned.
- Trace the member-api password-reset / activation email path (ksl-api delegates there; repo not yet researched).
- Collect volume baselines per sender (Datadog / Mailgun dashboards) for parity testing and metric targets.
- Sync the dirty, stale local ddm-protobuf checkout (behind 11, modified generated files) before any local proto research.

## Unanswered Questions

- **Q1**: Target provider — how long must the delivery contract stay provider-neutral, and who makes the final call?
- **Q2**: Does this package include the Go rewrite of the ksl-emailer-queue consumer, or only hardening in place?
- **Q3**: Convergence — is the central endpoint the single blessed path, retiring direct `PubSubEmail` publishes from PHP?
- **Q4**: Member pipeline ownership and migration plan (Justin Carmony / Chris Ward)?
- **Q5**: `mandrill_messages_etls` — retire, or preserve the BigQuery reporting dependency?
- **Q6**: The ~35 PHP `mail()` ops-alert sites — route through the queue, or replace with Slack/Datadog alerts and delete?
- **Q7**: KSL News Bronto newsletter signup (live SOAP in ksl-news-api) — in this package, or a separate product decision?
- **Q8**: Response-shape coupling — several callers parse Mandrill `reject_reason`/`status` arrays. What is the parity strategy when the response becomes queue-shaped?
- **Q9**: Should `isolate_recipients` become the default at the central endpoint to stop address leakage on multi-recipient sends?
- **Q10**: Who owns rotation of the exposed credentials (2 Mandrill keys, 1 committed ini, 1 airlock key, Bronto SOAP creds)?

## Research Sources Consulted

- **Notion**: Mailgun unification package (3c72ac5c…); Completely move to Mailgun (pubsub); Move all emails to Mailgun; Email Services: Who's using what? + Email Service Audit DB (11 rows); Mandrill » Mailgun move + Tech Debt • Mandrill; TSP Email Queue Endpoint; ADR 067 Transactional Email Templates; Mailgun next steps (project 012 scope); Email service replacement and migration (empty FRAMED shell).
- **Shortcut**: SC-383437 "Mail Client implementation research" (full description, 25 comments, 7 chokepoint subtasks 383967-383973; note: one comment cites ids 383960-383966 — mismatch).
- **GitHub org search** (deseretdigital): mailgun, mandrill, Public_SendEmail, PubSubEmail, bronto, sendgrid, mailchimp, "deseretdigital/email", AmazonSESAdapter, member-mailchimp-events, swiftmailer, PHPMailer, netcore, beeswax; repo listing for mail/email-named repos.
- **Local repo sweeps** (4 Explore agents, 2026-09-02): legacy PHP repos (ksl-api, m-ksl-classifieds-api, m-ksl-jobs, mieten, m-ksl-cars*, m-ksl-myaccount*, messages-service, alerts repos, peripheral repos); unified repos (marketplace-backend, marketplace-graphql, saved-search-*, push-notifications, reports, pricing, images, ddm-protobuf); ksl-emailer-queue deep-dive (contract, routing, infra, defects).
- **Remote file reads**: saved-search-email-service (email.go, app paths, .env.example), ksl-emailer-queue-endpoint (app.go, openapi.yml).

## Changelog

- 2026-09-02: Initial shaping pass. Added 8 core pipeline repos to project.json (ksl-emailer-queue, ksl-emailer-queue-endpoint, ddm-protobuf, email, m-ksl-homes, m-ksl-jobs, saved-search-email-service, saved-search-alert-workers). Wrote Features.md and Services.md from the full inventory. Synced local repos (ddm-protobuf skipped: dirty + behind 11). Synced findings to the Notion package SHAPING section.
