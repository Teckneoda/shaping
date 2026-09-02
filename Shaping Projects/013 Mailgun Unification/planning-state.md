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
- **Template inventory is complete (2026-09-02).** The modern repos reference 11 Mailgun template names; no legacy repo uses one. About 60 emails render HTML in code; about 35 are designed emails that must move into Mailgun templates ([Services.md section 5](Services.md)). Three legacy producer transports and the two feeds clients cannot pass a `template` field yet.
- **Member pipeline correction:** `mailchimp-email-service` no longer sends through Mandrill. It renders Jinja2 templates and publishes the body to `Public_SendEmail`, so member emails already deliver through Mailgun. Phase 3 becomes template migration + endpoint adoption + topic reconciliation.
- Template drift found in the modern repos: the 2-listing subscription payment-failed template can never send (the code hardcodes the single-listing name), and two docs name templates that do not match the code's constants.
- **Consumer defect list corrected (2026-09-02, against the synced checkout — 26 commits newer than the first deep-dive):** now FIXED upstream: template-only messages are accepted, and `isolate_recipients` works end-to-end in both senders (opt-in, with a warning log on unmarked multi-recipient sends). Still open: rethrow after a successful Mandrill fallback (duplicate sends), Mandrill attachment double-base64, Mandrill errors thrown as plain objects, `DEBUG=1` payload logging in prod, single `MAILGUN_DOMAIN`, no DLQ/schema on the topic, no APM.

## Still Needs Research

- Verify that endpoint `ddm-jwt` auth unblocks the m-ksl-homes alert emails, and whether the endpoint form supports `tags` and `delivery_time` (Tier B needs both).
- Confirm the Datadog zero-traffic claims for `mailgun-service` and `AmazonsesAdapter`. SC-383437's comment trail shows the claims were written without Datadog access.
- Check the Airflow UI for `mandrill_messages_etls`. The DAG exists in both dbi-dags and dbi-dags-airflow3, so it likely still runs.
- Reconcile the two member-pipeline topic names: `projects/mailchimp-340018/topics/mailchimp-member` (ksl-member) vs `member-mailchimp-events` (member-backend).
- Confirm whether the pull subscription `Prod_SharedFeatures_SendEmail` has any consumer; it looks orphaned.
- Trace the member-api password-reset / activation email path (ksl-api delegates there; repo not yet researched).
- Collect volume baselines per sender (Datadog / Mailgun dashboards) for parity testing and metric targets.
- Sync the dirty, stale local ddm-protobuf checkout (behind 11, modified generated files) before any local proto research.
- Audit the Mailgun console: list the templates that exist there today, and compare against the 11 names referenced in code (does `classifieds 2 listings subscription payment failed` exist? do the drifted README names exist as orphans?).

## Unanswered Questions

- **Q4**: Member pipeline ownership and migration plan. Direction set 2026-09-02: Phase 3 is planned as scoped (templates + endpoint + topic reconciliation, TOTP preserved); Chris confirms ownership with Justin Carmony and Chris Ward before the build cycle starts.
- **Q10**: For the **Trufty and Platform teams** — credential end-of-life plan. Mandrill stays live until the migration completes, so the exposed key literals stay valid during the build. Is shutdown-at-end acceptable in place of rotation, or do the two Mandrill keys get rotated at package start? Separately: the airlock key in `ksl-api/examples` is not a Mandrill credential and needs its own verification and revocation.
- **Q13**: The CAPI dealer monthly report embeds CID images and a runtime-generated chart PNG. Move to hosted images in a template, or keep it body-based and migrate transport only?
- **Q15** (new, product decision): Where do Bronto newsletter subscriptions go? Q7 pulled the Bronto newsletter migration into this package (Phase 5), but the replacement destination (newsletter provider/list system) is a product decision. Blocks the Phase 5 build, not the shaping.

## Resolved Questions (2026-09-02)

- **Q1** → Keep the delivery contract provider-neutral until a provider decision is made. Mailgun stays the working default; provider-specific code stays in the downstream sender.
- **Q2** → The Go rewrite of the consumer is a **separate package**. This package fixes correctness defects in the Node consumer in place.
- **Q3** → The central endpoint is the **only** blessed publish path. Direct topic publishes retire, including ksl-api `PubSubEmail`.
- **Q5** → No Airflow action in this package. Document that the migration eliminates the Mandrill traffic that feeds `mandrill_messages_etls` and its BigQuery tables; the reporting owner decides the DAG's end-of-life.
- **Q6** → The `mail()` ops-alert sites route through the queue, as a stretch goal of the package.
- **Q7** → The Bronto newsletter migration is **fully in scope** (new feature F11 / Phase 5): ksl-news-api signup, ksl unsubscribe flow, dado signup. Spawned Q15 (destination).
- **Q8** → Fire-and-forget. A queued send returns only "accepted". The callers that parse Mandrill `reject_reason` (saved-search-email-service, nest-tools, homes) get rewritten to stop parsing rejection detail; bounce handling belongs to the Mailgun verification package (project 012).
- **Q9** → Verified: `isolate_recipients` support shipped end-to-end in recent commits (Mailgun batch-splitting with recipient-variables; Mandrill `preserve_recipients:false`; endpoint + proto fields). Decision: keep it **opt-in** with the warning log; the migration checklist adds the flag per multi-recipient sender.
- **Q11** → The build team decides the plain-text strategy. The options and the authored-text inventory stay documented in Services.md 5.5; do not lose the existing authored `.text.php` variants.
- **Q12** → Templates stay managed in the Mailgun console. Add a checked-in **template registry** (name, owner, variables, source reference) to stop name drift. No CI upload in this package.
- **Q14** → Scope-edge bundle accepted: Pick'em emails stay CMS/body-based; the jobs confirmation becomes one Mailgun template with a brand variable (ksljobs / siliconslopes); the `ksl` form emailer stays body-based. All three still migrate transport to the central endpoint.

## Research Sources Consulted

- **Notion**: Mailgun unification package (3c72ac5c…); Completely move to Mailgun (pubsub); Move all emails to Mailgun; Email Services: Who's using what? + Email Service Audit DB (11 rows); Mandrill » Mailgun move + Tech Debt • Mandrill; TSP Email Queue Endpoint; ADR 067 Transactional Email Templates; Mailgun next steps (project 012 scope); Email service replacement and migration (empty FRAMED shell).
- **Shortcut**: SC-383437 "Mail Client implementation research" (full description, 25 comments, 7 chokepoint subtasks 383967-383973; note: one comment cites ids 383960-383966 — mismatch).
- **GitHub org search** (deseretdigital): mailgun, mandrill, Public_SendEmail, PubSubEmail, bronto, sendgrid, mailchimp, "deseretdigital/email", AmazonSESAdapter, member-mailchimp-events, swiftmailer, PHPMailer, netcore, beeswax; repo listing for mail/email-named repos.
- **Local repo sweeps** (4 Explore agents, 2026-09-02): legacy PHP repos (ksl-api, m-ksl-classifieds-api, m-ksl-jobs, mieten, m-ksl-cars*, m-ksl-myaccount*, messages-service, alerts repos, peripheral repos); unified repos (marketplace-backend, marketplace-graphql, saved-search-*, push-notifications, reports, pricing, images, ddm-protobuf); ksl-emailer-queue deep-dive (contract, routing, infra, defects).
- **Remote file reads**: saved-search-email-service (email.go, app paths, .env.example), ksl-emailer-queue-endpoint (app.go, openapi.yml).

## Changelog

- 2026-09-02 (third pass): Worked all 14 open questions with Chris. Resolved Q1-Q3, Q5-Q9, Q11, Q12, Q14; Q4/Q10/Q13 remain open (Q10 reassigned to Trufty & Platform); added Q15 (Bronto destination, product decision). Verified against the synced consumer: template-only sends and isolate_recipients are fixed upstream; corrected the defect list. Scope changes: Go rewrite moved to a separate package; Bronto newsletter migration added as F11/Phase 5; mail() sites → queue as stretch; fire-and-forget response contract.
- 2026-09-02 (second pass): Template migration research. Added Services.md section 5 (full template inventory: 11 Mailgun templates in use, ~35 in-code HTML emails to migrate, transport gaps, plain-text strategy, process gap) and Features.md F10. Corrected the member pipeline (already publishes to Public_SendEmail; Jinja rendering remains). Added Q11–Q14.
- 2026-09-02: Initial shaping pass. Added 8 core pipeline repos to project.json (ksl-emailer-queue, ksl-emailer-queue-endpoint, ddm-protobuf, email, m-ksl-homes, m-ksl-jobs, saved-search-email-service, saved-search-alert-workers). Wrote Features.md and Services.md from the full inventory. Synced local repos (ddm-protobuf skipped: dirty + behind 11). Synced findings to the Notion package SHAPING section.
