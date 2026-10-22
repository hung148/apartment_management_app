# Correct recorded payments

Requested priority: correct an already recorded payment's amount, date and note
in short-stay and long-term booking views. Calendar bubble/opacity/title changes
are paused. Prices and agreed totals are not part of this correction feature.

The saved short-stay Payment section and long-term Lease section open the same
recorded-payment editor. It edits the selected receipt in its stored currency.
The server adjusts paid balance by the difference, preserves the original receipt
operation and appends before/after correction history. Booking deposit and rent
projections are updated with their payment document in the same transaction.
Long-term invoice collections are individually selectable. Older direct paid
records remain available alongside subsequent collections. Refunded payment
documents are excluded; this editor does not undo refunds.

## Scenario checklist and evidence

- Access: owner and custom collection grant; reductions additionally require
  refund authority; suspended/revoked membership, foreign target/property and v1
  organization rejected. UI uses existing canCollect/canBill projections. Server
  checks membership, organization and property on reads, writes and retries.
  Unit-tested owner/custom/revoked/foreign/v1; suspended uses the same access
  helper, not a distinct new test. Closed organization fails closed.
- Data: short-stay rent and deposit; long-term individual invoice collections;
  partial balances, multiple receipts, date/note changes, VND/USD cents, legacy
  direct receipt plus later collection. Unit-tested. Long-term contract deposit
  metadata without a payment receipt is not treated as money collected.
- Validation: positive integer minor units, valid property-local date no later
  than today, 500-character note, balance not negative or above amount owed,
  deposit not reduced below already refunded amount. Unit tests cover invalid
  date/future/zero/fractional/overpayment. Deposit refund bound implemented, not
  separately exercised by a new test.
- Reliability: immutable operation IDs for uncertain saves, original values in
  invoiceHistory/paymentOperations, exact retries, stale reads and
  concurrent corrections. Unit tests cover retry/stale; real Firestore emulator
  verifies simultaneous exact retry and competing corrections.
- UI: load/empty/error/reload, selected populated receipt, success refresh,
  invalid amount, uncertain save locks inputs and retains request; labels above
  fields, scrolling notes and reachable actions. Widget checks include EN/VI,
  320 phone, 812 landscape, 1440 desktop, 100/130/200% text and light/dark.
- Actual Roboto screenshots inspected: VI320/200 and VI1440 normal; initial
  floating-label clipping found and corrected with labels above inputs.
  Artifacts: `.dart_tool/payment-corrections/`. Native screen-reader and OS
  keyboard interaction not verified. Calendar shared code was not edited.

## Validation status

- Server full suite: 465 passed before final closed-organization/retry authority
  hardening; targeted correction7 passed after it.
- Real Firestore concurrency test: passed. Uses existing local emulator8092.
- Widget correction flow and responsive matrix passed; additional uncertain-save
  case and full Flutter regression are running before handoff.
- No staging deployment of this correction yet; live verification pending.
