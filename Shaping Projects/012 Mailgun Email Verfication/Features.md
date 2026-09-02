# Mailgun Email Verification — Features

Features come from the Notion doc's goals and acceptance criteria, mapped to the validated email pipeline. Order follows the Notion priority. Items at the bottom go first if scope is cut.

## F1. Verify new addresses at collection

- Verify each newly collected email address through the Mailgun validation API.
- First collection point: member signup (`POST /members` in member-backend).
- Store the result before, or soon after, the address enters active email flows.
- Open: block, warn, or verify asynchronously after submit (Q3).

## F2. Store a reusable verification status

- Store one status per address: `deliverable`, `undeliverable`, `do_not_send`, or `inconclusive`.
- Keep `undeliverable` and `do_not_send` as distinct outcomes.
- Record status, timestamp, source, and expiration.
- The store must cover non-member addresses too (listing contacts, Quick Apply, `members_stub`, `socialIdentityCaptures`). The member DB alone is not sufficient (Q1).

## F3. Suppress sends to bad addresses

- Sending systems check the stored status before a send.
- Suppress messages to `undeliverable` and `do_not_send` addresses.
- Primary candidate enforcement point: the `emailer-mandrill-transactional` Cloud Function. All `Public_SendEmail` traffic passes through it, and it already contains disabled blocklist code (Q2).

## F4. Backfill existing addresses

- Provide a documented backfill process for existing addresses.
- Estimate volume first: the 5,000 included validations cap the free tier; overage is $0.80 per 100 (Q6).

## F5. Re-verification cadence

- Re-check stored statuses on an agreed cadence, or on events that mark a status stale.
- Open: scheduled job or event-driven consumer (Q4).

## F6. Safe handling of temporary failures

- A temporary Mailgun failure must not mark an address as permanently invalid.
- Define retries, timeouts, and a fallback policy.
- Caution: the send-path Cloud Function uses `RETRY_POLICY_RETRY`; a thrown error retries forever (Q9).

## F7. Trufty fraud signal (decision required)

- Review `do_not_send` results with Trufty.
- Decide ownership and how the signal enters fraud workflows (Q5).

## F8. Volume and cost measurement

- Measure unique-address counts and expected re-verification frequency.
- Get approval for projected overage before rollout (Q6).
