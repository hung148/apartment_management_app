# Release tasks — current queue

Started 2026-09-28. This is the single working list for finishing the release.
Work top to bottom, one task at a time. Tick a box only when its check has
actually been run and the result is recorded under the task. Detailed evidence
stays in [IAM rollout](IAM_ROLLOUT.md), [security evidence](SECURITY_VERIFICATION.md),
[release checklist](RELEASE_SECURITY_CHECKLIST.md) and
[implementation history](TEAM_ACCESS_IMPLEMENTATION.md).

**Client work (2026-09-30):** anh Hưng's requests (custom roles, Google sign-in,
short/long-term bookings, calendar bars, invoices, KPI, notifications, Sheet backup)
are planned in [CLIENT_ROADMAP.md](CLIENT_ROADMAP.md). Start there: finish the
PROFILE/STAFFLINK/NAV tests, then R1. G3/G4/G5/G6 are folded into that roadmap;
G8 (v2 creation + migrating his organization) must land before he uses them.

Baseline: commit `9ea3cf3` (Team and Access), pushed 2026-09-28. Roll back to
this commit if a release step goes wrong before deployment.

## Status overview

| # | Task | Status |
|---|---|---|
| G | V2 feature gaps (below) | **In progress** |
| 4 | Integration release decisions | **In progress** |
| 3 | Remaining security checks | Partly done |
| 1 | Clock and offline testing | Not started live |
| 2 | Full operational testing in staging | Not started |
| 5 | Migration and recovery rehearsal | Partly done |
| 6 | Monitoring and release preparation | Not started |
| 7 | Deploy to the existing app project | Not started |
| 8 | Retire broad Editor permissions | Not started |

Order is 4 → 3 → (1 + 2 together in staging) → 5 → 6 → 7 → 8. Each later task
depends on the one before it.

## V2 feature gaps (found 2026-09-28)

A version-2 organization opens `RoleWorkspace` instead of the legacy screen, and
Firestore rules deny direct client reads/writes for v2 data. Anything that only
exists in the legacy screen or writes Firestore directly does not work for v2.
Fix order below. Each fix = server callable (if needed) + client + tests.

Works in v2 today: team/invitations/access review, activity, property
create/details/layout/contract, rooms (rates, modes, schedules, deletion),
tenant name/phone, leases, roommates, rent changes, moves, move-out, bookings
list and operations, invoices, collections/refunds, housekeeping.

- [x] G1 Organization settings: dashboard shows a v2 owner as "Member"; no
  rename/contact/bank edit, delete or working leave (direct writes are denied).
  **Implemented 2026-09-28, waiting for Tom's test before ticking.**
  - Server: new `organizationSettings` callable (`functions/organization_settings.js`)
    with `read` / `update` / `leave` / `close`. Update needs `manageOrganization`
    and must send all 8 fields; activity stores changed field names only (no
    bank values). Leave: anyone except the owner. Close: owner only, exact name,
    revokes every membership (resumable after interruption), keeps records
    with `purgeAfter` = 30 days. Idempotent operation ledger
    `organizationOperations` (no client access).
  - Guards: closed organizations are hidden from `listMyOrganizations`, and
    invitation lookup/accept/request return `org_closed`.
  - Client: `OrganizationSettingsService`; dashboard shows the v2 role
    (Owner/Administrator/...), loads private details from the server for
    Info/Edit, hides legacy copy/migrate for v2, delete only for the owner,
    leave for every non-owner. New en/vi strings.
  - Copy to another organization (v2), added 2026-09-28: `copyPreview` / `copy`
    actions. Needs Owner/Administrator with all properties in BOTH
    organizations (+ export on source, import on target). Copies buildings,
    rooms, tenants, bookings, invoices/payments, lease occupancy, date
    corrections and their history subcollections with new IDs; every link is
    rewired. Team, staff, activity, housekeeping tasks and ledgers stay with
    the source. Retry with the same operation resumes onto the same records.
    "Copy and delete" = copy, then close the source (owner only).
  - Purge job, added 2026-09-28: `purgeClosedOrganizations` runs daily 03:15
    Asia/Ho_Chi_Minh. Deletes a closed v2 organization after `purgeAfter`
    (all records with its organizationId/orgId, linked legacy children and
    subcollections), leaves a `purgedOrganizations/{id}` record without names.
    Skips (and logs) if anyone is still active or a record links to another
    organization. Deploy note: needs the Cloud Scheduler API enabled in each
    project; staging endpoint count is now 32.
  - Analyzer cleanup: removed unused dashboard code, replaced deprecated
    `Color.value`.
  - Tests: 13 backend unit tests (shared in-memory Firestore in
    `functions/test/fake_firestore.js`), 2 emulator tests, 5 Dart service tests.
  - [x] Follow-up: scheduled purge job for closed organizations (implemented,
    same test round).
  - Automated results (Tom, 2026-09-28): `flutter analyze` (dashboard +
    service) no issues; Flutter 244/244; backend unit 77/77; emulator 86/86
    (includes both new G1 emulator tests).
  - Live staging round 1 (2026-09-28): backend release 32/32 ACTIVE, verify
    passed (purge private, 403 to outsiders; schedule 03:15 Asia/Ho_Chi_Minh).
    A (Owner badges) pass, B (owner menu) pass. C/D found: Info/Edit slow with
    no loader and could open several dialogs; edit refused valid emails.
    Fixed: details load when the menu opens + loader + one-at-a-time; shared
    email rule (`lib/utils/email_format.dart`, same as server, allows `+` and
    long endings). Same-pattern sweep also fixed: copy dialog Preview/Copy
    double-run, language Save double-pop, building-rent payment Save double
    tap (created duplicate payments). Retest C onward.
  - Live staging round 2 (2026-09-29): C, D, E, F, G, H, K pass. I: failure
    shown without the explanation; J: 30-day notice not seen. Fixed: copy
    status now sits above the buttons (outside the scroll area) and is red for
    errors, with messages for no-access target, linked records and timeouts;
    the 30-day notice is now the first thing in the v2 delete dialog.
    Retest I and J, then the purge test (Step 5).
  - Live staging round 3 (2026-09-29): I pass (asked to drop "version 2" from
    the text — done). J: notice visible; reported that a wrong name still
    allowed delete. Hardened: Delete stays disabled until the exact name is
    typed, and the typed text (not the saved name) is sent so the server's
    check really applies; Copy & delete now needs the same typed name.
  - Restore, added 2026-09-29: Settings > Recently deleted organizations lists
    organizations this account closed (until the purge date) with Restore.
    Server actions `closedList` / `restore`; close now stores each member's
    previous status and restore returns exactly that (suspended stays
    suspended, people who left stay out). Restore and purge claim the
    organization atomically, so a started restore is never purged.
    Tests: 16 backend unit (+3), 1 new emulator test, 1 new Dart service test.
    Needs a backend redeploy to staging.
  - Copy dialog reworked (2026-09-29, after Tom's review): the typed target ID
    is replaced by a list of the account's own organizations that can receive
    the copy. Situations covered: (1) only same-kind organizations with an
    active Owner/Administrator (legacy: admin) membership, never the source or
    a closed one; (2) none available -> notice, buttons disabled; (3) copy only
    needs a target, copy & delete needs target + exact source name (owner
    only); (4) changing the target clears preview/errors; (5) no double runs,
    dialog locked while copying; (6) server re-checks everything; (7) retry
    resumes onto the same records; (8) note that copying again makes a second
    set; (9) dashboard refresh / Recently deleted after copy & delete;
    (10) red plain-language errors above the buttons; (11) long names
    ellipsized, en/vi, narrow widths.
  - Live staging check: **passed 2026-09-29 (Tom)** — settings, leave, copy picker,
    copy & delete, close, restore and purge. G1 done. Tools: `tool/staging_release.cjs` (fresh
    restricted-identity backend release incl. the private purge schedule),
    `tool/staging_seed_v2.cjs` (synthetic v2 organizations),
    `tool/staging_verify.cjs` (now also checks scheduled functions are private).
- [x] Viewer role removed (2026-09-29, Tom's decision; live staging test passed). Six
  roles remain: owner, administrator, manager, receptionist, housekeeper,
  accountant. Any membership without a supported role (migrated v1 members
  with `assignmentRequired`, or a stored `viewer`) is a **waiting member**:
  the organization now shows on their dashboard with "Waiting for role",
  tapping explains who assigns roles, the menu offers only Leave (server
  allows leave for waiting members), and admins see "Assignment required" in
  Account access review. Pending viewer invitations say the role is gone and
  cannot be accepted. The "Viewer" label stays only so old history reads
  correctly. Seed tool: `--staff` (receptionist) and optional `--waiting`.
  Needs a backend redeploy.
- [x] G2 Account deletion: fails for any v2 member (direct membership delete is
  denied; v2 role is `owner`, not `admin`). App Store requires this to work.
  Built and live-tested by Tom 2026-09-29 (tests 1-7 pass). Server callable `deleteMyAccount`
  (preview / delete); the app deletes the login last. Situations covered:
  - Member of any organization: removed; v2 record kept as revoked with name
    and email wiped; legacy record deleted as before.
  - Owner with administrators: chooses per organization, hand over to one
    administrator (becomes owner, all buildings) or close for everyone.
    Owner with no administrator: close only. Confirm stays off until every
    owned organization has a choice.
  - Legacy sole admin: organization closed (purged after 30 days, the purge
    job now handles legacy too). Legacy with another admin: just leaves.
  - Closed organizations: other members' access revoked, purge after 30 days.
  - Personal data: owner profile, pending requests, AI usage/requests/drafts
    and entitlement deleted; staff profiles unlinked; activity kept.
  - Recent sign-in (5 min) re-checked by the server; password asked before
    and again if the dialog was left open too long.
  - Retry / double tap: one lock in the app; server run is resumable with the
    first choices; a hand-over that became impossible (administrator removed
    or demoted) stops and asks again, never closes silently.
  - Login removal fails after data is gone: signed out with a message to sign
    in and delete again (repeatable).
  - Navigation: goes to login with the whole stack cleared.
- [ ] PROFILE Settings > Personal information (Tom 2026-09-29), before the redesign.
  Built, waiting for Tom's test. Callable `myProfile` (update / syncEmail).
  - Name (required, 1-100) and phone (optional, 8-15 digits) saved by the
    server; the name is copied to every open membership (legacy and v2) and
    pending access request so teammates see it. Staff profiles (the
    organization's own records) are not changed.
  - Email: current password, then a confirmation link to the new address;
    the sign-in changes only after the link is opened. On the next start the
    verified email is copied to the profile and memberships.
  - Password: current password, new (6+ chars, different), confirm.
  - Forgot password: login screen link and a "reset link" in Change password
    (Firebase reset email; same message whether or not the email has an
    account). No "password changed" alert email yet (needs an email service).
  - Every save: one lock, busy button, inline errors (wrong password, email
    in use, too many attempts, offline), back button blocked while saving.
  - Also: new accounts now set the sign-in display name (legacy member lists
    used it and showed blank); settings gear hover now matches its square.
- [ ] STAFFLINK Accounts without a staff profile (found by Tom 2026-09-29):
  members who joined before v2 (waiting members) get access through "account
  access review" but have no staff profile, so they are missing from the staff
  list. Proposal: when an owner/administrator assigns them a role, create and
  link a staff profile from their name and email (server side). BUILT
  2026-09-29 in team.js setAccess (reuses a linked profile; code ACC-xxxxxx;
  none for revoke), waiting for Tom's test. Seed tool now
  creates a linked profile for --staff, like a real invitation.
- [ ] NAV Navigation (fold into the v2 screen redesign), reported by Tom 2026-09-29:
  - Inside the v2 workspace, Back goes straight to the dashboard instead of
    one step back (the workspace swaps ~12 on/off sub-screens inside one
    widget; system/browser Back and the top bar leave the whole organization).
  - The dashboard shows a Back button; pressing it opens the login screen with
    only the background image, stuck until reload, and the Back button stays.
    Dashboard must be a root page with no Back; login must redirect a signed-in
    user to the dashboard.
  - Done early (2026-09-29, with PROFILE): the app always starts at the splash
    (a reload no longer rebuilds inner screens without their data = blank
    page); login, logout and account deletion clear the history; signing out
    or switching account in another tab sends this tab to login/splash.
    Still to do in the redesign: Back inside the workspace.
- [ ] G3 Tenant profile: v2 stores only name and phone. Missing: gender, date of
  birth, ID number/issue date/place, email, emergency contact, deposit,
  vehicles, notes, documents/photo.
- [ ] G4 Statistics dashboard (KPIs, monthly trend, revenue by building).
- [ ] G5 Availability calendar grid (v2 has a bookings list only).
- [ ] G6 Receipts and exports: payment PDF, Excel export, organization reports.
- [ ] G7 AI chat data tools: denied for v2 (`ai_scoped_access_required`);
  needs role/property-scoped read tools.
- [ ] G8 v2 creation path built behind a release switch (staging on,
  production off) and migration tool `tool/migrate_v2.cjs` built (plan/backup/
  apply/undo/anonymized rehearsal). Remaining: staging rehearsal, then the
  production move (see Task 5 and CLIENT_ROADMAP G8).

---

## Task 4 — Integration release decisions (in progress)

Decisions (2026-09-28, Tom):
- AI chat assistant: **in this release**, free limit only (5 messages/day per
  account, enforced by the server).
- Subscription billing (RevenueCat / Apple): **off**. Apple billing setup is
  not available yet.
- AI import: **off** (recommended). It writes legacy records directly and uses
  device timezone offsets (TIME-08).
- Legacy reports/import/export: stay unavailable for v2 organizations.

Known limit: AI chat tools deny v2 organizations (`ai_scoped_access_required`).
After an organization migrates to v2, the assistant answers general questions
only and cannot read that organization's data.

- [ ] Add `lib/utils/release_features.dart` (`aiBilling`, `aiImport`, default off).
- [ ] Hide the "AI Pro" button and the "Import with AI" attach button in
  `lib/widgets/chat/chat_manager.dart` when the switches are off.
- [ ] Replace `aiImportPreview`, `aiImportCommit`, `aiSyncSubscription` with
  `feature_disabled` stubs and `revenueCatWebhook` with a 503 stub in
  `functions/index.js` (`RELEASE = {aiImport:false, billing:false}`).
- [ ] Update `test/chat_subscription_overlay_test.dart`: existing test turns
  billing on; new test proves both buttons are absent by default.
- [ ] Fix the usage text so it does not show imports while import is off.
- [ ] Confirm v2 organization screens cannot reach
  `organization_report_exports.dart` / `payment_excel_export.dart`.
- [ ] Staging: enable real AI chat with its own low-quota Gemini key
  (Secret Accessor for `app-ai-runtime` on that secret only). Keep import and
  billing disabled, including `aiImportCommit` (currently still live in staging).
- [ ] Verify in staging: chat works, the 6th message in a day is refused,
  disabled endpoints return `feature_disabled` / 503.
- [ ] Run `flutter test --concurrency=1` and `npm.cmd test`; record results here.

## Task 3 — Remaining security checks

Done already: callable App Check + rate limits + payload limits (source,
staging); genuine browser App Check and staging Firestore enforcement (2026-09-28).

- [ ] App Check token refresh: keep a staging tab open past token expiry and
  confirm calls still succeed.
- [ ] App Check failure: block the reCAPTCHA / App Check request in the browser
  and confirm a clear error with no data loss.
- [ ] Account recovery: password reset email works for the staging account.
- [ ] Session revocation: revoke refresh tokens / disable the account and confirm
  the open session loses access.
- [ ] Live abuse limits: burst past the invitation lookup limit (12) in staging
  and confirm `resource-exhausted`.
- [ ] Hosting headers: check `nosniff`, referrer policy, CSP and cache headers on
  the staging site.
- [ ] Error/log privacy: denied and failed calls show no internal details to the
  client; Cloud Logging has no tokens, emails or payloads.
- [ ] Refresh `npm audit`, `node functions/security_pub_audit.js` and
  `node functions/security_scan.js` on the final build.

## Task 1 — Clock and offline testing (staging)

Local/emulator evidence exists for C02, C04, C09–C11. Live runs are needed.
Record client offset/timezone, request, before/after data and result per row.

- [ ] C01 client clock −1 year / +1 year: create, edit, collect payment.
- [ ] C02 / C03 expired and revoked invitations (page left open, direct call).
- [ ] C04 / C12 forged timestamps, actor and status; direct audit writes denied.
- [ ] C05 overdue boundary and billing month under clock changes.
- [ ] C06 timezones UTC−12, UTC+14, Asia/Ho_Chi_Minh and a DST zone.
- [ ] C07 far past/future dates; backdating needs owner/admin + reason.
- [ ] C08 AI quota at day boundary with clock rollback.
- [ ] C09 / C14 go offline, revoke access, reconnect; server down during action.
- [ ] C10 / C11 two sessions, simultaneous collect/refund/check-out; repeated
  clicks. Confirm no duplicate payments.
- [ ] C13 PDF/export labels (only if export is in release scope).

## Task 2 — Full operational testing in staging

Follow [OPERATIONAL_WORKFLOWS_TEST_GUIDE.md](OPERATIONAL_WORKFLOWS_TEST_GUIDE.md)
against the staging site with synthetic data.

- [ ] Leases: create, future rent change, contract-end amendment.
- [ ] Room moves: roommate first, then main tenant; history kept.
- [ ] Move-out: occupancy ended, invoices and history kept.
- [ ] Bookings: create, edit, check-in/out, deposit, refund, conflicts.
- [ ] Invoices: create, edit fees, void, duplicate-period protection.
- [ ] Collections and refunds: partial, full, refund ceiling.
- [ ] Building expenses: rent-in expense and rent-out income.
- [ ] Two sessions at once on the same room/invoice: one wins, the other gets
  a clear conflict.
- [ ] Audit records exist for every successful action and none for denied ones.

## Task 5 — Migration and recovery rehearsal

Done already: 2026-09-26 inventory, authorized orphan cleanup with backup,
synthetic emulator migration rehearsal.

- [ ] Refresh the organization inventory from the existing project.
- [ ] Review legacy records: missing/duplicate owners, staff links, property
  timezones, client-written timestamps.
- [ ] Write the migration manifest (which organizations, what changes).
- [ ] Export a Firestore backup and restore it into staging.
- [ ] Rehearse migration on the restored staging copy.
- [ ] Rehearse rollback and confirm payments/audit data survive.

## Task 6 — Monitoring and release preparation

- [ ] Alerts: function error rate, permission-denied spikes, App Check
  failures, rate-limit denials, unexpected payment volume.
- [ ] Budget alert on the billing account (including Gemini cost).
- [ ] Merge `firestore.indexes.json` with the live index inventory and check
  every index is READY.
- [ ] Build artifacts: confirm the web build uses `lib/main.dart`, excludes
  preview/fixture/debug entries, and record the commit hash.
- [ ] Write the exact deployment and rollback sequence (below).

Deployment sequence: _to be written_.
Rollback sequence: _to be written_.

## Task 7 — Deploy to the existing app project

- [ ] Create the four restricted accounts in `apartment-management-app-776b9`
  and apply only the grants in IAM_ROLLOUT.md.
- [ ] Deploy functions with a fresh source bundle using the dedicated build and
  runtime accounts (the Firebase CLI cannot set the build account).
- [ ] Deploy indexes, then rules.
- [ ] Deploy the web client; build the mobile client with the same commit.
- [ ] Verify real traffic: Auth=VALID and App Check=VALID in logs.
- [ ] Enable Firestore App Check enforcement and read it back as ENFORCED.

## Task 8 — Retire broad Editor permissions

- [ ] Confirm no workload still runs as the default Compute or App Engine account.
- [ ] Save the current IAM policy and etag.
- [ ] Remove Editor from the default Compute and App Engine accounts.
- [ ] Re-test deploy and runtime after removal.
- [ ] Investigate the Google-managed Cloud Services agent separately (do not
  remove it automatically).
- [ ] Final check: old identities cannot read app data or secrets.
