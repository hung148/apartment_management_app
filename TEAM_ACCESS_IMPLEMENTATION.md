# Team & access implementation

## Staging security progress — 2026-09-28

Deployed the separate staging backend with dedicated runtime/build accounts,
rules and indexes. Live authenticated role/property/App Check acceptance passed;
all 238 Flutter tests passed. This does not finish the existing project's IAM
cutover or genuine browser/clock/offline release verification. Current details:
[IAM rollout](IAM_ROLLOUT.md) and [security evidence](SECURITY_VERIFICATION.md).

The staging web release is live. Genuine browser App Check passed and staging
Firestore enforcement is enabled: valid browser loads succeed; missing/invalid
App Check profile reads are denied. Clock/offline tests and the existing project's
Editor removal are still pending.

## Current completion status — 2026-09-27

Security hardening checkpoint: common callable App Check, transactional abuse
limits, client attestation startup, dependency fixes and security regressions
are implemented. The Firebase Hosting web key is registered; runtime enforcement
and least-privilege IAM remain coordinated release work. See
[security evidence and remaining gates](SECURITY_VERIFICATION.md).

This summary supersedes old checkpoint TODOs below; the chronological notes are
retained as implementation history, not a single current task queue.

- Core Team & access source implementation is largely complete: explicit roles,
  property scopes, staff versus account access, invitations, review/assignment,
  suspension/revocation, role workspaces, and activity views are connected and
  tested locally. New generic-member creation is removed from the new flow.
- Operational replacements now include collection/refund forms for existing
  invoices, housekeeping, basic property/room CRUD with protected deletion,
  room rates and rental modes, operating schedules, whole-building contract
  editing and authorized contract history browsing, plus the tenant directory and
  name/phone contact editor, main-tenant creation with a monthly lease, and linked
  roommate creation, future-dated rent scheduling, and private rent-change history.
- The operational replacement batch is implemented locally: lease contract-end
  amendments, individual roommate/main-tenant moves and move-out with retained
  occupancy history, scoped booking operations and server pricing, invoice
  creation/fee editing/voiding, rent-in expense payments and rent-out income,
  and property layout/defaults. See the batch checkpoint and combined guide.
  Legacy record review and broader security/time-policy acceptance are release
  gates; they are not automatically satisfied by the local source implementation.
- Release work remains: reviewed migration/backup plan for remaining organizations,
  current index reconciliation, coordinated backend/rules/client deployment, and
  live role/scope/revocation and release-security acceptance. Local tests do not
  close these gates. The earlier authorized orphan cleanup is recorded separately;
  old replacement-owner TODOs for those deleted organizations are historical.

There is no reliable percentage or release ETA yet: the remaining items differ
substantially in size. Core access features are close; the complete operational
replacement and production cutover are not yet complete.

## Operational completion batch — completed locally

User requested completing this entire batch before providing manual test steps.
This is the current batch queue; old chronological TODOs are not separate tasks.

- [x] Lease terms: existing future-dated rent changes, contract-end amendments and private history.
- [x] Room moves: household review, destination authorization, conflict protection,
  retained occupancy history and unchanged existing invoices.
- [x] Move-out: household review, occupancy end and retained financial/history data.
- [x] Bookings: scoped list/details, creation/editing, rate calculation, transitions,
  collection/deposit/refund/checkout, timezone-aware entry and conflict handling.
- [x] Invoices: server-calculated dated rent, fees, duplicate-period protection,
  creation/editing/voiding with immutable payment history and authorized adjustments.
- [x] Building finance: rent-out invoices and rent-in expense recording/history,
  explicit direction, currency, due dates and preserved contract snapshots.
- [x] Remaining property settings: inventory floor/prefix/type/area defaults,
  explicit review of changes, and no silent rewriting of existing rooms.
- [x] Integrate all entry points, preview fixtures and English/Vietnamese strings.
- [x] Targeted backend/UI regressions, full sequential Flutter/emulator regression,
  representative rendered visual review, and final combined manual test guide.

Approved business rules: prorate by actual calendar days in the property timezone;
handle each linked roommate separately before the main tenant moves or leaves;
allow past move/move-out/invoice effective dates only for owner/admin with a reason.
Production deployment and organization migration are outside this implementation
batch and remain separate release gates.

## Interactive local preview

### Add tenant / Start lease — implemented locally

The Tenants directory now opens a scoped main-tenant creation form for owners,
administrators and assigned managers. It collects name, optional phone, room,
move-in date, monthly rent and optional contract end date. Only owners/admins
may backdate, with a required reason. Linked roommate creation is also available
from the directory. Existing lease editing, room moves, move-out, deposits and
invoice creation remain separate future increments.

The `tenantLeases` callable supplies paginated room options and server-owned
timezone/currency/today metadata. Its strict creation request verifies current
access, selected room revision and property timezone. Dates are converted on
the server to the first real instant of the chosen local day; skipped whole
dates are rejected. Rent uses exact minor units. Atomic writes create the
tenant, immutable operation result, general activity and private backdate reason
when applicable. No payment or deposit collection is inferred.

Active or suspended occupants (including roommates/legacy occupants without a
main-tenant flag) and active bookings block overlapping open-ended occupancy.
Contract expiry does not free the room; explicit move-out is required. Room
revision writes serialize concurrent creates, bookings, rate changes and room
deletion. The older v2 tenant endpoint also rejects a competing main lease.
Room options are not an availability promise: the form says availability is
checked when saving. A historical tenancy already explicitly moved out is not
created by this form.

Manual preview check:

1. Select Owner and Riverside. In Property details, choose Asia/Ho_Chi_Minh and
   save if the property has no timezone yet.
2. Open Tenants → Add tenant / Start lease → room 102. Enter a name and monthly
   rent such as `1500000`. Use the displayed current date, then create the lease.
   Return to Tenants and verify the new contact appears.
3. Reset sample data, configure the timezone again, and choose room 101. A valid
   submission must report an occupied-room conflict and create no new tenant.
4. As Owner, enter a date before the displayed current date. Saving requires a
   reason. As Manager, that past date is rejected; today/future dates are allowed.
5. Switch to Vietnamese and enlarge text. Labels, messages and save/reload/room
   selection controls remain scrollable. Reset restores disposable data.

The preview uses a fixed simulated current date, `2026-09-27`, and does not
contact Firebase. Real clock, authorization, concurrency and audit behavior are
verified separately in backend tests. Live browser/account acceptance remains
pending; this is not deployed and no release gate is closed.

From the repository root run:

```powershell
flutter run -d chrome -t lib/team_preview.dart
```

This separate entry point opens the real team widgets with disposable in-memory
fixtures. It never initializes Firebase. It is not a migrated organization or
an authentication/security test. Reloading the browser resets all changes.

1. The owner directory contains Anh and Linh. Open details to edit a profile or
   create an invitation. Open Invitations & access requests to review the seeded
   request for Anh; explicitly choose Anh and assign a role/property scope.
2. Expand Local preview at the top and select Open recipient. Enter
   `demo-invite`, preview it and accept. This simulates a verified recipient.
3. Use the preview controls to return to the owner directory. Linh now has a
   linked account; open details to manage its access.
4. Reset sample data restores the starting state. Switch English/Vietnamese
   using the same controls. New invitation references can also be used in
   recipient mode. No emails are sent and no real accounts are created.

The preview transport intentionally models only these UI workflows; production
authorization remains covered by the independent backend/emulator tests.

Preview validation: its two targeted tests passed, including local acceptance,
idempotent retries, fresh-store reset and the populated shell in both languages,
phone/landscape/desktop sizes and 100%/130%/200% text. Representative Roboto
screenshots were inspected. The separate JavaScript web build passed; Flutter
reported dependency compatibility warnings for its optional Wasm dry run.
This is not live-account or browser-interaction verification.

## Progress

### Operational replacement batch — 2026-09-27

Source implemented as one user-requested batch. New `leaseLifecycle`, `invoices`,
`bookingWorkspace` and `propertyLayout` callables are connected to scoped role
workspaces, disposable preview fixtures and English/Vietnamese forms.

- Lease: contract-end amendments do not free occupancy; moves/move-out are actual
  date-only events, preserve prior occupancy intervals, lock source/destination
  rooms and check current scopes, currency, monthly mode and conflicts. Main
  tenants cannot leave active linked roommates behind. A roommate can move into
  an existing main tenancy or leave separately. Past dates require owner/admin
  and a reason. Legacy writes cannot inject new occupancy fields or bypass the
  dedicated move/move-out/contract-end workflow. Private lease history is retained.
- Billing: actual calendar-day proration consumes dated rent amendments and
  property-specific occupancy intervals; round once in minor units. Invoice
  periods are end-exclusive, whole-building contract ends inclusive. Quotes are
  revision checked, overlapping periods blocked, and saved calculation/contract
  snapshots preserved. Fee/due-date edits cannot reduce totals below collections;
  unpaid invoices can be voided, and paid invoices require refund first. Correct
  principal/period via void/reissue. Custom tenant charges calculate unit price
  times quantity. Rent-in is expense and rent-out income; income collection rejects
  expenses. Expense payment/reversal and invoice/collection histories are private.
- Booking: property-local time entry handles skipped/repeated DST hours; server
  rates support hourly and started 24-hour daily/overnight blocks. Price overrides
  require authority and a reason. Revision checks, operating windows and historical
  tenant occupancy protect saves. Confirm/check-in/cancel/no-show, payment,
  deposit/refund, booking-payment refund and checkout retain financial history.
- Property: floor counts, prefix, default type and area describe inventory and
  prefill new rooms without rewriting existing room details/rates/bookings.
- Recovery: invoice and booking commands persist their operation IDs before sending
  and restore exact retry requests by account/organization/property. Other forms
  retain pending operations while mounted. Current backend authority is checked
  even for retries. No production data or deployment was changed.

Validation: 237 full Flutter tests passed sequentially, 54 backend unit tests
passed, all 82 Firestore emulator scenarios passed again after the final guard
hardening, and targeted static analysis is clean. The final emulator run includes
the occupancy-injection and booking property-revision guards.
Additional financial-history UI assertions passed. Populated operational forms
were rendered across English/Vietnamese, 320/812/1440 widths, 100/130/200% text,
and both themes with actual fonts; representative screenshots were inspected.
No live deployed-account/browser acceptance was performed. Core transaction,
authorization, proration/DST and retry assertions are distinct from preview tests.

Combined manual acceptance: [OPERATIONAL_WORKFLOWS_TEST_GUIDE.md](OPERATIONAL_WORKFLOWS_TEST_GUIDE.md).
Deployment, migration/legacy-data review, index reconciliation and the separate
release-security checklist remain open. The new fee editor deliberately requires
v2 calculation snapshots; old invoices are retained for reviewed migration and
the existing guarded collection/refund workflow.


### Rent-change history — 2026-09-27

Implemented a read-only, paginated history view from Tenants and Rent schedule.
It shows schedule/replacement/cancellation events, previous and next planned
amounts, effective date, recorded timezone, reason, actor account reference and
server save time (UTC). An absent planned entry is explicitly labelled; it does
not imply zero rent or a change to an invoice. Returning to the rent editor
preserves an unsaved draft. Former tenants can be reviewed from the directory.

The history callable rechecks current organization, tenant/property identity,
`manageLease` and `overridePrices` on every page. It orders tied timestamps by
record ID, returns 20 entries per page, validates same-tenant cursors and projects
only display fields, omitting internal fingerprints/results. Direct Firestore
reads remain denied. The UI clears records after permission/identity denial,
ignores late responses after a context switch and supports older-page retries.

Manual test: run `flutter run -d chrome -t lib/team_preview.dart`. As Owner,
configure Riverside's timezone, open Tenants → Rent schedule for Nguyễn Thị Minh
Anh, schedule a future rent with a reason, then replace and cancel that date.
Open Rent-change history and check all three events, before/after amounts,
reasons and actor. Enter an unsaved reason in Rent schedule, open history and
return; the draft should remain. The directory also opens history directly.
Preview records reset when the preview reloads.

Validation: all 229 Flutter tests passed sequentially (`--concurrency=1`),
50 backend unit tests and 78 Firestore emulator tests passed; targeted static
analysis is clean. History tests cover pagination/retry, permission denial,
late responses, former tenants, preserved drafts and before/after values.
The populated UI matrix covers English/Vietnamese, 320/812/1440 widths,
100%/130%/200% text and both themes with actual fonts. Rendered English desktop,
Vietnamese narrow phone at 200% dark, and Vietnamese landscape at 130% light
screenshots were inspected. Live deployed accounts were not tested.
Deployment/live-account acceptance and invoice-generation integration remain
separate release gates.

### Future rent schedule — 2026-09-27

The user chose a future effective date for changed rent. Tenants now offers Rent
schedule for explicit active/suspended main tenants without a recorded move-out,
subject to both `manageLease` and `overridePrices` in the current property scope.
The form displays original rent, today's applicable rent and dated changes. It
supports scheduling/replacing a future date and cancelling a future change,
with a required reason. Applied dates cannot be changed here. Dates must be after
server-derived today and no earlier than the tenancy start. Up to 60 dated
entries are supported; the original rent remains the baseline.

`tenantRent` checks strict payloads, live authority, tenant revision, currency
and timezone; exact retries reuse the immutable result. Each write atomically
stores a private before/after history record under the tenant and a general
activity entry without the reason or financial amount. The schedule timezone is
fixed on its first edit so later property timezone edits do not shift agreed
dates. The legacy v2 tenant endpoint cannot replace rent or inject a schedule.
Room, dates, roommates, original rent and existing invoice/payment records are
preserved. No client clock or background job is needed to calculate rent today:
the server resolves the latest effective entry for that local date.

`rentForDate` is the shared server resolver for the pending invoice-creation
workflow. That workflow must integrate it and establish billing-period/proration
rules before release. Legacy scalar invoice defaults do not consume the schedule
and must not be reopened for v2. This increment does not generate invoices,
prorate bills, edit contract end dates or expose private history browsing.

Manual preview: select Owner → Riverside, configure its timezone, then open
Tenants → Rent schedule on Nguyễn Thị Minh Anh. Enter `2026-10-01`, `2000000`
and a reason; save and reload. Original/current rent remains `1500000` before
the effective date. Saving `2026-10-01` again replaces that planned amount.
Select its cancellation button, enter a reason and confirm to remove it. Today
(`2026-09-27` in the fixed preview) and earlier dates must be rejected. A manager
without price-override permission has no rent editor. Reset restores sample data.

Focused tests: `flutter test --concurrency=1 test/tenant_rent_test.dart`.
Validation: all 224 Flutter regression tests passed sequentially (9m06s), plus
50 backend unit tests and 77 Firestore emulator tests. Covered future-date
boundaries, replacement/cancellation, current-rent resolution, permission and
scope denial, unchanged invoices, private history, exact retries, concurrent
writes and legacy bypass rejection. Fixed a nondeterministic roommate test that
reused a completed operation ID; its booking-conflict assertion remains intact.
The four rent widget tests also cover hidden price access, loading/unavailable
states, ignored late responses, validation, lost replies and stale/denied saves.
Populated forms were tested in English/Vietnamese, phone/landscape/desktop,
100%/130%/200% text and both themes. Representative actual-font desktop,
Vietnamese landscape and enlarged dark-phone screenshots were visually reviewed;
the tests reported no layout exceptions. Analyzer: no issues in seven edited
Dart files. No deployment, live-account acceptance or live browser verification
has been performed.

### Linked roommate creation — 2026-09-27

The Tenants directory offers Add roommate on explicitly identified active main
tenants without a recorded move-out. The shared creation form displays the main
tenant, room, earliest move-in date, property timezone and server date. It asks
for name, optional phone and move-in date; no rent or deposit fields are shown.
Owner/admin backdating requires a reason; managers can use today/future dates.

The strict `tenantRoommates` callable rechecks live scope, parent and room
revisions, timezone, monthly rental mode and conflicting bookings. It creates an
occupant with `isMainTenant:false` and `mainTenantId`, without rent, deposit,
contract charges or payments. Date-only entry cannot precede the parent's local
move-in date; on the same date as an older midday-start tenancy, the actual
instant is clamped to the parent's start. Retry identity and private backdating
evidence follow the main-lease workflow. Suspended, former, moved-out, unknown
main-tenant flags and roommate parents are rejected.

The older v2 endpoint cannot create or change roommate occupancy/financial terms,
promote roommates, or move/end/change a main tenancy with active/suspended linked
roommates. Contact edits remain possible. A dedicated coordinated move/move-out
workflow is still pending; these guards prevent leaving linked occupants behind.
Creation serializes against room writes and detects parent changes. Existing
records are not automatically relinked or repaired.

Manual preview: select Owner → Riverside, configure its timezone in Property
details, then open Tenants → Add roommate on Nguyễn Thị Minh Anh. Enter a name
and the displayed current date, save and return to Tenants. The new row shows
its main-tenant reference and has no Add roommate action. A date before
2026-09-01 is rejected for this fixture; a past date on/after that date requires
an owner/admin reason. Manager cannot backdate. Reset sample data between runs.

Verification: 49 backend unit tests and 75 Firestore emulator tests passed.
Coverage includes roles/property scope, parent status/identity, parent and room
revision conflicts, concurrent roommate creates, booking conflict, private
reasons, exact retry and changed-payload rejection, no financial records, and
legacy promotion/creation/move-out bypass rejection. Thirteen targeted tenant
widget tests passed before the final reason-text correction; the three roommate
tests passed again after it. The incorrect reason message was reproduced with
a failing regression test before fixing it in the shared form.

Populated layouts were exercised in English/Vietnamese, 320px phone/812px
landscape/1440px desktop, 100%/130%/200% text and both themes, with actual fonts.
Representative screenshots were rendered and visually inspected, including
long names, parent context and the corrected reason error. No Flutter layout
exceptions occurred in those checks. All 220 Flutter regression tests passed
sequentially in 8 minutes 37 seconds. Analyzer found no issues in the seven
edited Dart files.
No deployment, live browser interaction or live-account verification has been
performed. The new callable must ship with its client.

Focused test command: `flutter test --concurrency=1 test/tenant_roommate_test.dart`.

### Main tenant and lease creation — 2026-09-27

Implemented the workflow described above, including English/Vietnamese messages,
paginated room selection, required timezone guidance, field validation, occupied
room errors, reload after stale settings, frozen exact retry after an uncertain
reply, and clearing private form data on denied access. Context changes ignore
late responses. The existing contact-directory navigation exposes the new form.

Verification so far: all 49 backend unit tests and 73 Firestore emulator tests
passed, including exact retries/changed payloads, role/property scope, stale
currency/timezone, owner/admin reasons, server-recorded metadata, date-only
conversion/DST/skipped dates, main-tenant conflicts through the older endpoint,
competing lease creates and a booking racing a lease. Five targeted widget tests
passed, including validation, pagination, loading/empty/error states, property
changes, denied/stale saves and lost replies. Tested the populated form in both
languages, 320px phone/812px landscape/1440px desktop, 100%/130%/200% text and
both themes with actual fonts. Rendered and inspected representative desktop,
Vietnamese landscape and enlarged English/Vietnamese phone screenshots; added
spacing between bottom actions after inspection. Final analyzer: no issues in
the seven edited Dart files. The full sequential Flutter regression suite passed
all 217 tests in 6 minutes 39 seconds.

Repeat the focused form tests with:

```powershell
flutter test --concurrency=1 test/tenant_lease_test.dart
```

No production deployment, real Firebase account acceptance, or live browser
interaction was performed. Existing rooms query indexes are reused; deployment
still requires index reconciliation and the new `tenantLeases` callable.

### Lease move-in date policy — 2026-09-27

Implemented the first backend increment for tenant creation. Version-2 lease
creation and changes to an existing move-in timestamp now require the property's
configured timezone. The server compares property-local calendar dates against
its own current timestamp. Owners/admins need a nonblank reason (maximum 1,000
characters) to backdate; other roles cannot backdate, even with a supplied reason.
Existing scoped lease authorization remains required.

Server-owned `moveInLocalDate` and `moveInTimeZone` are stored on new or changed
move-in dates. Client attempts to replace those fields on unrelated edits are
ignored. Existing historical dates can remain unchanged during other authorized
edits. Backdating reasons are stored atomically in private
`leaseDateCorrections` records with actor, server event time and before/after
move-in timestamps. They are omitted from the tenant document and general staff
activity feed; direct client access to these records is denied by current rules.
Create retries do not duplicate evidence. Legacy v1 behavior is unchanged.

This does **not** complete the Add tenant form, date-only conversion at entry,
roommate/competing lease policy, future-start presentation, lease move-out policy,
or a private correction-history UI. Old v2 callers creating a historical tenant
without a reason now receive an error; deploy the replacement form together with
the backend. No production deployment was performed.

Validation: reproduced the manager-backdating bypass with a failing regression
test before the fix. All 48 backend unit tests, 71 Firestore emulator tests and
212 Flutter regression tests passed. Covered property-local day boundaries/DST,
today/future manager entry, owner/admin reasons and invalid reasons, missing
timezone, changed-date corrections, forged metadata, unchanged historical edits,
retry evidence deduplication, revoked access, private reason records and direct
client-write denial. Corrected an emulator test's Admin-versus-client Timestamp
fixture before the successful run. No UI changed, so no new rendered screenshot
or live-app verification was performed. No production deployment was performed.

To repeat the focused backend tests from the repository root:

```powershell
node --test functions/test/lease_dates.test.js functions/test/calendar.test.js
```

The full Flutter regression command is `flutter test --concurrency=1`. There is
no new preview form in this increment; Add tenant / Start lease remains next.

### Tenant directory and contact editing — 2026-09-27

Validation: all 212 Flutter tests passed sequentially, 44 server unit tests and
70 Firestore integration tests passed, and targeted seven-file Dart analysis was
clean. The new directory/contact suite includes five behavioral/layout tests.

The property workspace now offers Tenants to accounts with manageLease for the
selected property (owners, administrators and assigned managers under current
roles). The paginated directory includes active, inactive, suspended and former
tenants. It shows name, phone, room reference and tenant status. The editor changes
only name and phone; this is not yet tenant creation, lease terms, room movement,
move-out, identity-document management, or invoice generation.

The tenantContacts callable validates organization/property/tenant identity,
live permissions, strict write fields and document revision. Name is required
and limited to 160 characters; phone is optional and limited to 80. Exact retry
commands return the original result, changed retry payloads are rejected, and
concurrent edits against one revision cannot both commit. Existing rent, deposit,
currency, room, status, dates and private identity fields are preserved. Server
update timestamps/actors and activity commit atomically. Activity exposes changed
field names and room/property references, not the contact values. Reads project
only the directory/contact fields; private IDs and financial terms are excluded.
The tenant organization/building/document-ID index is included in both index
manifests; deployment and live index reconciliation remain pending.

UI read or permission failures clear loaded tenant data; stale edits require
reload, uncertain outcomes lock the payload for exact retry, and late responses
from another property are discarded. Pending retries remain in memory only while
the screen is mounted. Directory pages are ordered by document ID, 25 per page.
Room IDs are labeled as references; room-label lookup/search and broader tenant
workflow controls are not included in this increment.

Manual preview:

```powershell
flutter run -d chrome -t lib/team_preview.dart
```

1. As Owner or Manager, select Riverside in Your workspace and open Tenants.
2. Edit the name/phone of the active tenant, save, and reload. Return to the list
   and verify the updated contact. Try the moved-out tenant too: status stays put.
3. Clear the name or enter more than 80 phone characters: saving must be blocked.
4. Switch to Receptionist, Housekeeper, Accountant or Viewer: the Tenants action
   is not available under the current role policy.

The preview is disposable UI data, not a live authorization test. Automated
coverage includes scoped/foreign reads, pagination, field projection, forbidden
lease/financial patches, concurrent writes, immutable retries, stale revisions,
revocation, former tenants and preservation of lease data. Populated English and
Vietnamese directory/editor error states were exercised at phone/landscape/desktop
sizes, 100/130/200% text, and both themes. Representative actual-Roboto screenshots
were visually reviewed. No deployment, live account verification or production
writes occurred.


### Contract history browsing — 2026-09-27

Validation: all 207 Flutter tests passed sequentially, 44 server unit tests and
68 Firestore integration tests passed, and targeted analysis was clean. No live
account/browser verification, production writes, or deployment occurred.

Whole-building contract now offers Contract history. Authorized property/lease
managers can read saved versions newest first, with actor account ID, UTC save
time, saved details and expandable previous details. The view is read-only;
returning preserves the current unsaved editor draft. There is no restore or
history-deletion action. Historical IDs are shown rather than guessed names.

The propertyContract history action rechecks current v2 membership and property
scope for every page. It returns at most 20 versions plus an opaque cursor, with
createdAt/document-ID ordering to handle identical timestamps. Cursors must
refer to a history record in the requested property. Responses explicitly project
contract fields and omit operation fingerprints/results and unknown fields.
Direct Firestore access to contract history remains denied. Initial read or
permission failures clear data; a transient older-page failure keeps prior rows
and permits retry. Late responses from another property are ignored.

Manual test: in the local preview, save a whole-building contract, change its
amount or direction and save again. Open Contract history; the newest saved
version appears first. Expand Previous version to compare. Return to the form,
make an unsaved name change, open history and return: the draft remains. A fresh
property with no contract saves shows the empty state. Reloading the browser
resets all preview data.

Coverage includes two-page reads with tied timestamps, foreign/invalid cursors,
revoked and out-of-scope accounts, response field privacy, draft preservation,
loading/empty/error and late-response states, older-page retries, and populated
expanded en/vi layouts at phone/landscape/desktop sizes, 100/130/200% text and both
themes. Representative actual-font screenshots were visually inspected.


### Whole-building rent-in / rent-out contracts — 2026-09-27

Validation complete: all 203 Flutter tests passed sequentially, 44 server unit
tests passed, and 67 Firestore integration tests passed. Targeted analysis of
seven changed Dart files was clean. Contract screenshots were generated in 36
language/size/scale/theme combinations and representative phone, landscape and
desktop populated/error captures were visually reviewed.

The user selected support for both directions. The property workspace now offers
Whole-building contract to owners, administrators and scoped managers with both
manageProperty and manageLease. Users explicitly choose Rent in (pay a landlord)
or Rent out (receive rent from a whole-building tenant). The form records one
current contract: party name/phone, monthly rent in the property's currency,
monthly due day, start/end dates, active/ended status, and notes. Ended contracts
require an end date. Dates are validated YYYY-MM-DD values from 2000 to 2199,
not device-local timestamps. Due days are contractual references; shorter-month
invoice dates must still be confirmed when billing is implemented.

The new propertyContract callable checks current membership and scope, property
identity, revision, currency, strict payloads and exact integer minor amounts.
It updates only rentalContract and server-owned update metadata. Every save keeps
an immutable before/after snapshot under the property's rentalContractHistory;
the history is server-only in this increment (no history browser yet). General
activity shows direction/status without contacts, notes or amounts. Retry payloads
are bound to an operation and current authority, and concurrent edits cannot both
commit against the same revision. Properties with contracts/history cannot be
removed through empty-property deletion, including ended contracts.

Legacy management/renter fields remain unchanged and are shown in an expandable
review section. No direction is inferred or migrated automatically. Old date
values are shown as recorded for review, without automatic timezone conversion.
This does not create invoices, record income/expenses, generate recurring bills,
change room availability, or update the old building-rent reports. Those remain
separate operational tasks; deployment is required before real-account use.

Manual preview checks:

```powershell
flutter run -d chrome -t lib/team_preview.dart
```

1. As Owner or Manager, select the property in Your workspace and open
   Whole-building contract (alongside Property details, outside Manage rooms).
2. Choose Rent in. Enter landlord, monthly rent, due day 1–31 and start date
   such as 2030-01-01. Save, reload, and verify the details.
3. Choose Rent out and verify the party label describes a tenant. Save/reload.
4. Mark Ended without an end date: saving must be blocked. Enter an end date
   on or after the start date and save again.
5. Try an invalid date or due day 32; saving must be blocked. Switch preview
   role to Receptionist: the contract action should not be available.

Preview data is disposable and does not connect to Firebase. Targeted tests cover
workspace navigation, both directions, USD cents and VND precision, invalid dates,
ended-date requirement, lost-response exact retries, stale edits, revoked access,
loading/read failures, and late responses after property switching. The populated
form and error state were checked in en/vi, 320px phone, 812px landscape, 1440px
desktop, 100/130/200% text, and both themes. Actual-font screenshots were inspected;
scrolling initially discarded validation state and enlarged Vietnamese labels
initially clipped currency. Both were reproduced in tests and fixed with retained
coverage. No live account/browser verification or production writes were performed.


### Shared room settings preservation — 2026-09-27

The shared Room model now retains the weekly operating schedule and date
exceptions when reading Firestore data, serializing, and copying a room for
unrelated edits. A regression test first reproduced the schedule being omitted.
The same test then reproduced copyWith resetting USD currency to VND; copies now
preserve currency too. Nested schedule data is defensively copied and immutable
inside the model; serialization returns an independent mutable snapshot. Legacy
rooms without weekly schedules omit the new key and retain their daily hours.
This does not enable legacy direct writes for v2 organizations or change server
validation, calendar rendering, rates, or stored bookings.

All existing Room model settings now have Team & access editing coverage: basic
room details, rental mode and rates (including daily threshold), minimum duration,
cleaning buffer, and daily/weekly/date-specific operating windows. The next
operational continuity work is the remaining property settings and tenant/booking
workflows. No new screen or production deployment is included in this checkpoint.

Validation: all 198 Flutter tests passed sequentially, including three new model
regression tests; targeted analysis was clean. Both schedule loss and currency
reset were reproduced before their fixes. No layout changed, so no new screenshot
review was needed for this model-only checkpoint. No live account verification
or production writes were performed.

Targeted regression command:

```powershell
flutter test --concurrency=1 test/room_schedule_model_test.dart test/widget_test.dart
```


### Weekly operating windows and date exceptions — 2026-09-27

Manage rooms > Booking settings now retains the same-hours-every-day option and
adds Weekly schedule and date exceptions. Each weekday supports up to six
non-overlapping windows. Up to 60 unique property-local dates (2000–2199) can
replace normal hours for late opening, early closing, or a full-date closure.
Removing a date exception restores the recurring weekly schedule.

Overnight windows remain supported. A weekday with no windows starts no new
window, but may inherit overnight hours from the preceding weekday. A date
exception replaces the entire calendar date, including that incoming overnight
portion. Its own overnight window may continue into the next date, unless that
date also has an exception. Every booking must fit a single window; adjacent
windows do not combine into one stay. Disable operating limits for unrestricted
multi-day stays. Overlaps across midnight and the Sunday/Monday boundary are
rejected, including conflicts between exceptions and normal hours.

The server applies the property timezone, including DST folds and gaps. It
validates the whole schedule, current authorization and revision, and refuses
changes that invalidate active bookings. Changes serialize with booking writes
and property timezone changes. Audits use server time. Older clients cannot
silently erase a saved weekly schedule by omitting its new field. Existing daily
hours need no migration. The Firestore schedule uses a weekday map (`0` Monday
through `6` Sunday) and a date-keyed exceptions map, each containing window maps;
there are no nested arrays.

Manual local-preview check:

```powershell
flutter run -d chrome -t lib/team_preview.dart
```

1. Open the owner/manager workspace. Set the property's timezone in property
   details if needed, then open Manage rooms > Booking settings for a room.
2. Enable operating-hour limits and choose Weekly schedule and date exceptions.
   Give Monday 08:00–12:00 and 14:00–22:00; set Tuesday to 10:00–17:00.
3. Add date exception, enter a YYYY-MM-DD date, and add 11:00–15:00 to open late
   and close early. Add another date with no windows for a full-day closure.
4. Save and reload. Check both weekdays and both exceptions. Edit the closed date
   or choose Restore weekly hours to remove its exception, then save again.
5. Try overlapping windows or an invalid/duplicate date: saving must be blocked.

The preview is disposable in-memory UI, not a booking-security test. Backend
integration coverage checks actual Firestore persistence, active-booking conflicts,
booking/date enforcement, old-client protection, timezone guards, and the booking
versus date-closure race. Server unit coverage includes exact boundaries, lunch
breaks, overnight carry, closed dates, DST transitions and invalid schedules.
UI coverage includes hidden-date validation, immutable retries, independent
weekdays, save/reload/close/restore, and populated en/vi phone/landscape/desktop
layouts at 100/130/200% in both themes. Actual Roboto screenshots were inspected;
a stale date-summary issue was reproduced and fixed with retained coverage.
Validation: 43 server unit tests and 65 Firestore integration tests passed. The
full Flutter run passed 194 of 195 tests; the new hidden-date test needed to scroll
to the offscreen message before asserting visibility. After that test-only
correction, all five schedule tests passed. No application edits followed the full
run. Targeted Flutter analysis was clean. The visual matrix exercised 36
language/size/scale/theme combinations and generated 72 weekly/date captures;
representative phone, landscape and desktop captures were visually reviewed.
Live browser/account acceptance remains unverified.

The legacy calendar's rendering remains device-local; calendar visualization and
broader billing/import time policies are not completed by this feature. No live
Firebase writes or deployment were performed.

### Empty-room deletion — 2026-09-27

Manage rooms > Edit room details now offers Delete empty room to owners and
administrators with all-property scope. Managers retain room editing/creation
but cannot delete. Confirmation displays the saved room number, explains history
protection, and offers Keep room. Return to Manage rooms after success to refresh.

The roomDetails delete command checks live authorization, organization/property/
room identity and revision. Any linked tenant, booking, payment or housekeeping
record blocks deletion regardless of status or missing legacy organizationId.
Recorded before/after room references in activity also block deletion, protecting
rooms whose tenant or booking has moved. Nested room collections block deletion.
Creation/edit activity is retained and deletion adds a server-owned audit event.
No linked records are cascaded or silently rewritten.

Immutable retries return the original result, including after the empty parent
property was subsequently removed, while still requiring current authorization.
Changed retry payloads are rejected. Room deletion serializes with booking/tenant
creation and updates the parent inventory timestamp. UI tests cover cancel,
blocked deletion, lost replies, revocation, stale revisions and context switches.
Pending requests are kept only while the screen remains mounted; browser reload
persistence is not implemented. Legacy history never recorded with a room link
cannot be reconstructed by this check and requires migration review.

Manual preview checks:

1. As Owner, open Manage rooms > room 102 > Edit room details. Choose Delete empty
   room, then Keep room. Confirm the room remains.
2. Repeat and Confirm room deletion. Return to Manage rooms; room 102 disappears.
   Activity history retains the deletion event.
3. Try room 101: its housekeeping record blocks deletion and the room remains.
4. As Manager, the deletion action must be absent. Repeat in Vietnamese.

The preview simulates task/activity links; server history guards and concurrency
are independently tested with Firestore emulator fixtures. No production writes,
deployment or live-account verification were performed.


Validation: all 190 Flutter regression tests passed sequentially, all 63 Firestore
emulator tests passed, and all 39 server unit tests passed. Targeted analysis of
seven changed Dart files is clean. The confirmation matrix covers English and
Vietnamese, narrow phone, phone landscape and desktop, 100%/130%/200% text, both
themes and a long saved room name. Representative actual-font screenshots were
visually inspected. Tests verify cancellation, directory refresh, blocked history,
role restrictions, exact retries, revocation, stale revisions, late responses and
concurrent booking/tenant creation. These are local automated and rendered-fixture
checks; live browser/account verification and deployment remain pending.

### Empty-property deletion — 2026-09-27

Property details now offers Delete empty property to owners and administrators
with all-property scope. Managers retain editing/creation permissions but cannot
delete properties. The inline confirmation names the saved property, explains
permanent deletion and provides a Keep property action. After success, return to
the workspace to refresh its list. Creation/edit activity history is retained,
and deletion adds a server-timestamped audit event.

The callable validates live authorization, input keys and the property revision.
It refuses deletion when rooms, tenants, bookings, payments or housekeeping tasks
reference the property, including completed/cancelled records and legacy records
without organizationId. Membership and invitation references also block deletion;
no staff scopes are silently rewritten. Nested collections and embedded building
rental-contract data block deletion. There is no cascade or historical-record
delete capability. Room creation and property deletion cannot both commit.

Identical deletion retries return the stored result even after the property is
gone, but still require current permission; changed commands are rejected. The
screen locks conflicting actions while confirmation or an uncertain request is
pending. Stale revisions require reload; revoked access clears the form. Pending
commands are retained only while the screen is mounted, not across browser reloads.
The preview simulates room/task blocking; full history and assignment protection
is tested independently in the Firestore emulator.

Manual check in the local preview:

1. As Owner, create a disposable property without rooms. Open Property details,
   choose Delete empty property, then Keep property. Confirm it still exists.
2. Repeat and Confirm deletion. Return to Your workspace; it should disappear.
   Check activity history for the deletion event.
3. Try Riverside, which has rooms: deletion must be blocked and its data retained.
4. As Manager or Receptionist, the deletion action must be absent. Repeat in
   Vietnamese and with enlarged text.

No production deployment or live data changes were performed. Historical-record
deletion and archiving remain separate unfinished tasks; empty-room deletion is now covered above.


Validation: 185 full Flutter regression tests passed sequentially, 60 Firestore
emulator tests passed, and 39 server unit tests passed. Targeted analysis of the
six changed Dart files is clean. Deletion coverage includes cancel, nonempty
blocking, retries after lost replies, revocation, stale-revision recovery, late
responses, historical/assignment/rental-contract guards and a concurrent room
creation race. The en/vi confirmation matrix covered phone, landscape, desktop,
100%/130%/200% text and both themes. Representative actual-font screenshots were
visually inspected. Live browser/account and production deployment checks remain
unperformed; these results are local tests and rendered fixtures.

### Property creation and pricing translation repair — 2026-09-27

The workspace now offers Create property to active owners, administrators and
managers with all-property scope. Selected-property accounts cannot create new
properties, even if they submit a forged request or guess its ID. The form is
available when an organization has no properties. Name, address, an explicit
valid timezone and VND/USD currency are required. Asia/Ho_Chi_Minh is suggested
for new properties and can be changed before saving; existing properties retain
their prior timezone. New rooms inherit the chosen property currency.

Creation uses the propertyDetails callable with prepareCreate/create actions.
The server validates the current organization version, membership, role and scope,
rejects client timestamps/actors and other unknown fields, and atomically creates
the property, operation ledger and activity event. Repeated identical operations
return the original result, changed intents are rejected, and concurrent attempts
cannot overwrite an existing property ID. Authorization is rechecked on retries.
The screen retains an immutable command after an uncertain reply and disables
leaving/reloading until it is resolved; it does not persist retries across browser
reloads. Switching context ignores late responses. After success the same form
becomes the ordinary property editor; returning to the workspace refreshes the list.

This completes basic property creation. Bulk floor/room generation, building
rental/management settings and property/room deletion remain unfinished. No staff
memberships or scopes are automatically changed, and no production deployment,
migration or live-account test was performed.

The pricing warning was a duplicate translation key: the report exchange-rate
message overrode the room-price validation message. A failing widget regression
reproduced this before the repair. Room pricing now uses room_rate_required;
report exchange-rate guidance retains rates_required. English and Vietnamese
assertions cover both meanings. Screenshot inspection also found a stale required
timezone error; a failing regression preceded enabling validation on interaction.

Manual preview checks:
1. Run `flutter run -d chrome -t lib/team_preview.dart`. In Your workspace, use
   Owner, Administrator or Manager with all-property scope and choose Create property.
2. Submit empty fields, then enter a name/address, review the suggested timezone
   and select VND or USD. Corrected required-field errors should disappear.
3. Create the property, edit its name, then return to the workspace. Select it,
   open Manage rooms and add a room; the room uses the chosen currency.
4. Switch to assigned-properties-only access or Receptionist. Create property
   must be absent. Repeat in Vietnamese.
5. In room pricing, leave a required price blank and save. The error must request
   a positive price, not an exchange-rate refresh.


Validation: all 180 Flutter regression tests passed sequentially. The final six
property-creation tests also passed after extending the populated workspace-entry
matrix. All 56 Firestore emulator tests and 39 server unit tests passed. Static
analysis of the eight changed Dart files, including both translation maps, is
clean. English/Vietnamese forms and pricing errors cover phone, landscape and
desktop, 100%/130%/200% text and both themes. Representative actual-font screenshots
of the creation form, workspace entry and corrected pricing error were visually
inspected. These are automated and rendered-fixture checks, not live browser or
production-account acceptance tests.

### Overnight operating windows — 2026-09-26

Booking settings now accepts a daily window crossing midnight, such as 22:00–06:00.
A closing time earlier than opening means the next local day. Equal opening and
closing times are rejected; disable the limit for unrestricted stays. Closing at
24:00 remains supported. Early-morning-only stays belong to the previous evening's
window. The entire stay must fit one window: crossing the daytime closure or
joining two nightly windows is rejected, even if both endpoints are open.

The server uses the property's explicit timezone and checks the entire interval,
including repeated/skipped daylight-saving hours. Settings changes check existing
active bookings, retain optimistic concurrency and idempotent retries, and preserve
existing prices. English/Vietnamese guidance explains the next-day convention.
Multiple daily windows remain a separate unfinished task. This is source work;
no deployment or live-account verification was performed.

Manual check: in the local preview, select a property timezone, open Manage rooms
> Booking settings, enable hours and save 22:00–06:00. Reload and verify the times
remain unchanged. Equal times must show an error. Same-day 09:00–17:00 must still
save. The preview does not enforce real booking intervals; those checks use the
Firestore emulator.


Validation: all 173 Flutter regression tests passed sequentially, as did 54
Firestore emulator tests and 39 server unit tests. The settings UI matrix covered
English/Vietnamese, phone/landscape/desktop, 100%/130%/200% text and both themes;
representative actual-font overnight screenshots were visually inspected. The
changed screen and test pass static analysis. Including translation files reports
two pre-existing duplicate `rates_required` keys from the earlier pricing work;
these were subsequently repaired in the property-creation checkpoint above.

### Booking settings and property timezones — 2026-09-26

The user selected a per-property timezone policy. Property details now accepts a
server-validated IANA timezone (for example `Asia/Ho_Chi_Minh`). Existing properties
are not assigned a timezone automatically. The property-creation workflow now suggests Vietnam time, as described above. The timezone field
currently uses a text entry with examples, not a complete searchable zone picker.

Manage rooms now offers **Booking settings** to property managers regardless of
price-override permission. Minimum duration supports 0–168 whole hours; cleaning
gaps support 0–1440 minutes. Zero disables that limit. An optional daily
opening window uses HH:MM in the selected property timezone (closing may be 24:00).
All of a stay must fit inside the window. Overnight support is described above;
weekly multiple windows and date exceptions are now supported as described in the newer checkpoint. Disabling the limit allows multi-day stays.

The server validates current scope, room/property identity, document revision,
timezone and active booking compatibility, and atomically records updates and
activity with server time. Conflicting existing durations, gaps or opening times
block settings changes without rescheduling bookings. Settings transactions
serialize with new booking writes and property timezone edits. Timezone changes
are blocked while any room has operating-hour limits; disable those limits first.
Unknown zones, mismatched timezone snapshots and forged fields are rejected.
Retries reuse the operation while the screen remains mounted; no reload persistence.

A failing emulator regression confirmed operating hours were previously only a
client display limitation. V2 booking creation/editing now checks the entire stay
against the property timezone on the server, including DST folds. Server checks
do not use the browser timezone or clock. Existing legacy calendar display still
uses device-local dates; this change does not migrate that calendar UI or define
invoice due-date, import, backdating or billing-timezone policies.

Manual test: launch `flutter run -d chrome -t lib/team_preview.dart`, select
Manager, open Property details, enter `Asia/Ho_Chi_Minh` as Property timezone and
save. Open Manage rooms → Booking settings for room 101. Set minimum hours `2`,
cleaning minutes `30`, enable the daily limit and enter `09:05`–`17:30`. Save,
reopen and verify the same values. Invalid/reversed hours must not save. Disable
the limit and save before changing the property timezone. Activity history shows
the settings event. Actual booking-conflict/DST enforcement is verified in server
tests; the disposable preview does not simulate booking schedules.

Validation: ten focused settings/property widget tests passed, with long populated
content in English/Vietnamese at phone/landscape/desktop, 100/130/200% text and both
themes. Representative actual-Roboto screenshots were inspected. Targeted static
analysis is clean. All 53 emulator integration tests passed, including the
out-of-hours regression, schedule conflicts, current authorization, retries,
timezone locking and settings/booking concurrency. Pure unit tests include Vietnam
boundaries, midnight closing, invalid zones and New York spring/fall DST cases.
All 172 sequential Flutter regression tests and 37 server unit tests passed.
No production deployment/migration
or live-account verification was performed. Large schedule scans need performance
testing before deployment.

### Room pricing and rental modes — 2026-09-26

Manage rooms now opens **Pricing and rental mode** for accounts with both
manageProperty and overridePrices in the selected property. The server enforces
both permissions on reads, writes and retries. The editor supports monthly,
hourly, daily and overnight default rates, the daily threshold (1–24 whole hours),
and monthly/hourly/both modes. Monthly-capable modes require positive monthly rent;
hourly-capable modes require a positive hourly rate. Optional prices may be blank.
The room currency is fixed; requests carry integer dong or USD cents. Existing
bookings, tenant contracts and payments retain their stored charges.

Updates use server revisions/timestamps and atomic operation/activity records.
Switching to monthly-only is blocked by pending/confirmed/checked-in bookings;
switching to hourly-only is blocked by active or suspended tenants. These checks
use record status, not the device clock. A failing regression exposed that the v2
lease endpoint accepted an active tenant in an hourly-only room; it now rejects
active/suspended leases there. A concurrent mode-switch/lease test ensures both
cannot commit. Legacy organization behavior is unchanged by that v2 guard.

Minimum booking hours, cleaning buffers and operating hours are preserved, not
edited here. Existing invalid currencies/amounts fail closed and need reviewed
repair. Pending retries remain local to the mounted screen; reload discards them.
Changing default prices does not complete the separate trusted booking-price
calculation release gate. No production deployment or migration occurred.

Manual test: run `flutter run -d chrome -t lib/team_preview.dart`, select Manager,
open Manage rooms and choose Pricing and rental mode for room 101. Select Monthly
and short stay, enter monthly rent `1500000`, hourly rate `50000`, optional daily
rate `300000` and threshold `8`, then save. Reopen to verify values. Leave a
required price empty to check validation. Check Activity history for the change.
The preview does not model occupied-mode restrictions; emulator tests verify them.

Validation: six focused pricing tests passed, including exact cents, required
prices, retries, conflicts, denied access, context switching and populated layouts
in English/Vietnamese, phone/landscape/desktop, 100/130/200% text and both themes.
Representative Roboto screenshots were inspected. The clipped selected-mode label
at narrow Vietnamese 200% text was given a full wrapping label with regression
coverage. All 50 emulator integration tests and 35 server unit tests passed;
targeted static analysis is clean. The full sequential Flutter regression suite
passed (167 tests). Live browser/account verification remains pending.

### Room creation — 2026-09-26

Owners, administrators and authorized property managers can now use **Manage
rooms → Add room**, including in an empty property. The form requires a room
number/name, type and positive area. It explains that new rooms use monthly-rental
mode, have no configured price and inherit the property's currency. The server
uses the current property currency (legacy missing currency defaults to VND),
rejects unsupported currencies and rejects client-supplied price, mode or timestamps.

Creation rechecks current organization/property access and rejects existing room
IDs or duplicate normalized names. It atomically creates the room, operation and
activity event using server timestamps. A property inventory timestamp serializes
concurrent creates even in an empty property. This timestamp also invalidates an
older property-details revision; that editor will require a reload before saving.
Uncertain responses retain the same room ID and operation for retry while the
screen stays open. After confirmation the form becomes an editor for that room.
Pending creation is not persisted across browser reloads. Duplicate-name checking
continues to scan the property's rooms; large inventories need performance testing.

Manual test: run `flutter run -d chrome -t lib/team_preview.dart`; select Manager,
open Manage rooms and Add room. Submit blank fields to see validation, then enter
`201`, `Family suite` and `52,75`. Create the room, return to the directory and
verify it appears. Edit it again to confirm it is the same room. Try adding another
room named `201` to check duplicate rejection. Activity history should show Room
created. Housekeepers and receptionists do not have Manage rooms access.

Validation: all ten focused room creation/editing widget tests passed, including
creation from an empty directory, defaults, validation, duplicate recovery,
lost-response retry, access loss, context switching and existing edits. Creation
forms were tested in English/Vietnamese at phone/landscape/desktop sizes,
100/130/200% text and both themes; representative Roboto screenshots were inspected.
All 47 emulator integration tests passed, including simultaneous creates in an
empty property, inherited currency, forged-field rejection, current authorization
on retries and one creation/audit per operation. The full sequential Flutter suite
passed (161 tests), all 35 server unit tests passed and targeted static analysis
was clean. These are automated and rendered-fixture checks; live browser/account
verification remains pending.
No production deployment or migration occurred. Pricing, rental-mode configuration,
room deletion remains unfinished; basic property creation is now available as described above.

### Room directory and basic editing — 2026-09-26

The scoped workspace now offers **Manage rooms** to owners, administrators and
authorized property managers. The paginated directory opens an editor for room
number/name, type and area. It preserves room IDs, prices, rental modes, booking
settings and tenant/booking links. Area accepts a decimal point or comma and must
be above zero and at most 100,000 m². Empty names/types are rejected.

Server reads and updates recheck current membership, organization and property
ownership. Updates use a server document revision, server timestamps and atomic
activity/idempotency records. Renaming checks existing property rooms, including
legacy labels, with trimmed, Unicode-normalized case-insensitive comparison.
Concurrent attempts to claim the same name are covered by an emulator test.
Existing duplicate labels can retain their names while editing other details;
this is not an automatic cleanup of historical duplicates. Renaming scans the
property's rooms transactionally; very large inventories need performance testing.

The UI clears records after denied reads, handles pagination/empty/error states,
ignores late results after switching rooms, preserves conflict drafts for copying
and locks uncertain submissions for same-operation retries. Pending commands last
only while the editor stays open. A corrected area now clears its error immediately;
the stale message was reproduced with a failing test and fixed with live validation.

Manual test: run `flutter run -d chrome -t lib/team_preview.dart`, choose Manager,
then Manage rooms. Edit the first room, try the existing number `102` (rejected),
then use a unique name, change its type and enter `52,75` for area. Save and return
to the directory to see the updated values. Check Activity history for the change.
Switch to Housekeeper or Receptionist: Manage rooms should be absent.
Preview changes are disposable and reset when the browser reloads.

Validation: six focused widget tests passed, covering navigation, input validation,
duplicates, retries, conflicts, access loss, late responses, pagination and empty
states. Populated English/Vietnamese directory/editor checks cover 320px phone,
812px landscape and 1440px desktop, 100/130/200% text and both themes. Representative
Roboto screenshots were inspected. Targeted static analysis is clean. All 45
emulator integration tests passed, including concurrent renames, scoped access,
forged input, unchanged financial/link fields and direct-write denial.
The full sequential Flutter regression suite passed (157 tests), and all 35
server unit tests passed. These are automated and rendered-fixture checks;
live browser/account verification remains pending.
The required rooms index is included in both index manifests but not deployed.
Room creation/deletion and pricing/rental-mode editing remain unfinished; no live
organization was migrated or deployed in this checkpoint.

### Property details editor — 2026-09-26

Authorized owners, administrators and property managers can open **Property
details** from the scoped workspace and edit the selected property's name and
address. Other building fields are preserved. Reads return only these fields and
a server revision. Updates recheck current membership/property scope, reject
stale revisions and commit server timestamps, an activity record and an idempotent
operation together. Direct v2 writes remain denied. Client timestamps are neither
accepted nor used for conflict detection.

The form requires both fields, wraps long content, locks uncertain submissions
for same-operation retries, clears data on access denial and ignores late results
after switching context. Conflicts preserve read-only draft text for copying and
require reload. Pending retries last only while the screen stays open. A reload
discards unsaved form input. This completes name/address editing, not property
creation/deletion, room management, rental settings or currency changes.

Test locally: run `flutter run -d chrome -t lib/team_preview.dart`; select Manager,
open Property details, change name/address and save. Return to Your workspace and
verify the updated property name. Open Activity history to inspect the recorded
change. Switch to Receptionist or Housekeeper and verify the editor is absent.
The preview uses disposable in-memory data; refreshing resets it.

Validation: five focused widget tests cover workspace navigation, validation,
save/refresh, lost-reply retries, stale edits, denial, context switching and populated
English/Vietnamese layouts at 320px phone, 812px landscape and 1440px desktop,
100/130/200% text and both themes. Representative Roboto screenshots were inspected.
The narrow-phone enlarged-address issue was reproduced with a failing scroll-extent
assertion, fixed by expanding the text field and retained as a regression.
All 43 emulator integration tests passed, including property scope, revocation,
field preservation, stale revisions, timestamp forgery and atomic retry/audit checks.
The full sequential Flutter regression suite passed (151 tests); targeted static
analysis was clean, and all 35 server unit tests passed. These are automated and
rendered-fixture checks, not live browser/account verification.
No production deployment or migration was performed in this checkpoint.

### Housekeeping workspace — 2026-09-26

The scoped workspace now opens the housekeeping screen. Owners, administrators
and property managers can explicitly select a room and an eligible account and
assign instructions. Assigned workers can start and complete their own tasks.
The server validates current property access and assignment eligibility, records
server timestamps and activity, and handles exact retries atomically. Room and
assignee pickers use scoped, paginated server projections.

An uncertain response preserves the same operation while the screen stays open;
keep the screen open to retry. Unlike payment commands, task retries are not
persisted across reloads. Reassignment and cancellation are not implemented.
A regression reproduced disabled controls after changing organization during
a pending save; resetting the saving state fixes it, and late responses are ignored.

Manual test: run `flutter run -d chrome -t lib/team_preview.dart`, select Manager,
open Housekeeping, choose Assign a task, select room 101 and the sample worker,
enter instructions and save. Switch to Housekeeper and open Housekeeping: start
the new task and mark it completed. Assignment controls should be absent for
the worker. Switch back to Manager to see its completed status. Refreshing the
browser resets this disposable preview; it does not test production permissions.

Validation: the full sequential Flutter suite passed 145 tests before the final
context-switch fix; all four focused housekeeping tests passed after that fix,
and targeted static analysis was clean.
All 42 emulator integration tests passed, including task authorization, picker
access, retries, suspension, timestamps and direct-write denial. Populated UI
checks cover English/Vietnamese, phone/landscape/desktop, 100/130/200% text and
both themes. Representative Roboto screenshots were visually inspected.
Production deployment and live-account verification remain pending.

### Authorized orphan cleanup — 2026-09-26

After all five recorded creator accounts were confirmed absent from Firebase
Authentication, the user explicitly changed the instruction from restoring access
to deleting the five organizations. A typed Firestore backup was saved before
deletion. The checked transaction deleted 18 documents: 5 organizations, 2 buildings,
2 rooms, 2 tenants, 2 payments and 5 invite codes. Each document's full update time
was checked against the backup; the transaction also checked for newly added
memberships and organization-scoped records. No other organization was targeted.

Deleted organizations: 14 Tân Thái 1, 141 LÝ NHẬT QUANG, 211 QUỐC LỘ 9, FPT,
and SLC 2019. A subsequent read verified all 18 document paths absent. A fresh
inventory shows **24 remaining organizations, 26 memberships, zero v2 organizations,
zero missing-active-owner issues and two generic members requiring assignment**.

Backup: `private-backups/orphan-deletion-backup-2026-09-26.json` (gitignored;
contains private data, preserve securely). SHA-256:
`792CD6FC4F65501D984F58D0EA74CE69EACCCD658624363062BC9E5AB15A318F`.
It contains the exact typed document fields and paths for recovery; restoring it
would require a separately reviewed create-only restore, checking for path reuse.
The original `.dart_tool` copy is also retained. No Authentication accounts were
deleted and no remaining organization's access version changed. The earlier
"no production writes" notes describe their checkpoints; this cleanup did write
to production with explicit user authorization.

Payment workflow validation completed: 142 Flutter regression tests, 42 emulator
integration tests, 35 server unit tests and clean targeted static analysis. Full
operational replacement and v2 deployment/migration remain unfinished.

### Payment workflow and live migration inventory — 2026-09-26

The scoped workspace now offers **Collect / refund payments** to permitted
accounts. Receptionists can collect without financial-report access; refunds
require their separate permission. The action projection omits tenant identity,
bank transaction references and notes. Booking-linked records cannot use the
standalone command. Collection/refund hints are not authorization; the server
rechecks current membership, property scope and balances on every submission.

The form validates whole dong or exact USD cents and requires refund reasons.
It persists an immutable command before sending, keyed by account/organization/
invoice, restores it after reopening, and reports success only after server
confirmation. An uncertain outcome locks inputs for the same-operation retry.
Storage failure prevents sending. This journal is device-local, not a cross-device
or concurrent-tab lock; deliberately submitting distinct intents elsewhere is not
deduplicated as the same business action. Do not clear browser storage while a
payment is uncertain. No bank transfer is executed by these recordkeeping actions.

Manual test: launch `flutter run -d chrome -t lib/team_preview.dart`, select
Receptionist, open Collect / refund payments, open the sample invoice, enter
250000, confirm, and return to see 750000 paid. Switch to Accountant for refund
controls. The preview simulates these actions; server enforcement is tested
separately. Reopening uncertain operations, failed storage, exact retries, refund
validation and denied access are covered in `test/payment_action_form_test.dart`.

Validation: full sequential Flutter suite passed (142 tests), including workspace
payment submission and updated balance, plus 42 Firestore integration tests.
The currency hint truncation was reproduced with a failing RenderParagraph
assertion, fixed with wrapping text, and retained as a regression. English and
Vietnamese forms cover phone/landscape/desktop, 100/130/200% text and both themes;
representative actual-Roboto screenshots were inspected after the fix.

Housekeeping backend groundwork now supports manager assignment to active,
property-authorized accounts and assigned-worker status changes, with atomic audit
and idempotency records. Workers read only their own tasks; property managers
can read property tasks. Emulator coverage verifies assignment, isolated reads,
completion timestamps, retries, suspension and direct-write denial. The task UI
is now connected as described in the housekeeping checkpoint above.

The user selected **all organizations** as the migration scope. After Firebase
reauthentication, a read-only inventory succeeded: 29 organizations, 26 memberships,
zero v2 organizations, two generic members needing explicit assignment and five
organizations without any membership. The private local report is
`.dart_tool/team-inventory-2026-09-26.json`; it is metadata only, not a database
backup or a transactionally consistent snapshot. No tenant/payment data was read.

The user authorized restoring the five organizations to their recorded creators.
Authentication checks found all five creator accounts missing, so **no restoration
was applied**. An existing replacement owner must be designated for each affected
organization (or a single explicitly designated owner for all five):
14 Tân Thái 1, 141 LÝ NHẬT QUANG, 211 QUỐC LỘ 9, FPT, SLC 2019.
The check output is `.dart_tool/creator-recovery-check.json`.

Read-only deployed index discovery succeeded. `firestore.indexes.json` preserves
the live index inventory and adds workspace/activity/task requirements; it is not
yet wired into the deployment config or deployed. Review it again against current
live indexes immediately before deployment. `functions/team_inventory.js` is a
read-only CLI inventory utility; `restore_recorded_creators.js --check` verifies
the authorized recovery prerequisites without writing Firestore.

Still open: replacement-owner decision, actual backup and reviewed migration
manifest, housekeeping UI, property/tenant/booking operational continuity,
production deployment and live acceptance. No production writes occurred.

### Current Team & access integration — 2026-09-26

This section supersedes older checkpoint descriptions of navigation and shared-code
joining below. The complete production cutover is **not done**.

- [x] Account access review lists existing accounts, including accounts with no
  staff profile. Owners/admins explicitly choose supported role, status and
  property assignments using the existing audited access editor. No member role
  is offered, no automatic promotion occurs, and no staff link is inferred.
  Self, owner and administrator-peer protections are computed by the read API
  and independently enforced by the mutation API.
- [x] Version-2 organization entry uses RoleWorkspace before constructing the
  legacy screen. Legacy building/payment loaders do not run for that entry.
- [x] Dashboard organization discovery uses authenticated, paginated
  `listMyOrganizations`; v2 summaries omit banking details and join codes.
  Current suspension and malformed/legacy v2 assignments exclude an organization.
  Legacy organizations load their existing details through legacy rules.
- [x] Join opens request submission/status. Direct shared-code creation of a
  generic member is denied even for a valid code. The historical join service
  now fails closed. Requests currently require a v2 organization; a legacy
  organization must be reviewed/migrated before onboarding through this flow.
- [x] Permitted staff can open their own activity and profile from the workspace;
  owners/admins can open directory, account review and organization activity.
  The backend remains the authority for visibility. Preview fixtures filter
  staff activity/profile reads by the simulated account.
- [x] Standalone collection/refund event labels are available in both languages.
- [x] Synthetic emulator migration rehearsal: a pure proposal leaves originals
  unchanged; applying the reviewed fixture atomically preserves room inventory,
  makes legacy members assignmentRequired, permits explicit subsequent assignment,
  and keeps direct inventory reads denied. This is not a production migration tool
  or a rehearsal against a real organization export.

#### How to test this integration

Run `flutter run -d chrome -t lib/team_preview.dart`.

1. Open **Account access review** from the owner directory. The sample legacy
   account appears even though it has no linked staff profile.
2. Open **Manage account access**. Saving without a role/status is rejected.
   Select Receptionist, Active, explicit property scope, and enter a reason.
   Save, then confirm the new role appears. This does not create a staff profile.
3. Switch the preview role to Receptionist. Open activity history: only the
   sample receptionist payment appears, not the manager's room move. Team
   administration and account review are absent. Open the personal profile;
   the fixture has no linked profile, so it shows the empty state.
4. Reset the preview to restore the unassigned account. Repeat in Vietnamese.

Automated tests:

```powershell
flutter test test/account_access_list_test.dart test/team_organization_entry_test.dart test/role_workspace_test.dart --concurrency=1
```

The normal app's new organization discovery requires deployment of
`listMyOrganizations` before releasing the client. The preview requires no
Firebase deployment. Do not publish the client ahead of its callable dependencies.

Validation: full Flutter regression passed (135 tests), followed by 14 targeted
tests covering final navigation, loading/empty/denied/stale-account states,
own-activity/profile routing, and the organization entry boundary. Final team
screen/test static analysis was clean. Broader legacy-file analysis reported
existing unused-code/style findings; it was not globally clean. The normal app
release JavaScript web build passed; the optional Wasm dry run reported `image`
dependency compatibility warnings. No Wasm build or live browser test was performed.
Server unit tests passed (35), and Firestore integration tests passed (40).
The emulator used `.dart_tool/firebase.team-final.json` on port 8692; previous
ports were occupied. Negative rules tests intentionally report permission errors.
Account-review fixtures cover en/vi, phone/landscape/desktop, 100/130/200% text,
and both themes. Representative actual-Roboto screenshots were visually inspected.
Final directory and populated workspace captures were also inspected, including
Vietnamese phone at 200% text and desktop navigation. Scrollable content remains
reachable; these captures are fixtures, not deployed-account verification.
Live accounts, production indexes and actual browser login remain unverified.

#### Remaining items before the entire checklist can be closed

- [x] Local operational replacement source batch; see the 2026-09-27 checkpoint
  and combined acceptance guide. Live verification remains part of release.
- [ ] Review a real organization export and resolve duplicate/missing owners,
  staff links, assignments and historical records. Prepare an approved migration
  manifest and backup/restore procedure; the synthetic rehearsal is insufficient.
- [ ] Merge supplemental indexes with the deployed inventory and verify them.
- [ ] Deploy callable dependencies and rules, perform live role/scope/revocation
  acceptance tests, then release the client and migrate reviewed organizations.
- [ ] Close the separate release-security gates, including legacy financial
  writes and the property-timezone/effective-date policy.

No production deployment, migration or live-data changes occurred in this turn.

### Standalone payment command checkpoint — 2026-09-26

Added `mutateStandalonePayment` for existing version-2 standalone invoices and
`PaymentCommandService` for immutable collection/refund commands. Amounts use
integer minor units (VND dong, USD cents). The server checks current role,
property scope, organization, invoice balance and currency. Refunds require
`refundPayments` and a reason. Booking invoices use the booking workflow.
Unsupported currencies and malformed historical amounts fail closed for review.

The invoice update, protected operation ledger and staff activity record commit
atomically. The server records time and actor; clients cannot supply timestamps,
actors, resulting balances or statuses. Exact retries return the original result
but still require current authorization. Changed input with the same operation
ID is rejected. Retain the prepared operation after a timeout instead of making
a new one. Refunds preserve paidAt and add lastRefundedAt. Original createdAt is
preserved. Audit snapshots omit tenant details and free-text refund reasons;
the protected operation ledger retains the reason.

This checkpoint does not connect forms, create invoices, migrate organizations,
deploy functions, or close legacy write paths. The release security gates remain
open. There is no new payment UI in the local preview. Next: connect collection
and refund forms with handling for uncertain outcomes, then coordinate legacy
cutover and invoice creation/edit policy.

How to test from the repository root:

```powershell
flutter test test/payment_command_service_test.dart --concurrency=1
```

From `functions`, run the emulator suite (requires Java and available ports):

```powershell
node node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --config ../firebase.emulator.json --project demo-apartment-calendar --only firestore "node --test --test-concurrency=1 test/firestore.integration.js test/team.integration.js"
```

All 37 emulator tests passed, including seven payment scenarios covering server
timestamps/actor, identical retries, forged fields, roles/scopes/revocation,
concurrent overpayment attempts, USD fees, partial/full refunds, unsafe invoice
data, and direct client write denial. A fixed injected backend clock verifies
time ownership; this is not a live browser operating-system clock test. The run
used temporary `.dart_tool/firebase.payments.json` on port 8492 with current
rules copied into `.dart_tool`; the emulator stopped afterward. Existing server
unit tests also passed (35). No UI layout changed or screenshots were generated.
The three Flutter command-service tests passed: identical retry payloads after
connection failure, refund command identity/amounts, and propagation of denied
or unavailable responses without local success. Tests ran with `--concurrency=1`.

### Release security review — 2026-09-26

See [RELEASE_SECURITY_CHECKLIST.md](RELEASE_SECURITY_CHECKLIST.md) for release
gates, source-reviewed device-clock findings and the C01–C14 adversarial test
matrix. Release is not approved. Prioritize server-owned standalone payment
timestamps/mutations and the business timezone/effective-date policy. This review
did not modify production code, deploy changes or run clock-manipulation tests.

### Newest-first activity checkpoint — 2026-09-26

Activity history now orders events by `createdAt` descending, then document ID
descending for equal timestamps. Load more continues from the complete cursor
document so Firestore timestamp precision is preserved. Newer events arriving
between page loads appear after Refresh; they do not shift older pages. Refresh
and actor-filter changes start a new page sequence. Non-activity lists retain
their original ordering and pagination contract.

The cursor ID is resolved in the same authorized transaction as the page. A
missing cursor, cursor from another organization, or cursor incompatible with
the effective actor filter is rejected without returning its fields. Suspended
or revoked callers are rechecked before cursor resolution. Missing/deleted cursor
errors clear the UI and can be recovered with Refresh. Server-created audit
records already include createdAt; manually imported historical documents without
that field are excluded by Firestore's ordering and require a reviewed backfill
before rollout. No timestamps were inferred or backfilled in this checkpoint.

The preview implements the same timestamp/ID ordering and page boundaries. To
test: open Staff activity history; the sample room move (14:00 UTC) precedes the
payment (13:00 UTC), which precedes the access change (12:00 UTC). Save a staff
profile, reopen history, and confirm that its new event is at the top. Actor
filters retain newest-first ordering. Existing sample dates are shown in the
computer's local timezone.

Before implementation, the new emulator ordering and cursor tests and the
preview pagination test failed for the expected old behavior. Afterward all 30
emulator tests and 35 server tests passed. The occupied emulator port 8292 was
left untouched; the successful run used 8392 and stopped its emulator afterward.
`firestore.workspace.indexes.json` now includes organization/time/ID and
organization/actor/time/ID activity indexes. Merge these supplemental indexes
with the live inventory before deployment; emulator success does not verify
production indexes. No deployment, migration or live-account changes occurred.

Final checks: 128 Flutter tests passed sequentially; the four activity tests also
passed after updating the pagination fixture to use distinct IDs. The screen
continues to cover en/vi, phone/landscape/desktop, 100/130/200% text and both
themes. Representative final screenshots with Roboto were visually inspected.
Live-account and deployed-index verification remain pending.

### Operational activity checkpoint

Version-2 calendar booking and tenant lease mutations now create teamActivity
events in the same Firestore transaction as the operational writes. Events cover
booking create/edit/status/payment/deposit/refund/checkout and lease create/edit/
room move/status. Snapshots allowlist room/property references, lifecycle dates,
status, currency and collected/refunded amounts. Guest/tenant identity, contact
fields and free-text notes are excluded. Edits to private fields still generate
an event, without recording their values. Existing legacy behavior is unchanged.

Existing payment/checkout/create retry guards prevent duplicate audit entries;
unchanged lease/edit submissions create no additional event. This is not a new
general operation-token protocol for all edits, and distinct successful edits
remain distinct events. Invalid or denied writes commit no audit entry. Historical
operations are not backfilled. Direct legacy payment CRUD is not covered yet.

The preview seeds a booking payment (`preview-receptionist`) and room move
(`preview-manager`) in Staff activity history. Expand their details or filter by
those actor references. These are illustrative fixtures; operational editing is
still unavailable in the preview workspace. Real backend behavior is verified
separately with emulator transactions, not by those fixtures.

The 28 emulator tests passed, including new create/payment/checkout/lease retry
coverage, rejected overpayment, exact event count, before/after paid amounts,
lease status changes and absence of private fields. The emulator stopped after
the run. No deployment or migration was performed.

Final operational checkpoint validation: 127 Flutter regression tests, 35 server
tests and 28 emulator tests passed. Three activity tests passed again with the
operational screenshot fixture. Payment-event details were rendered across
en/vi, phone/landscape/desktop, 100/130/200% text and both themes; representative
final images were visually inspected. Targeted static analysis reported no issues.
Live accounts, actual device keyboards and direct legacy payment CRUD remain
outside this verification.

### Request submission checkpoint

The local preview now includes **Open requester**. Enter organization reference
`preview`, join code `demo-code`, and a name. Send request, then return to the
owner directory and review that request under Invitations & access requests.
Create a matching unlinked staff profile first, or deliberately select an
existing eligible sample profile. Return to Open requester, enter `preview`, and
choose Check my request status (no code/name needed for a status read).

The request screen uses `requestAccess` and requester-scoped `myRequests`, follows
pagination, clears records on organization changes/read failures, and preserves
an immutable operation for uncertain submission retries. Submission itself
creates no membership. The preview requester has a separate request from the
seeded Anh request. Reset restores all fixtures. The normal app's legacy join
route is unchanged until the coordinated authorization cutover; this screen is
currently reachable through the preview only.

Six targeted request/preview tests passed. They cover submission without account
linkage, approval reflected in status, unchanged retries, denial cleanup and
populated en/vi layouts at phone, landscape and desktop sizes with 100/130/200%
text and both themes. Representative rendered screenshots were inspected using
Roboto. No Firebase backend changes were made in this checkpoint; real-account
request submission, device keyboard behavior and production cutover remain
unverified. The full regression suite was not rerun for this isolated screen.

- [x] Explicit role/permission foundation in Dart and Node.
- [x] Separate staff profile, with optional account linkage.
- [x] Pure migration proposal: legacy members require assignment; no database writes.
- [x] Backend team mutation handler, invitation/access-request flow and atomic audit events.
- [x] Authorized, paginated team read API.
- [x] Flutter team API service and dependency registration.
- [x] Connect read-only staff directory/details to the API service.
- [ ] Integrate authorization across Firestore, callable functions and queries.
- [x] Read-only Team directory and staff details, English/Vietnamese.
- [x] Staff profile creation/editing with safe retries.
- [x] Invitation creation and explicit role/property assignment, suspension and revocation controls.
- [x] Invitation acceptance/revocation UI and access-request review queue.
- [x] Replace legacy join with access-request submission/status UI in source (deployment pending).
- [x] Request submission/status screen, interactive preview and dashboard wiring.
- [ ] Role-specific workspaces and restricted data views.
- [x] First role workspace: scoped read-only property, booking and financial views; preview role switcher.
- [ ] Activity history screens and mutation coverage.
- [x] Administrator activity history and staff own-activity entry; team, booking, lease and standalone payment commands are audited (legacy direct CRUD remains outside coverage).

### Staff activity history checkpoint

In the local preview, open the owner directory and choose Staff activity history.
One sample access-change event is seeded. Save a staff profile or change account
access, then return to history and refresh to see another preview event. Filter
by `preview-owner` to see preview events, or an unknown account reference for the
empty state. Expand Change details for before/after data and recorded reasons.
The preview uses a simulated owner actor; it is not a real authentication test.

The real screen uses `readTeam(activity)` and its existing backend restrictions:
all-property team administrators can inspect/filter organization activity, while
non-administrators can only request their own allowed activity. History navigation
is currently exposed in the administrator directory. Read errors clear all loaded
events, filters reset pagination, and late responses from another organization
are discarded. Dates and primary field labels are localized. Account/property
references remain visible rather than guessing historical names. Results retain
the API's newest-first timestamp order, with document ID as the tie-breaker.

New reviewRequest audit events include pending -> approved/rejected outcomes and
revocations include pending -> revoked. Existing records are not backfilled;
missing change details are marked Not recorded. This is team-access history,
not a complete log of bookings, payments or every profile field. Backend events
remain atomic and idempotent with their mutations. No deployment occurred.

Emulator tests passed (27), including explicit request outcomes and existing
own-activity/admin-filter/revoked-user checks. The occupied emulator port 8192
was left untouched; this run used temporary configuration on 8292 and stopped
its emulator afterward.

Activity checkpoint validation: full Flutter regression passed (126 tests), plus
20 targeted server tests and 27 emulator tests. The two activity tests passed
again after localization polish. Populated expanded history was checked in en/vi,
320px phone, 812x375 landscape, 1440px desktop, 100/130/200% text and both themes.
Representative screenshots with actual Roboto were visually inspected, including
final Vietnamese field labels. Live accounts and device keyboards were not tested.
- [ ] Migration rehearsal, full regression and visual verification.
- [ ] Coordinated production cutover.

## Phase 1: model and policy testing

### Role workspace checkpoint

Run `flutter run -d chrome -t lib/team_preview.dart`, expand Local preview and
select a role from the dropdown. Owner/administrator can open Team & access;
manager sees bookings and financial records; receptionist sees bookings;
accountant sees bookings and financial records; viewer sees financial records;
housekeeper sees properties only, with an explicit tasks-not-yet-available message.
Choose Assign Riverside only to exercise selected property scope. Selecting a
different property clears the previously displayed records. Refresh clears all
old data before checking current membership. A denied read clears the workspace.

`readWorkspace` checks the authenticated membership, organization access version,
active status, role and target property's organization in a transaction. Selected
property lists are fetched only from assigned IDs (at most 100), filtered by
organization and paginated without exposing unassigned IDs. Booking and payment
queries bind both organizationId and buildingId. Booking projections omit phone,
ID number, notes and payment data; financial projections omit guest/tenant name,
phone, transaction identifiers and notes. Housekeepers cannot call either
operational view, and viewer/receptionist restrictions are enforced on the server.
Overrides do not create new read permissions. No direct-client rule was relaxed.

The workspace is available in the local preview, with production entry-point
integration reserved for cutover. Operational editing, housekeeping task CRUD,
financial summaries and activity screens are still pending. No deployment or
migration occurred. The supplemental `firestore.workspace.indexes.json` contains
the scoped operational and chronological activity indexes; merge them with the project's existing live
index inventory before deployment. It is deliberately not a replacement index
configuration and is not wired into firebase.json yet. Emulator coverage does
not establish production index availability.

Backend validation: 35 unit/handler tests and 27 emulator tests passed. The new
emulator scenario covers all seven roles, sensitive-field omission, cross-property
and cross-organization denial, an empty assignment and immediate suspension.
Representative screenshots were visually inspected in both languages, narrow
phone/landscape/desktop, enlarged text and themes. These are fixtures, not real
Firebase login or live browser verification.

Final workspace validation: all 124 Flutter tests passed sequentially. The three
workspace tests were rerun after status localization and locale-aware numeric
formatting, and passed; final representative screenshots were inspected again.
Targeted static analysis reported no issues. The complete seven-role operational
editing rollout is not finished; this checkpoint delivers scoped read-only views.

Run from the repository root, sequentially:

```powershell
flutter test test/team_access_test.dart --concurrency=1
node --test functions/test/team_access.test.js
```

Expected checks: all roles obey selected building scope; suspended/revoked users
have no access; unknown and legacy roles fail closed; receptionists cannot refund
or override prices by default; housekeepers cannot view booking/financial data;
administrators cannot change owners or other administrators; overrides cannot
grant team management or bypass building scope; staff identities survive without
an account. Migration proposals do not modify inputs, promote legacy members, or
overwrite existing v2 assignments.

These are policy unit tests, not proof of backend enforcement. The foundation is
not wired into existing screens, rules or callable functions yet. Existing live
access and member creation remain unchanged until the coordinated integration.
No migration or deployment has been performed.

Validation on 2026-09-25: full Flutter suite passed (78 tests, including 10 new
team-policy/staff tests). Existing calendar server tests plus new team-policy
tests passed (15 total). After tightening malformed-scope handling, the eight
server-policy tests passed again. No UI changed, no screenshots were needed for
this phase, and no live-account or Firestore-emulator verification was performed.

## Integration constraints

- Never activate only client-side restrictions and describe them as security.
- Firestore reads return whole documents: sensitive guest data requires separate
  projections/documents or server-mediated reads for restricted roles.
- Housekeeping role currently defines capabilities, not an implemented task module.
- Every operational server call must bind the membership to authenticated user,
  organization, and target building; role checks alone are insufficient.
- Owner-only operations and administrator peer restrictions need explicit checks
  beyond the manageTeam capability.
- A migration preview must be reviewed before removing legacy access; no silent
  privilege grants or automatic staff-account linking.
- UI checks must cover en/vi, narrow phones, desktop, landscape, 130%/200% text,
  realistic populated fixtures, layout exceptions and actual screenshot review.

## Phase 2: backend team mutations

`mutateTeam` is registered in the Functions entry point but has not been deployed.
It requires `organizations.accessVersion == 2` and an explicit active v2 membership.
Do not manually enable it in production: legacy rules, reads, and operational
callables still need the coordinated authorization migration.

Implemented actions:

- `saveStaff`: create/edit a profile without granting account access. Employment
  inactivity does not automatically suspend a linked account; use `setAccess`.
- `invite`: explicit role/scope, verified-email recipient binding on acceptance,
  seven-day expiry, existing unlinked active staff profile.
- `acceptInvitation`: link account/profile and activate approved access atomically.
  Existing memberships are never overwritten by an invitation. Inviter access and
  building existence are checked again at acceptance.
- `revokeInvitation`: close a pending invitation.
- `requestAccess`: valid join code creates a pending request, not a membership.
- `reviewRequest`: approve with an explicit role/scope and staff profile, or reject.
- `setAccess`: change another user's role/scope or suspend/revoke access, with a
  required reason. Self, owner and administrator-peer protections apply.

Each action requires an `operationId` retained by the caller across retries.
Exact retries return the previous result without duplicate records/events;
reuse with changed input is rejected. Privileged retries recheck actor access.
Role defaults as well as overrides cannot exceed the granting administrator's
permissions. Team administration currently requires all-building scope.

New `staffProfiles`, `teamInvitations`, `teamRequests`, `teamOperations` and
`teamActivity` collections remain inaccessible to direct clients under the
current rules. The future read API will return authorized views.

### How to test

From the project root:

```powershell
node --test functions/test/calendar.test.js functions/test/team_access.test.js functions/test/team.test.js
```

For real Firestore transactions and rules, from `functions`:

```powershell
node node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --config ../firebase.emulator.json --project demo-apartment-calendar --only firestore "node --test --test-concurrency=1 test/firestore.integration.js test/team.integration.js"
```

The integration tests require the emulator and refuse to run without it. The
demo project avoids production access. Fixtures are synthetic.

Expected scenarios include invitation recipient verification, expiry/revocation,
duplicate/concurrent acceptance, no access before request approval, rejection,
cross-organization references, forbidden privilege grants, protected roles,
access suspension, atomic audit records, and denied direct client writes/reads.

No new screens exist in this phase. Legacy shared-code member creation in the
existing app is not yet replaced; only the new handler uses approval requests.

Validation on 2026-09-25: 33 server unit/handler tests passed, including the
existing calendar tests. All 13 Firestore integration tests passed (10 existing,
3 new), with real transaction retries and direct-client denials. The emulator
was stopped afterward. Expected PERMISSION_DENIED output comes from negative
security tests. No Flutter files changed in phase 2, so the prior 78-test Flutter
result was not rerun; no UI or live-account verification was performed.

## Phase 3: authorized reads and migration boundaries

`readTeam` accepts `{organizationId, view, limit?, cursor?, actorId?}`. Page size
defaults to 25 and is capped at 100. `actorId` is only accepted for activity.

- `myAccess`: only the authenticated user's access record, including revoked or
  suspended state; null if there is no matching membership.
- `myRequests`: only that user's requests in the selected organization.
- `staff`: owner/administrator with all-building scope can list profiles; other
  active roles with own-activity permission can read only their linked profile.
- `activity`: owner/admin can list or filter by actor; other permitted roles see
  only events they performed.
- `access`, `invitations`, `requests`: owner/admin with all-building scope only.

List responses contain `{records, nextCursor}`; `myAccess` contains `{record}`.
Dates serialize as UTC ISO strings. Fields are explicitly selected; unlisted
document fields do not leak into responses. Activity uses descending createdAt
and document ID, resolving an authorized cursor document inside the transaction.
Other views retain document-ID ordering. Date-range filters remain pending.
Reads execute in transactions alongside membership authorization.

For organizations explicitly migrated to accessVersion 2:

- Direct legacy operational reads/writes are denied, including full guest and
  financial documents. New operational projections/client integration are still
  required; this is a safe boundary, not completed operational page support.
- Legacy generic-member creation and client policy-version changes are denied.
- Booking operations check the target building and action permission; suspended
  creators do not bypass checks. Permanent booking deletion is disabled pending
  a dedicated deletion policy. Receptionists cannot create arbitrary-priced
  bookings until authoritative server rate calculation is implemented.
- Lease operations require access to both source and destination buildings.
- Legacy organization-wide AI reads/imports are denied pending scoped tooling.
- The legacy member-list callable rejects v2 organizations; clients must use
  readTeam. Both legacy membership callables now use the current request envelope.

Unmigrated organizations retain existing workflows, covered by legacy integration
tests. Do not enable v2 in production yet: new pages, operational read projections,
rate calculation, complete audit coverage and migration remain unfinished.

### How to test this phase

From the repository root, run sequentially:

```powershell
node --test functions/test/calendar.test.js functions/test/team_access.test.js functions/test/team.test.js functions/test/team_read.test.js
flutter test --concurrency=1
```

From `functions`, run the same emulator command listed in phase 2. It now also
checks pagination, output-field filtering, cross-organization isolation, own-only
activity, revoked access state, legacy join denial in v2, migration tampering,
booking price permissions, source/destination lease scope, and AI denial.

Backend verification: 35 unit/handler tests and 20 Firestore integration tests
passed. Negative-rule tests intentionally print PERMISSION_DENIED. No functions,
rules or database migrations have been deployed. No UI changed in this phase.

## Phase 3 client service

`TeamService` is registered with the app's service locator. It reads authorized
pages and own-access status through callable functions, without direct Firestore
reads or a permission cache. Callers prepare one immutable `TeamOperation` and
retain it for retries after uncertain failures, avoiding duplicate mutations.
Changing the input requires a new operation. Authorization errors propagate to
the screen rather than returning stale records.

Run `flutter test test/team_service_test.dart test/team_access_test.dart --concurrency=1`.
The 15 passing checks cover policy, organization/pagination parameters, revoked
and absent access, unchanged retry payloads, reserved fields and denied reads.
The full Flutter suite before this service addition passed 78 tests. Screen
integration and live-account verification remain pending; there is no new Team
screen to test manually yet. Do not enable accessVersion 2 in production.

## Phase 4: read-only staff directory and details

The organization's Members tab becomes Team & access for accessVersion 2 and
uses `TeamScreen`. Legacy organizations keep their existing tab until cutover.
The organization model reads and preserves the server-owned version marker but
never includes it in client writes. The v2 tab avoids the legacy member-list call.
Other organization tabs still require their planned authorization integration.

Owners/admins with all-building access see authorized staff pages. Other active
roles with own-activity permission see their linked profile. The server enforces
record visibility. Details show name, staff code, email, phone, employment status,
and login linkage. Linked login explicitly does not mean active account access.
There are no new role-granting or generic-member creation controls here.

Refresh clears previous records and details. Failed or denied reads clear data;
stale responses after changing organization are ignored. Load-more requests
recheck access. Loading, no profiles, no linked profile, denied access and request
failure have explicit messages. All labels are in English and Vietnamese.

### How to test

```powershell
flutter test test/team_screen_test.dart --concurrency=1
```

This verifies pagination, details, access-denied cleanup, stale organization
responses, empty/error/suspended states and the server-owned version marker.
Populated UI fixtures cover English/Vietnamese, 320px phones, 812x375 landscape,
1440px desktop, 100%/130%/200% text, and light/dark themes. Tests scroll to and
activate detail/back controls and assert no Flutter layout exceptions.

To render local screenshots using the app's actual Roboto font:

```powershell
flutter test test/team_screen_test.dart --concurrency=1 --dart-define=TEAM_GOLDENS=true --update-goldens
```

Screenshots are written to `.dart_tool/team-*.png`. Representative populated
directory/details screenshots were visually reviewed on phone, desktop and
landscape, including 200% text and dark mode. These are widget fixtures; live
Firebase accounts and the full organization shell were not visually verified.
No deployment/migration has occurred. Do not activate v2 just to preview this
screen: operational pages and the remaining access-management UI are unfinished.

Validation on 2026-09-25: all 88 Flutter regression tests passed sequentially.
The targeted Team test file passed, including 36 populated layout combinations
and their detail views (72 rendered captures). Seven representative captures were
visually inspected; this does not claim visual inspection of every capture.

## Phase 5: staff profile creation and editing

Owners/administrators with all-building team access can add staff profiles and
edit permitted profiles from their details. The server now computes
`canEditProfile` on staff reads, checking linked account roles in the read
transaction. Protected owner profiles and administrator peers do not show Edit;
the mutation handler independently rechecks permission, including suspension
after the directory was loaded. Non-admin staff have no create/edit controls.

The English/Vietnamese form edits full name, unique staff code, optional email
and phone, and employment status. It preserves existing color, never sends
account-linkage or role fields, and never creates generic members. Marking
employment inactive does not suspend the linked account. A successful save
reloads the authorized directory; cancel does not write.

Required fields/email validation and duplicate-code errors preserve the draft.
While a save is pending, duplicate submission is disabled. An uncertain transport
failure locks the draft and retains the exact operation ID/payload for Retry same
save. Explicit server rejection unlocks editing; a changed draft gets a new
operation. The retry state lasts while the form stays mounted, not across browser
reloads or app restarts. An authorization denial clears private records/draft.
Changing organization disposes the editor and ignores late save responses.

### How to test

```powershell
flutter test test/staff_editor_test.dart test/team_screen_test.dart --concurrency=1
```

The editor tests cover creation, required/email validation, cancellation, editing
and color preservation, no account/role writes, duplicate codes, locked uncertain
saves and identical retries, blocked double submission, revoked-access cleanup,
protected-profile controls, and switching organization during a save.

The populated form is checked in English/Vietnamese at 320x740, 812x375 and
1440x1000, at 100%/130%/200% text, in both themes, with simulated keyboard insets.
Tests assert reachable save/cancel controls, stable field size while typing, and
no Flutter exceptions. Enlarged validation/network-error states are also covered.

```powershell
flutter test test/staff_editor_test.dart --concurrency=1 --dart-define=STAFF_GOLDENS=true --update-goldens
```

This renders `.dart_tool/staff-*.png` using the app's Roboto font. Five
representative captures were visually inspected: phone/desktop/landscape forms,
dark mode, and English/Vietnamese uncertainty messages at 200% text. Live accounts,
real device keyboards and the complete organization shell remain unverified.

Backend checks passed: 35 server unit/handler tests and 22 emulator integration
tests (same emulator command as phase 2). New emulator cases cover protected
edit hints, suspension between read/save, preservation of account linkage and
access status, duplicate code rejection, and one audit event on an identical retry.
No migration or deployment has occurred; invitations and role/property assignment
controls are the next checkpoint. Do not enable v2 in production yet.

Validation on 2026-09-25: all 96 Flutter regression tests passed sequentially,
including eight staff-editor tests. Targeted static analysis reported no issues.

## Phase 6: invitation grants and account access editor

Staff details now offer Invite to account access for an active, unlinked profile,
or Manage account access for a linked account the actor can manage. Server-computed
`canManageAccess` excludes self, protected owners and administrator peers. Linked
account policy is returned only to authorized team administrators and only when
its organization/account identity matches the profile.

`readTeam` adds an administrator-only `buildings` view containing names and IDs
(plus organization ID). The editor loads all pages before allowing a save; no
legacy direct reads or full property documents are used for the picker.

Both forms require an explicit supported role (never owner/member), all-property
or selected-property scope, and allow only the four approved permission overrides.
Each override shows its role default. Empty selected scope remains empty; all scope
includes future properties and sends no selected IDs. Existing unavailable IDs
are shown and cannot silently disappear from a selected-scope save. The picker
caps selected assignments at 100, matching the server contract.

Existing accounts can be activated, suspended or revoked with a required audit
reason. Unassigned/legacy roles are not automatically promoted: a supported role
and status must be chosen. The editor checks grant limits for feedback; the server
rechecks authority, actor status and property ownership on each mutation.

Invitation creation requires a recipient email and returns a selectable reference.
The UI explicitly states that no email was sent and recipient acceptance is still
required. Verified-email matching and seven-day expiry remain enforced by the
backend. This phase does not add recipient acceptance, delivery, or invitation-list
revocation UI; those and the access-request queue remain pending.

Uncertain saves retain the immutable operation for retry while the form is open.
Explicit server rejections unlock the draft; access denial clears the editor.
This state is not persisted across browser reloads or app restarts.

### How to test

```powershell
flutter test test/access_editor_test.dart --concurrency=1
```

Scenarios include role validation, empty selected scope, all-property grants,
override payloads, required suspension reasons, grant limits, administrator role
choices, identical uncertain retries, access-denied cleanup, property-read failure
and pagination, explicit legacy assignment, and unavailable property handling.

The populated invitation and linked-account forms cover both languages, 320px
phones, 812x375 landscape and 1440px desktop, both themes, and 100%/130%/200% text.
Controls are exercised and Flutter exceptions are checked. Screenshot review
found clipped Vietnamese permission text at 200%; a regression was first observed
failing (91px of text in a 48px box), then passed after using variable-height
dropdowns. This regression remains in the suite.

```powershell
flutter test test/access_editor_test.dart --concurrency=1 --dart-define=ACCESS_GOLDENS=true --update-goldens
```

This writes `.dart_tool/access-*.png` with the actual Roboto font. The screenshots
cover populated property selections and save controls. Representative captures
were visually inspected; live Firebase accounts, the full organization shell and
real email delivery remain unverified. No production deployment or migration has
occurred. Do not enable v2 in production yet.

Phase 6 validation on 2026-09-25: all 106 Flutter tests passed sequentially,
including 10 access-editor tests. The populated UI matrix covers 72 form/locale/
size/scale/theme combinations. All 35 server unit/handler tests and 24 Firestore
integration tests passed. Targeted static analysis was clean. The emulator was
stopped after the tests. Representative screenshots were inspected rather than
treating the generated images as automatic visual approval.

## Phase 7: invitation acceptance and review queue

The Team directory has an Invitations & access requests entry for authorized
owners/administrators. Invitation pages show recipient, role, status, localized
expiry and a selectable reference. Pending invitations show Revoke only when the
server says the actor may manage the target role. Requests offer Review or Reject.
Review loads eligible active, unlinked staff profiles across all pages. The
administrator must select a profile and explicitly assign role/property access;
approval calls `reviewRequest`, not `invite`. The requester identity and selected
staff name/code stay visible on the approval form. No automatic name/email match
links accounts. Empty eligible lists tell the administrator to add a profile first.

The dashboard has an Accept invitation entry, reachable without organization
membership. The recipient enters a reference, previews the organization, role,
properties, permission settings and expiry, and explicitly accepts. Editing the
reference clears the previous preview. The new `lookupTeamInvitation` callable
requires the exact recipient's verified email; unknown/wrong-recipient references
return the same unavailable error. Its explicit projection omits directory,
inviter and other private organization data. Preview never creates membership.
The mutation still rechecks expiry, revocation, current inviter authority, staff
availability and existing membership before atomically accepting.

Both queues paginate. Failed/denied reads clear displayed records. Revoke,
reject and accept use stable operations for uncertain retries; explicit rejection
unlocks the flow. Mutations require server confirmation before success is shown.
No email delivery was added. The reference is shared manually outside the app.
The legacy join-code submission screen is still pending replacement at cutover;
this checkpoint reviews requests created through the existing new backend API.

### How to test

```powershell
flutter test test/team_review_test.dart --concurrency=1
```

This checks explicit eligible-profile selection and approval payloads, rejection
versus invitation revocation, identical retries, denied-record cleanup, recipient
preview without a grant, reference changes, expired/unavailable invitations,
localized dates, queue loading/empty/error states and pagination, and the
no-eligible-staff path. Representative fixtures have long Vietnamese names,
emails and property names. The four screens cover English/Vietnamese, 320px phones,
812x375 landscape, 1440px desktop, 100%/130%/200% text and both themes. Tests open the
recipient route through the same entry button used by the dashboard and verify
reachable controls and no Flutter exceptions.

```powershell
flutter test test/team_review_test.dart --concurrency=1 --dart-define=REVIEW_GOLDENS=true --update-goldens
```

This generates `.dart_tool/review-*.png` using Roboto and Material icons.
Representative populated screenshots were visually reviewed; screenshots are
fixtures, not live Firebase account verification. The entire dashboard/organization
shell and actual device keyboards remain outside this visual check.

Server unit/handler tests passed (35). Firestore integration tests passed (26),
including verified recipient isolation, expired/revoked preview and acceptance,
no membership before approval, staff-account linkage on approval, one audit event
per repeated operation, and rejection without membership creation. The normal
8092 emulator port was unavailable; the run used temporary configuration in
`.dart_tool/firebase.team-review.json` on port 8192 with an exact rules copy and
the same demo project. The emulator was stopped afterward. No production database
changes, deployment, email sending or migration occurred.

Final checkpoint validation: the full Flutter suite passed (115 tests), run
sequentially with `--concurrency=1`. Targeted analysis of the team screens,
service and review tests reported no issues. The directory layout test now uses
a stable record-specific details key so it can scroll to lazily built cards
after the additional queue navigation increases the header height. Representative
final screenshots confirmed localized dates and reachable approval controls at
200% text; live-account verification remains pending.
