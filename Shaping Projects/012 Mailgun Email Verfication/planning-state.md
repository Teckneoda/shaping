# Planning State — Mailgun Email Verfication

## Identified So Far

### Validated: the account-creation email flow (Chris Ward's description, 2026-09-02)
All three of Chris Ward's claims from `conversation.txt` were verified in code:

1. **Account creation is ported to member-backend — TRUE.** 100% cutover; the router sends all `POST /members` to the Go service. The signup UI (m-ksl-myaccount-v2) calls `POST https://member-api-V2.ddm.io/members`.
2. **Emails go out via pubsub through mailchimp-email-service, which does not use Mailchimp — TRUE, with corrections.** The service is a template renderer/relay, not a sender. It consumes `mailchimp-member` events and republishes rendered emails to `Public_SendEmail`. Delivery happens in `ksl-emailer-queue/emailer-mandrill-transactional` (Cloud Function) via **Mailgun** (100% in practice; Mandrill fallback). The signup email is a verification email (`email_verification` action), not a welcome email.
3. **The member API stores `emailAllow` without per-email-type detail — TRUE.** Single boolean, hardcoded `false` at creation, PATCH-updatable. The send path never consults it. Newsletter preferences live elsewhere (Pardot, legacy `setNewsLetter`, conversation prefs).

Full chain with code references: see [Services.md](Services.md).

### Gaps this project fills (evidence found)
- **No suppression or bounce handling exists anywhere in the chain.** `emailFail` exists in the member model but no service writes it.
- **A disabled blocklist scaffold already exists** in emailer-mandrill-transactional (Firestore `prod_email_queue_blocklist`; call sites commented out). Its TODO says: "a separate service that manages blocklists by checking bounces in Mailgun" — this package is that service.
- **Validation is regex-only at every layer** (UI, member-backend, sender). No Mailgun client, MX check, or third-party validation exists in any repo.
- **The Cloud Function is the single choke point** — all `Public_SendEmail` traffic passes it. Publishers (member flow, endpoint front door, legacy PHP, messages) would each bypass a collection-time-only check.
- **Non-member addresses exist**: listing email-seller senders, Jobs Quick Apply, `members_stub`, `socialIdentityCaptures` (30-day TTL). The member DB alone cannot store all statuses.
- Mailgun DNS (DKIM/SPF/DMARC, domain `ksl.com`) is already configured in ddm-platform.

### Side findings (not this project's scope, worth relaying)
- mailchimp-email-service acks then nacks the same message on a malformed payload (`Processor.py:48-53` falls through to a generic handler).
- emailer-mandrill-transactional computes recipient filtering but never applies it to the send (`src/index.ts:92-125`).
- Broken resend button in `CreateAccountForm.tsx:130-145` (posts `{resend:true}` to a route that ignores it).
- New accounts get `emailAllow=false` yet still receive verification emails; the flag gates nothing.

## Still Needs Research
- Mailgun account details: confirm the Scale package, validation-API access, and API key scope.
- Volume data: unique member emails, signups per month, non-member send volume — needed for Q6 cost math.
- Senders that do NOT pass through `Public_SendEmail` (e.g., Legacy `ksl-emailer-queue` other services, marketplace repos, Pardot) — do any need suppression too?
- The verify service (`apps/verify` in member-backend) — how `emailValid` interacts with a new verification status.
- Firestore blocklist scaffold: is `prod_email_queue_blocklist` an acceptable store, or is it too narrow (send-side only)?

## Unanswered Questions
- **Q1**: Where should verification status be stored? Member DB (misses non-members) vs the Firestore blocklist scaffold vs a new shared store/service. Must cover non-member addresses.
- **Q2**: Where is suppression enforced? The consumer choke point (emailer-mandrill-transactional) vs each publisher vs both.
- **Q3**: Signup-time verification: synchronous inside `POST /members` (adds Mailgun latency to signup) vs asynchronous after create? Which service calls Mailgun?
- **Q4**: Backfill and re-verification: scheduled job or event-driven consumer? What cadence?
- **Q5**: Does Trufty own `do_not_send` as a fraud signal? How does it enter fraud workflows?
- **Q6**: Expected validation volume and cost vs the 5,000 included validations ($0.80 per 100 overage)?
- **Q7**: How does the new status relate to existing fields? `emailAllow` gates nothing; reuse `emailFail`, or add new fields?
- **Q8**: Are non-signup collection points (email-seller, Quick Apply, legacy publishers, endpoint front door) in scope for verification at collection?
- **Q9**: How are `inconclusive`/temporary Mailgun results handled? Note: the Cloud Function's `RETRY_POLICY_RETRY` retries a thrown error forever.

## Research Sources Consulted
- [Notion: Mailgun verification](https://app.notion.com/p/deseret/Mailgun-verification-3b42ac5cb23580a0847ec44d7d2d12f5?v=2be2ac5cb23580cb882a000c3a41b92a) — framing, requirements, acceptance criteria, cost model. No open comments.
- [conversation.txt](conversation.txt) — Chris Ward's description of the signup email flow (validated above).
- [deseretdigital/member-backend](https://github.com/deseretdigital/member-backend) — account creation, pubsub publish, emailAllow/emailValid/emailFail, verify service. Local clone added 2026-09-02.
- [deseretdigital/trufty-microservices](https://github.com/deseretdigital/trufty-microservices) — mailchimp-email-service internals. Local clone added 2026-09-02.
- [deseretdigital/m-ksl-myaccount-v2](https://github.com/deseretdigital/m-ksl-myaccount-v2) — signup UI, member API surface, email collection points. Key findings re-verified after a 900-commit pull.
- [deseretdigital/ksl-emailer-queue](https://github.com/deseretdigital/ksl-emailer-queue) (local: `Research Repos/Legacy/ksl-emailer-queue`) — the Public_SendEmail consumer; Mailgun delivery; disabled blocklist.
- [deseretdigital/ksl-emailer-queue-endpoint](https://github.com/deseretdigital/ksl-emailer-queue-endpoint) — HTTP front door publisher to Public_SendEmail. Local clone added 2026-09-02 under Legacy.
- [deseretdigital/ddm-protobuf](https://github.com/deseretdigital/ddm-protobuf) — `emails.v1.EmailMessage` schema.
- ddm-platform — Mailgun DNS records; `/emailer-queue` ingress.

## Changelog
- **2026-09-02**: Initial shaping session. Read `conversation.txt`; validated Chris Ward's flow end to end across 4 repos with code references. Added repos `ksl-emailer-queue`, `ksl-emailer-queue-endpoint`, `ddm-protobuf` to project.json; cloned `member-backend`, `trufty-microservices`, `ksl-emailer-queue-endpoint` locally. Wrote Features.md (F1–F8) and Services.md. Opened Q1–Q9. Synced findings to the Notion doc's TECHNICAL DETAILS section.
