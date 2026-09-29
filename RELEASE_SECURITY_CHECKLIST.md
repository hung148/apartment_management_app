# Release security checklist

2026-09-27 hardening checkpoint: see [SECURITY_VERIFICATION.md](SECURITY_VERIFICATION.md)
for current evidence. Common callable App Check/rate/payload enforcement, client
attestation startup, patched dependencies and exact draft-expiry rejection are
implemented locally. A web reCAPTCHA Enterprise key was registered with explicit
authorization. Firestore remains unenforced pending coordinated cutover; three
service accounts retain broad Editor IAM grants. Historical findings below are
an audit trail, not a claim that the newer source lacks these protections. The
production release gates remain open until their live acceptance is completed.

Updated: 2026-09-27. Scope: Flutter web/mobile client, Firebase rules and callable
functions in this checkout, with emphasis on the Team & access v2 release.

Latest source integration: shared-code generic member creation is now denied;
Join submits access requests. Account review includes unlinked memberships.
V2 organization routes avoid legacy loaders, and dashboard organization summaries
come from `listMyOrganizations` with current membership checks. Deploy that
callable before the new client. These changes have not been deployed or verified
against real accounts; they do not clear production cutover gates.

Booking timezone checkpoint: property details now stores an explicitly selected,
server-validated IANA `timeZone`. V2 room operating hours are enforced in booking
creation/editing using that timezone, including weekday-specific multiple windows, date exceptions, overnight windows
and DST transitions. Date exceptions replace the entire local date, including
incoming overnight hours. Server validation is independent of the device clock. Current room
settings updates validate active schedules and serialize with bookings. This
partially addresses timezone configuration, but does not define billing due dates,
date-only imports, backdating, check-in policy or the legacy calendar's device-local
display. Existing properties still need explicit timezone review. Do not close
the broader time-policy gate based on this booking-only implementation.

**Release status: NOT approved.** This is a source-review checklist, not a
penetration-test certificate. Local regression and dependency checks passed;
live App Check, function runtime, Auth and project IAM metadata were inspected.
The approved web App Check key is registered. Application/functions/rules were
not deployed, Firestore enforcement remains off, and broad IAM grants and live
acceptance remain unresolved. See SECURITY_VERIFICATION.md for exact coverage.

2026-09-27 lease-date checkpoint: the user approved past move-in dates only for
owners/administrators, with a required reason. The v2 lease callable now enforces
that policy on creation and changed move-in timestamps using the configured
property timezone and server clock. Private correction records retain the reason,
actor, effective timestamps and server-recorded event time; general activity
omits the reason. Unchanged historical dates remain editable without requiring
a new correction. This is a partial TIME-04/TIME-05 fix, not closure:
move-out and other business-date policies remain pending. The new scoped
Add tenant / Start lease form and `tenantLeases` callable now implement date-only
entry/conversion, immutable creation retry, room revision checks and competing
occupancy/booking protection. These changes are locally tested, not deployed.
Deploy the replacement client flow together with this backend; old v2 callers
cannot backdate without supplying a reason. Linked roommate creation now has a
strict callable with parent/room revision checks, no implicit rent or deposit,
and the same backdating policy. Older v2 writes cannot detach active roommates
by moving/ending their main tenancy; coordinated moves/move-out and existing
lease-term changes still need dedicated workflows and acceptance.

Future rent checkpoint: the approved policy is a chosen future effective date.
The `tenantRent` callable stores dated exact-minor-unit changes with a fixed
schedule timezone, server date validation, tenant revisions, live lease/price
permissions and private before/after reasons. Existing invoices stay unchanged.
The v2 invoice workflow now consumes the dated rent resolver and prorates by
actual calendar days, rounding once to minor units. Existing invoices retain
their calculation snapshots. Contract-end amendments, room moves, move-out,
booking operations, invoice creation/fee editing/voiding, and rent-in expense
payments now have scoped source workflows. Moves retain historical occupancy;
linked roommates must be handled separately. Backdated move/move-out and invoice
period/due dates require owner/admin and a reason. Invoice and booking requests
persist exact operation IDs before network submission. Income collection rejects
expense records. Private histories retain reasons; generic activity omits them.

These source changes do not close live authorization, clock-manipulation,
migration or release-security gates. New callable dependencies (`leaseLifecycle`,
`invoices`, `bookingWorkspace`, `propertyLayout`) and updates to existing booking,
payment and tenant endpoints must be deployed together with the reviewed client.
Legacy invoices remain preserved; editing through the new fee editor requires a
v2 calculation snapshot. Legacy financial/report/AI paths must not be reopened
without completing their separate release checks.

2026-09-26 implementation checkpoint: `mutateStandalonePayment` now provides
server-timed, authorized, atomic collection/refund commands for existing v2
standalone invoices. Seven new emulator scenarios passed (37 total), including
forged timestamps, retries, concurrent collections and direct-write denial.
The Flutter command service passed three targeted tests. Forms and legacy
cutover are still pending; TIME-01/TIME-02 remain open. See
[implementation evidence and test commands](TEAM_ACCESS_IMPLEMENTATION.md#standalone-payment-command-checkpoint--2026-09-26).

For each gate, record owner, implementation/commit, test evidence, environment,
reviewer and sign-off date. An unchecked item is not cleared for release. If a
feature is deferred, prove that its endpoint and client route are unavailable in
the release scope; hiding a button alone does not count.

## 1. Device-clock findings

The client clock is attacker-controlled. Changing OS time is only one approach:
a modified client can submit arbitrary timestamps and call APIs directly. We do
not need to detect every clock change if the server owns security decisions.

`DateTime.now()` and `Timestamp.now()` in **Flutter** use the device clock.
`Timestamp.now()`/`Date.now()` in **deployed Cloud Functions** use the backend
clock. `FieldValue.serverTimestamp()` is a server-resolved write transform.
Reading a document with `Source.server` gives fresh data, not a trusted local
clock. A UTC conversion changes representation; it does not make client time
trustworthy.

| ID | Source-reviewed finding | Consequence and required action |
|---|---|---|
| TIME-01 | `lib/services/payments_service.dart`: `markAsPaid` and `updatePaymentStatus` write client `Timestamp.now()` to `paidAt`. `updatePayment` directly writes the supplied map. `addPayment` persists client model timestamps. `lib/screens/payment/edit_payment_dialog.dart` also creates local payment timestamps. | **Release blocker for legacy payment writes.** A wrong device clock can affect recorded payment time, and an authorized legacy client can supply arbitrary values. Move financial mutations to authenticated server transactions; generate recorded time and actor there. Do not just replace the UI clock. |
| TIME-02 | `firestore.rules`, `/payments`: eligible legacy members can create/update ordinary non-booking payments, without a timestamp field restriction. V2 organizations are denied through `legacyOrganization`. Booking-linked payment writes are already protected. | Timestamp changes in the service alone are insufficient: direct API writes must be denied or constrained. Verify the exact deployed rules. Existing broad legacy financial permissions need a reviewed replacement. |
| TIME-03 | `PaymentService.updateOverduePayments` uses `DateTime.now()` and batch-writes overdue status. No call site outside its definition was found in `lib` during this review. `Payment.isOverdue`, `daysOverdue` and payment reports also use client time. | The helper is a latent persistent-data risk if enabled; badges/report filters can already disagree across devices. Compute authoritative overdue status/fees on the server using an approved business timezone. Display-only estimates must not authorize charges or mutations. No automatic late-fee exploit was reproduced in this review. |
| TIME-04 | `lib/models/tenants_model.dart` derives contract-expiry information from device time. `TenantService.markTenantAsMovedOut` defaults to device now and calculates early/late notes; `moveTenantToRoom` uses local timestamps. | Define permitted effective move/contract dates, separate from immutable server-recorded event time. Validate backdating/future dates and require an authorized correction reason. These business dates may legitimately be in the past; blanket replacement with server now is incorrect. |
| TIME-05 | `functions/calendar.js` stamps booking creation, status/check-in/out, booking payments and audit events on the backend. Lease creation/update timestamps and actors are also overwritten on the backend. | Device-clock changes do not control those event timestamps. The backend still accepts business booking/lease dates and custom prices subject to existing validations. Explicitly approve early/late check-in, backdating and price policies; interval/overlap checks alone do not enforce those policies. |
| TIME-06 | `functions/team.js` creates invitation expiry and checks acceptance against backend time. `functions/team_read.js` uses backend time for invitation preview. | Existing protection against extending an invitation by changing the device clock. Add client-clock-skew and exact-expiry boundary tests before sign-off. Preview validity is not a grant: acceptance must always recheck. |
| TIME-07 | `functions/ai.js` derives quota periods and verifies entitlement expiry using backend `now()`. `functions/subscriptions.js` uses provider-verified subscription data and backend time. `functions/ai_import.js` validates draft expiry on the backend. | These decisions are not based on the user's OS date in reviewed code. Verify deployed configuration, retry behavior, expiry boundaries, sandbox rejection and concurrency in staging. Do not infer that client-side premium indicators are authoritative. |
| TIME-08 | `lib/screens/ai_chat/ai_import_dialog.dart` sends device-derived date offsets. `functions/ai_import.js` uses those offsets to turn imported date strings into stored instants. No organization/property IANA timezone policy was found in the reviewed models. | Define business timezone and date-only semantics before enabling imports for v2. A client offset is input, not proof of location or correct business time. Validate/derive conversion on the backend from the configured property timezone. |
| TIME-09 | Calendar “today”, date-picker defaults, contract badges, PDF generation labels and report month defaults use local time. Preview fixtures use local time intentionally. | Mostly display/default behavior; still test clock skew and timezone changes. A misleading PDF generated-at label must not be treated as a certified financial event time. Preview success does not validate server time. |
| TIME-10 | Several form line-item/history IDs use `DateTime.now().millisecondsSinceEpoch`. | Inventory persisted uses and replace uniqueness-critical IDs with UUIDs/Firestore IDs. Clock rollback and concurrent operations must not overwrite records. A timestamp is not an authorization token or guaranteed unique ID. |

### Required time model

- [ ] Keep immutable **recordedAt/createdAt/updatedAt** and actor identity server-owned.
  Use backend time or server timestamp transforms; deny forged direct writes.
  Existing creation time must not be replaced during ordinary updates.
- [ ] Separate **effective business dates** (payment received date, move-in date,
  booking interval, invoice due date) from event-recording time. Define which
  roles can backdate/change them, allowed range, reason, and review requirements.
- [ ] Introduce an explicit organization/property IANA timezone policy. Store
  instants as UTC and calendar-only dates as dates where appropriate. Define
  due-date end-of-day, billing-month and DST behavior. Do not infer timezone from
  language, currency, browser settings, or a supplied offset.
- [ ] Derive invoice totals, fees, refunds, eligibility, expiry and quota resets
  on the server. Repeat checks inside the committing transaction.
- [ ] Clock-skew warnings may compare a server-provided time with device time
  for UX. They must never be the security boundary. If added, use a monotonic
  elapsed timer, account for network delay, and resync after resume/reconnect.
- [ ] Offline state cannot grant access, renew expiry, mark a payment confirmed,
  or bypass checks. Revalidate membership and expiry when a queued action reaches
  the server; show pending/failed accurately. Never fall back to local financial
  authorization when the server is unavailable.
- [ ] Review historical client-generated timestamps before migration. Do not
  silently relabel them as verified server timestamps or guess missing dates.

## 2. Mandatory clock-manipulation test matrix

Run with seeded staging/emulator data and test accounts, never by changing the
production server clock. Prefer an injected client clock or isolated browser/VM.
Keep backend time independent: changing `Date.now()` in a shared client/server
test process can invalidate the experiment. Large OS changes can break TLS/auth;
record that separately from an authorization failure.

| Test | Action | Expected result |
|---|---|---|
| C01 | Client clock -1 year / +1 year; create, edit and collect payment | Recorded timestamps and actor come from backend; totals/rights unchanged. Business dates follow the explicit date policy. |
| C02 | Move clock backwards after invitation expiry; accept by direct callable | Expired invite rejected; no membership, staff linkage or success audit created. |
| C03 | Keep acceptance page open until expiry or revoke invitation on another device | Final acceptance rechecks server state and fails; stale preview cannot grant access. |
| C04 | Forge `createdAt`, `updatedAt`, `paidAt`, actor, expiry and status in requests | Server rejects or ignores forbidden fields; direct Firestore writes are denied. |
| C05 | Clock rollback/forward across overdue boundary and billing month | No premature persisted overdue status/late fee, no avoided overdue charge, consistent reporting under the approved business timezone. |
| C06 | Change timezone only: UTC-12, UTC+14, Asia/Ho_Chi_Minh and a DST zone | Same business date/amount/rights across devices; localized display can differ intentionally. Test DST gaps and repeated times. |
| C07 | Client requests dates far in past/future or malformed offsets | Policy enforced server-side, regardless of date-picker limits. Corrections require allowed role/reason and are audited. |
| C08 | Clock rollback at AI quota/subscription/draft-expiry boundaries | No extra quota or restored entitlement; backend/provider determine validity. |
| C09 | Offline request, then expire invite/revoke role before reconnect | Mutation rejected on reconnect; no optimistic success retained. |
| C10 | Two devices disagree on time; concurrent collection/refund/check-out | One consistent balance; retries do not double-charge or duplicate success audits. |
| C11 | Repeated same-millisecond actions and backwards clock while generating IDs | No collision/overwrite; stable operation keys for retries. |
| C12 | Forged historical audit timestamp and direct audit update/delete | Denied; server timestamp and authenticated actor remain authoritative. |
| C13 | Inspect PDF/export after changing clock | Financial event dates remain authoritative; generated-at/display labels do not masquerade as verified payment time. |
| C14 | Server unavailable during time-sensitive action | Clear retry/pending state; no local fallback authorization or misleading saved status. |

For every row save expected vs actual results, client offset/timezone, independent
backend time, request payload, relevant before/after database state, actor/role,
and transaction/audit outcome. Sanitize identifiers and never attach credentials.

## 3. Authorization and tenancy gates

- [ ] Complete v2 operational reads/writes before enabling `accessVersion: 2`.
  Preview-only navigation is not a production migration.
- [ ] Verify every callable binds authenticated UID, active membership,
  organization and target property; cross-property moves must authorize both.
  Never trust client role, UID, organization membership, amount or scope flags.
- [ ] Test all seven roles, no-assignment scope, unknown/legacy roles, suspended
  and revoked accounts, self-change, owner protection and admin peer protection.
- [ ] Verify direct SDK/REST attempts as well as UI paths: field injection,
  protected collection writes, legacy endpoints, cursor tampering and cross-org IDs.
- [ ] Close legacy member creation and broad legacy mutation paths at the
  coordinated cutover. Review every existing member; do not auto-promote.
- [ ] Verify invited verified email matches the authenticated account. Test
  expiry, revocation, duplicate acceptance, account collision and privilege loss
  of the inviter before acceptance.
- [ ] Server-SDK code explicitly enforces policy: Admin SDK bypasses Firestore
  rules. Firestore rules alone cannot protect a flawed callable. See [Firebase's
  field-security documentation](https://firebase.google.com/docs/firestore/security/rules-fields).
- [ ] Ensure sensitive projections, exports, AI tools and future Drive/Sheets
  imports enforce the same scope. Audit history can contain amounts and must not
  become a way for unauthorized roles to read financial data.

## 4. Money, audit and data-integrity gates

- [ ] Replace general client-side legacy payment updates with server-owned,
  allowlisted operations; enforce integer minor-unit/currency rules, balance,
  refund ceilings and permission overrides inside transactions.
- [ ] Retry/double-click/concurrent execution tests for all money and access
  operations. Test changed payload under reused operation ID and partial failure.
- [ ] Create immutable audit entries atomically with successful mutations;
  record actor, target, server time, relevant changes and correction reason.
  Denied operations must not create misleading success events.
- [ ] Complete audit coverage for standalone payments and other remaining
  mutation paths. Current booking/lease audit coverage does not cover every path.
- [ ] Retain only necessary audit/export data; exclude secrets, guest ID numbers,
  contact details and free-text private notes from broad logs.
- [ ] Deploy and verify required indexes, including chronological activity
  indexes, after merging with the existing live index inventory. Test real
  staging queries; the emulator does not establish production index availability.

## 5. Abuse protection, authentication and integrations

- [ ] Review authentication providers, verified-email policy, privileged-account
  protection, account recovery, session revocation and authorized domains.
- [ ] Configure/test App Check for supported release platforms, then enforce on
  relevant callable/Firestore endpoints. Source enforcement and Flutter startup
  integration are implemented and a Hosting-domain key is registered; live token
  acceptance and Firestore enforcement remain pending. App Check supplements authentication/authorization; it is
  not protection against an authorized user supplying malicious input. See
  [callable enforcement](https://firebase.google.com/docs/app-check/cloud-functions).
- [x] Add per-user/per-organization abuse limits for invite/code lookups,
  requests, mutation attempts, exports and costly endpoints. `maxInstances` is
  capacity control, not a per-user rate limit. Locally implemented/tested; deploy
  and monitor real traffic before treating production as protected.
- [ ] Validate request size, field allowlists, types, string lengths, date ranges,
  file content/size and reference relationships. Reject ambiguous imports.
- [ ] Verify provider webhook authenticity, idempotency and out-of-order handling;
  production subscription entitlement cannot come from client claims or sandbox.
- [ ] Audit secrets in repository history and built artifacts without printing
  their values. Provider keys/service-account credentials stay server-side in
  managed secrets with least-privilege IAM. Firebase client configuration alone
  is not a substitute for security rules and is not automatically a secret leak.
- [ ] Before enabling Drive: least-privilege OAuth scopes, server-side token
  storage/revocation, account/org binding, spreadsheet ownership checks, import
  authorization and protection against formula injection in exports.
- [ ] Verify Hosting HTTPS/security headers and compatible CSP in staging;
  inspect external dependencies, dependency advisories, logs and error responses.
  Record vulnerabilities with owner and resolution; do not assume clean status
  from a successful build. Current npm and Pub/OSV scans found no known advisories;
  Hosting header/CSP source is added but has not been exercised in staging.

## 6. Deployment and release sign-off

- [ ] Inventory deployed rules, functions, indexes, Hosting build and provider
  settings; compare versions with the reviewed source.
- [ ] Use a staging Firebase project and separate test accounts/data. Exclude
  preview entry points, fixtures, emulator/debug switches and secret files from
  the production artifact. Confirm the build entry point is `lib/main.dart`.
- [ ] Rehearse migration, backup/restore and rollback. Rollback must not restore
  broad legacy access or discard valid audit/payment data without review.
- [ ] Run applicable full Flutter regression (`--concurrency=1`), server and
  rules/emulator suites, then staged real-account and cross-device testing.
- [ ] Run C01–C14 above. Record remaining gaps; do not count source review as
  a completed adversarial clock-manipulation test.
- [ ] Configure monitoring for permission-denied spikes, unexpected payments,
  abnormal quotas, function failures and billing cost; test incident response.
- [ ] Resolve release blockers or disable the affected feature with verified
  enforcement. Obtain owner approval of the concrete release and residual risks.

## 7. Suggested implementation order

1. Server-owned standalone payment operations, trusted recorded timestamps,
   transactional balances and denial of bypass writes (TIME-01/TIME-02).
2. Approve the business timezone/backdating policy; implement server overdue,
   effective-date validation and import conversion (TIME-03/TIME-04/TIME-08).
3. Add clock-skew/forged-payload/offline/concurrency regressions C01–C14.
4. Finish remaining v2 authorization/audit coverage and migration rehearsal.
5. Verify App Check, abuse limits, secrets/IAM, staged deployment and sign-off.

## Evidence and limitations

The paragraph below describes the initial checklist-only review. Current
implementation, scan/test results, configuration changes and remaining limits
are recorded in SECURITY_VERIFICATION.md and supersede that initial scope.

This checklist was created by source inspection and official documentation
review. No clock-manipulation experiment, new security test run, production scan,
dependency vulnerability scan, deployment or exploit attempt was performed in
this checklist task. Prior project test results are recorded separately in
`TEAM_ACCESS_IMPLEMENTATION.md`; they do not certify these new checklist gates.

Key source references: `lib/services/payments_service.dart` (addPayment,
updatePayment, markAsPaid, updatePaymentStatus, updateOverduePayments),
`lib/models/payment_model.dart` (isOverdue/daysOverdue),
`lib/services/tenants_service.dart` (markTenantAsMovedOut/moveTenantToRoom),
`functions/calendar.js`, `functions/team.js`, `functions/team_read.js`,
`functions/ai.js`, `functions/ai_import.js`, `functions/subscriptions.js`,
`functions/index.js`, `firestore.rules`, `firebase.json` and the existing
`functions/test/team.integration.js` / `firestore.integration.js` scenarios.

Firebase documents `request.time` as server evaluation time, including equality
with server timestamp transforms on relevant writes. If direct client timestamp
writes remain intentionally supported, test a field policy such as requiring a
new server timestamp to equal `request.time`, together with identity, scope,
allowed-field and immutable-field checks. A client merely choosing to send a
server timestamp is insufficient without enforcement. See [Firestore Request
reference](https://firebase.google.com/docs/reference/rules/rules.firestore.Request).
