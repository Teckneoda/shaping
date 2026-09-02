# Mailgun Email Verification — Services

## The validated email pipeline (account creation)

Chris Ward's description of the flow was validated in code on 2026-09-02. The full chain:

1. **Signup UI** — [`m-ksl-myaccount-v2`](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2): [create-account.tsx](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/pages/create-account.tsx) → Next API [register.ts:139](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/pages/api/v1/auth/register.ts#L139) → `POST https://member-api-V2.ddm.io/members` ([constants.ts:33](file:///Users/cpies/code/shaping/Research%20Repos/m-ksl-myaccount-v2/constants.ts#L33)).
2. **Router** — routes `POST /members` 100% to the Go service ([routing-rules.yaml:142-156](file:///Users/cpies/code/shaping/Research%20Repos/member-backend/apps/router/services/router-http-member-proxy/routing-rules.yaml#L142-L156)).
3. **member-backend** (Go) — persists to MySQL `member` + Mongo `members`, then publishes `{action, member_data}` to `projects/mailchimp-340018/topics/mailchimp-member`. Actions from signup: `email_verification` (normal path, [account_creation.go:469](file:///Users/cpies/code/shaping/Research%20Repos/member-backend/apps/member/services/member-http-rest/internal/domain/account_creation.go#L469)) and `account_exists` (duplicate path, `:357`). The publish is best-effort; a failure never fails signup.
4. **mailchimp-email-service** — in [`trufty-microservices`](file:///Users/cpies/code/shaping/Research%20Repos/trufty-microservices/mailchimp-email-service). Pull-subscribes `mailchimp-member-sub`, renders a Jinja template (12 actions → 7 templates), publishes an `EmailMessage` to `projects/ddm-platform/topics/Public_SendEmail` ([Generate_email.py:266](file:///Users/cpies/code/shaping/Research%20Repos/trufty-microservices/mailchimp-email-service/mailchimp_email_service/Generate_email.py#L266)). The name is vestigial — it makes zero Mailchimp calls. It is a renderer/relay, not a sender.
5. **emailer-mandrill-transactional** — in [`ksl-emailer-queue`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue/emailer-mandrill-transactional). A Cloud Functions gen2 Eventarc push consumer of `Public_SendEmail` ([email-mandrill-transactional.tf:77-86](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue/.tf/email-mandrill-transactional.tf#L77-L86)). Delivers via **Mailgun** (domain `ksl.com`, `ROLLOUT_PERCENTAGE=1` → 100%), Mandrill as fallback. From-domain whitelist: ksl.com, utah.com, thememories.com.

Other publishers to `Public_SendEmail` (they bypass any signup-time check):
- [`ksl-emailer-queue-endpoint`](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue-endpoint) — HTTP front door at `api.ddm.io/emailer-queue`, publishes at [app.go:41](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue-endpoint/app.go#L41). Used by logged-in-user flows and cron jobs (member token / interservice JWT auth).
- Legacy PHP: [PubSubEmail.php:11](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-api/public_html/classifieds/common/api/classes/PubSub/PubSubEmail.php#L11).
- `messages-email-notifications` (same ksl-emailer-queue repo).

Payload schema: [email_message.proto:8-34](file:///Users/cpies/code/shaping/Research%20Repos/ddm-protobuf/proto/emails/v1/email_message.proto#L8-L34) (`emails.v1.EmailMessage`). The consumer accepts camelCase and snake_case.

## Services to create

### email-verification service (NEW — shape TBD, see Q1/Q2)
- Calls the Mailgun validation API for new, backfilled, and re-checked addresses.
- Owns the shared status store (`deliverable` / `undeliverable` / `do_not_send` / `inconclusive`).
- Exposes the status to sending systems and collection points.
- A head start exists: `emailer-mandrill-transactional` has a written-but-disabled Firestore blocklist (`prod_email_queue_blocklist`) at [checkUserEmail.ts:25-65](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue/emailer-mandrill-transactional/src/helpers/checkUserEmail.ts#L25-L65), call sites commented out at [index.ts:95-106](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue/emailer-mandrill-transactional/src/index.ts#L95-L106) with a TODO that describes this exact project.

## Services to update

### member-backend
- Add a verification trigger at address collection (`POST /members`, and later `PATCH /members/{id}` email changes).
- Today the only check is a format regex ([login.go:138-141](file:///Users/cpies/code/shaping/Research%20Repos/member-backend/apps/member/services/member-http-rest/internal/handler/login.go#L138-L141)). No Mailgun client exists in the repo.
- Relevant fields: `emailValid` (set by the verify service), `emailFail` (exists, never written), `emailAllow` (hardcoded `false` at creation; the send path never reads it).

### emailer-mandrill-transactional (ksl-emailer-queue)
- Candidate enforcement point: enable a suppression check against the shared status store before delivery.
- Note: recipient filtering is computed but never applied to the actual send ([index.ts:92-125](file:///Users/cpies/code/shaping/Research%20Repos/Legacy/ksl-emailer-queue/emailer-mandrill-transactional/src/index.ts#L92-L125)).

### ddm-protobuf (possible)
- `EmailMessage` may need fields for verification metadata or suppression override, if enforcement lands in the consumer.

## Services documented, no change expected

- **mailchimp-email-service** — renderer/relay only; no suppression or validation logic today, and none planned here.
- **m-ksl-myaccount-v2** — signup UI; client-side regex validation only. UI messaging may change depending on Q3 (block vs warn vs async).
