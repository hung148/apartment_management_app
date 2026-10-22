# Hourly prices and templates — 2026-10-16

## Behavior

Short-stay hourly pricing accepts an ordered price for each successive hour. The
user confirmed additive charges and repeating the final price: 300,000 / 200,000 /
100,000 yields totals 300,000 / 500,000 / 600,000 / 700,000 for 1 / 2 / 3 / 4 hours.
Partial hours retain time-based proration, using the rate for that hour; round the
final amount once in the booking currency. Nightly pricing remains separate.

The booking form supports custom hourly rows, add/remove last hour, a template
name and Save template. Selecting a saved template applies its prices immediately.
The delete control removes a template. Bookings store their own hourly-price
snapshot; deleting a template does not change a saved booking. Templates belong
to the property, with up to 20 templates and 168 hourly rows each, in its currency.

## Situation checklist

- Owner/admin/manager and custom roles: server checks readBookings, createBookings
  or manageBookings, overridePrices for arbitrary rows, saveRoomPrices for template
  creation/deletion. Staff may select an existing same-currency template without
  overridePrices. A saved booking's unchanged snapshot remains valid after deletion.
- Revoked/suspended memberships, wrong property and other organizations: existing
  server checks apply before template reads/writes and booking changes.
- Empty templates: explicit empty message and custom-hour action for price editors.
  Loading retains the existing booking loading state. Invalid/blank hourly rows
  stop quotes/save. Template request failure retains inputs and exposes retry via
  the existing failure message; controls disable during the request.
- Duplicate presses: disabled during request; identical retries reuse template ID.
  Server deduplicates identical IDs and rejects conflicting payloads. Transactions
  merge simultaneous additions and make repeated deletion harmless.
- Interrupted booking save and simultaneous edits: existing operation journal,
  request fingerprint, booking/room/property revisions and calendar transaction.
- Legacy v1: new workspace remains v2-only. Existing flat hourly/nightly records
  do not require the new optional hourPrices field. Old requests omitting both
  hourly price inputs retain the saved hourly snapshot.
- Currency: use existing MoneyForm conversion; templates are selectable only in
  booking currency. Creation is offered only when property, booking and input
  currencies agree. USD uses minor units; no implicit relabeling of VND templates.
- Date changes, extra hours, partial hours, switching flat/custom/nightly, room
  changes, surcharges, agreed totals, deposit and payments: use the existing quote
  and save path; hourly snapshot is part of the quote fingerprint. Room changes
  clear custom rows. Changes to templates never rewrite old bookings.
- Fields/buttons: hourly rows, add/remove, flat price, name, save/select/delete,
  estimate, calculated total and saved booking snapshot. Preview server and option
  cache updated alongside production server.
- Layout: EN/VI, 320px phone, 812x375 landscape, 1440px desktop, 100/130/200% text,
  long template names, populated three-hour schedule and repeat-hour total.
  Calendar layout is not changed.

## Verification

- Final server unit suite: 478 passed, including hourly totals, partial hours, USD,
  invalid input, authorization, idempotent template creation/deletion, saved
  snapshots after deletion and legacy requests retaining the snapshot.
- New widget flow: create/select/delete template and save four-hour 700,000 booking
  with original hourly snapshot passed.
- EN/VI responsive matrix passed (36 combinations). Actual-font screenshots of
  desktop EN and 320px/200% VI hourly fields and totals visually inspected.
- Full sequential Flutter run: 1,052 passed; the new hourly test file initially
  failed to compile because its assertion used TextFormField.readOnly. Corrected
  it to inspect the child TextField. Final hourly/booking/payment rerun: 43 passed,
  including all five new hourly tests. Full suite was not repeated afterward.
- Focused analyzer: no errors, two existing warnings and style notices.
- Final picker visual review: found clipping in the original InputChip at 320px /
  200%; replaced with wrapping ListTile rows and retained a long-title/delete-size
  assertion. Inspected light narrow-phone and dark desktop actual-font renders.
- Exact template retry originally compared JSON map ordering; reproduced the
  Firestore field-order mismatch with a failing unit test, fixed field-wise
  comparison, and retained the regression test.
- Real Firestore emulator: passed concurrent template additions, exact retry
  deduplication, concurrent identical booking saves, snapshot survival after
  deletion, and extension from four hours (700,000) to 5.5 hours (850,000).
  Initial extension fixture correctly hit stale room revision; final test obtains
  a fresh quote/revision, as the app does. Emulator shut down cleanly.
- Physical-device accessibility and browser screen
  readers: not yet verified. No production deployment.

Evidence: .dart_tool/hourly-server-final.txt, hourly-widget.txt, hourly-full.txt,
.dart_tool/hourly/*.png. The full regression includes existing workspace changes;
this repository already had substantial uncommitted work before this feature.
Final focused43 and emulator pass outputs are recorded in this chat.

A redundant post-format analyzer rerun stalled without diagnostics and was stopped; the earlier focused analyzer completed with no errors, and final widget compilation/tests passed.

Staging release in progress: backend release 2026-10-16t20-39-16-806z succeeded; all four functions ACTIVE, unauthenticated access denied, indexes READY. Release gate43 Flutter/478 server passed. Web build resumed after interruption; hosting/live check pending.

Final staging result: backend and hosting deployed successfully on 2026-10-16. Release build completed (Wasm); hosting uploaded318 files. Live owner session created QA hourly 2026-10-16, switched to flat pricing and selected the persisted template to restore300000/200000/100000 rates. Two-hour estimate and server quote500000; four-hour estimate and server quote700000. Template persisted through form reconstruction. Visually inspected390px Vietnamese phone layout. Screenshot: .dart_tool/hourly-staging-live.png.
Live scope: used an unsaved edit of synthetic QA payment status2026-10-14; closed without saving, leaving the existing booking unchanged. QA template retained. Delete, concurrent retries, permissions and saved-snapshot survival were verified by local tests/emulator, not live. The initial workspace access error cleared on Refresh. Changing desktop to phone viewport reconstructed the dialog and reset the unsaved draft; this remains a responsive-dialog limitation. Production untouched.

