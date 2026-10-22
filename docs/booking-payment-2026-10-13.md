# Booking forms and Payment — 2026-10-13

## Scope

- Short stay: only the main guest's name is required among guest details.
  Phone, ID, guest count and co-guest details may be completed later. Supplied
  values still have length/type checks. Stay dates and valid prices remain required.
- Nightly price fields appear automatically, initialized from the room price.
  Individual edits survive adding nights; newly added nights use the baseline
  room/selected price. Saved-price chips can explicitly apply a price to all nights.
  Existing price permissions still control typing and saved-price selection.
- Short-stay Payment follows Staff and source, contains agreed-price controls
  and automatically requests the existing server calculation after a short debounce.
  No Review calculation or intermediate Edit step. Save requires a current quote.
- Long-stay Payment follows Staff in charge. The existing recurring agreed rent
  per billing period is directly editable without the amount toggle. The default
  follows monthly rent × months until manually edited. A differing amount still
  requires price authority and a reason. This does not introduce a new schedule
  of independently stored monthly rents; individual invoices retain their existing
  adjustment flow.
- Long-stay estimates distinguish recurring fees, one-time charges and the
  separately held deposit. Metered utility charges and partial periods remain
  calculated on invoices.
- Payment labels and amounts stack on narrow/enlarged layouts. Long-stay price
  and reason labels sit above the inputs, with spacing after the calculated hint.
- Deferred explicitly by Tom: night-start time / 7 PM setting and charges before
  that time. No date-counting, check-in or hourly billing rule changed.

## Situations and verification checklist

| Situation | Evidence/status |
|---|---|
| Owner, administrator, manager, receptionist, staff; price/collection/ID rights | Existing server and Flutter permission tests; unchanged server authorization. New fields retain read-only controls and protected price payloads. |
| Suspended/revoked members and other organizations | Server regression suite covers boundaries; UI cannot grant permission. |
| Only main name, optional phone/ID/co-guest name, fill details later | New server regression, including later edit, exact retry and retained limits; new widget save tests. |
| Blank main name, invalid field sizes and types | Existing validation retained; added server negative cases. |
| Hourly/nightly selection, adding/removing nights, saved prices, old stored prices | Updated booking form regressions; new edited-night preservation test. |
| Source currency / selected currency, rounding, staff without override | Existing currency tests retained; unchanged prices omitted where the server must preserve/convert them. |
| Automatic total, price overrides/reasons, deposit and per-person fees | Existing assertions updated to await automatic calculation; server still rechecks on save. |
| Empty/incomplete fields | No valid quote/Save until price inputs are complete. Payment asks for dates/prices. |
| Calculation loading/failure/retry | New failed-quote test checks disabled Save, retained input and successful retry. |
| Fast edits and out-of-order responses | New held-response test checks old response cannot overwrite newer total or saved prices. |
| Interrupted saves, double taps, exact retries and concurrent writes | Existing immutable pending-command journal unchanged; server exact-retry and concurrency regressions retained. |
| Save-time conflict and revision changes | Save errors remain separate from calculation feedback; refreshed quote does not erase the save error. |
| Legacy records without optional details or old pricing types | Existing read/edit conversion paths retained; broad regression suite required before release. |
| Long-stay baseline changes versus manual agreed amount | New test verifies default updates and explicit amount preservation. |
| Long-stay regular/once/per-person/monthly charges and separate deposit | Summary uses existing surcharge details; invoice calculations remain authoritative. |
| Every affected button/field | Add/remove guests and charges, pricing selection, nights/dates, saved-price menus, agreed price/reason, deposit, source/staff, cancel, retry, save and editing covered by targeted workflow tests. |
| EN/VI, 320px phone, 812×375 landscape, 1440px desktop; 100/130/200% | New 36-case actual-font form matrix checks exceptions and reachable save actions. |
| Visual clarity beyond overflow detection | Rendered desktop and enlarged-phone screenshots inspected; found/reproduced narrow total wrapping, fixed with stacked labels/amounts. User-reported hint/label crowding fixed and spacing assertion retained. |
| Themes | Existing operational-form matrix exercises light/dark. New screenshots use the app's light theme. |
| Embedded/calendar entry and standalone | New tests enter short-stay form from calendar parameters; existing tests enter through standalone list. |

## Validation

- Behavioral regression initially failed because the nightly toggle still existed.
- Optional co-guest server regression initially failed with booking_invalid_request.
- Narrow payment regression reproduced a RenderFlex overflow before the responsive fix.
- New interaction and visual matrix passed before final spacing refinement; focused
  spacing assertion then passed. Full Flutter run: 1,000 passed, one outdated
  test selector matched errors from both rent fields. Scoped it to monthly rent;
  all six tenant-lease tests then passed. No production change for that failure.
- Full server suite: 450 passed (`.dart_tool/payment-server-full.txt`).
- Actual-font images: `.dart_tool/booking-payment/` (EN/VI desktop and 200% phone).
- Firestore emulator: 13 booking-related integration tests passed, including
  blank optional guest details, duplicate saves and conflict/concurrency checks.
- Production-file analyzer: no errors/warnings; four brace-style informational notes.
- Backend staging release `2026-10-14t02-19-18-776z` finished; verification reports
  all four functions active, unauthenticated probes denied, indexes READY.
- Wasm build succeeded (194.5 seconds), with automatic JavaScript fallback.
  Staging Hosting deployment completed (`.dart_tool/payment-hosting-deploy.txt`).
- Final live UI verification blocked: in-app browser connection timed out twice
  while attaching to the existing staging tab. No live form writes performed.
  Local rendered inspection and test evidence above are separate from live verification.

Do not treat unverified live browsers or every possible input as covered by the
automated matrices. Production is outside this release.
