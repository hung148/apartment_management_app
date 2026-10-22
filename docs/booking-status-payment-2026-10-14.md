# Short-stay status and payment continuation

Scope: short stays only. Deposit date/amount/note and Deposit paid checkbox lead
Payment; a dated partial payment with note follows; the always-visible agreed
total comes immediately before the total card. Staff select Not checked in,
Staying or Checked out; time passing does not change short-stay status. Checkout
does not collect money. Checked-out bookings can be edited and reopened, subject
to fresh occupancy checks. Recorded financial entries remain locked and use the
existing refund actions.

## Review situations

- Authority: owner and scoped/custom staff; create/manage, read, price override,
  collection and refund grants independently enforced; suspended/revoked accounts,
  foreign organizations, changed permissions on retries. Server rechecks authority
  in the final transaction. Legacy v1 workspace access stays denied; old v2
  records without the new optional fields remain readable. Long stays unchanged.
- Status: each choice at creation and on edit; past/future dates; clock passing;
  checkout with outstanding balance; reopen into available or occupied room;
  concurrent room claims, room revisions, cancelled/no-show records retaining
  existing restrictions. Only one stay status is selected at a time.
- Deposit: blank, requested but unpaid, paid, zero/negative/invalid amount,
  missing/invalid/future date, full/partial amount, collection denied, recorded
  deposit reopened without collecting twice, refund history and old deposits.
- Payment: blank, partial, full, overpayment, deposit plus payment together,
  date/note validation, prior payments visible, edit starts a fresh payment row,
  currency/source precision and selected-currency changes, totals before/after save.
- Agreed total: empty, equal to calculated, different with required reason,
  clear an override, retain existing override without price permission, surcharges
  included, calculation loading/failure/retry and outdated responses.
- Reliability: double taps, lost response/exact retry, changed retry payload,
  simultaneous saves, stale booking/property/room revisions, access lost mid-flow.
- Layout: populated long guest/deposit/payment notes; EN/VI; 320 phone, 812
  landscape, 1440 desktop; 100/130/200% text; fields and save reachable by scrolling;
  deposit checkbox and methods visible, labels readable, no layout exceptions.
  Shared calendar presentation remains unchanged; existing full-suite calendar
  tests cover embedded/standalone layouts and populated occupancy combinations.

## Verification

- Server full suite: 456 passed before the added exact-retry test; focused status/
  payment suite: 6 passed including duplicate charges and suspended replay denial.
- Retained widget regression reproduced a 320px/200% deposit note/checkbox overflow.
  Fixed by using the existing responsive field row and allowing checkbox text wrap.
- Existing quote assertions now identify the total card explicitly because the
  new agreed-total placeholder legitimately repeats the calculated amount.
- Actual-font populated EN/VI desktop and 320/200 screenshots inspected: deposit
  note and checkbox readable; desktop section order correct. Review exposed the
  pending-payment omission from the remaining-balance preview. A retained assertion
  failed before the fix: total 1,500,000 minus 200,000 deposit and 300,000 payment
  must show 1,000,000 remaining. The card now lists and subtracts that payment too.
- Real Firestore emulator: 14 booking-related tests passed, including concurrent
  identical saves with both deposit and payment (exactly two ledger entries),
  checkout/reopen without changing paid amount, existing currency/scope/race cases.
- Calendar/status unit tests: 24 passed, including before/during/after the stay
  dates for all three staff-selected statuses and exact-retry/suspended access.
- Full sequential Flutter suite: 1,008 passed before the final balance-card fix.
  After that fix, 44 targeted booking/payment/workflow tests passed, including
  the populated responsive matrix and retained remaining-balance assertion.
- Updated EN desktop and VI 320/200 total-card screenshots visually reviewed:
  deposit and payment both deducted, remaining amount correct, Cancel and Save
  reachable and fully readable. Screenshots: `.dart_tool/booking-payment/`.
- Targeted analyzer: no errors; four unnecessary-null-operator warnings and five
  style infos remain in the reviewed files. `git diff --check` passed.
- Staging deployed October 14 (Los Angeles): release
  `2026-10-15t00-58-07-841z`, fresh backend source SHA256
  `a5a73dad9960beb99b07bbdb7fd152e485015476ad2b7f2ba245b9298049aecc`.
  Release gate: analysis without errors, 44 widget tests, 458 server tests passed.
  All four functions ACTIVE; unauthenticated boundary denied; indexes READY.
  Wasm with JavaScript fallback built and Hosting deployment completed successfully.
  Existing indexes/rules skipped by unchanged fingerprints. Production unchanged.
- Live synthetic staging acceptance: 13 access-control cases passed; temporary
  fixtures and App Check debug token cleaned up (exit 0). This is not genuine
  browser attestation or feature-flow verification.
- Live browser: attached after initial tool timeouts, reloaded deployed site,
  enabled accessibility, reached account access failure. Refresh repeated the
  failure; console says Firestore backend unreachable after 10 seconds. No live
  booking writes performed; deposit/payment/status end-to-end check remains open.
  Evidence: `.dart_tool/booking-staging-access-blocked.png`, release log
  `.dart_tool/booking-staging-deploy.txt`. Retry with a working browser connection.
  Dark-mode and live OS keyboard checks for this form remain unverified. General
  role/legacy/refund/currency coverage from existing suites is not evidence of
  every combination of these new fields; only named checks are claimed.

### Final live follow-up

- Browser access recovered without authentication/security changes. User reported
  recovery in Chrome too; directly verified in-app reload and authenticated writes.
  Earlier HTTP401 with missing App Check remains unexplained, not claimed fixed.
- Used synthetic `QA payment status 2026-10-14`, QA101, October16–17 in Staging
  Unified. Saved total500,000 VND, deposit100,000, payment150,000, remaining250,000.
  Both date fields saved October15 (property timezone) and distinct notes persisted.
- Unchecked deposit preview left total undeducted; checking deducted100,000.
  Adding payment deducted150,000 more. Agreed-price field appeared without toggle,
  immediately before totals. Live screenshot inspected at normal browser size.
- Quick check-in produced Staying before scheduled arrival. Checkout retained
 250,000 paid and250,000 outstanding. Edit allowed reopening to Staying; saving
  did not collect the deposit/payment again. Final checkout retained same balances.
  Test fixture retained checked out; no real tenant data changed.
- Evidence: `.dart_tool/booking-staging-payment-preview.png` and
  `.dart_tool/booking-staging-verified.png`. Live checks used owner role/VI/default
  viewport. Other roles, concurrent retries, clock boundaries and responsive
  variations rely on the automated/local evidence above, not this live check.
  Non-default payment dates and agreed-price override were not exercised live.
