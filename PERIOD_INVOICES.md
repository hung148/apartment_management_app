# B6 period invoices — plan

Authorized as part of the remaining client roadmap. B6a (period invoice) DONE on staging, accepted by Tom 2026-10-02. B6b (move-out settlement) DONE on staging, accepted by Tom 2026-10-03.

## Decisions (Tom, 2026-10-02)

- One invoice per lease payment period: rent and service fees for the coming
  period (paid in advance) + every meter reading not yet billed (usage paid
  behind). B4/B5 single invoices remain possible; a charge is never billed twice.
- Late fees: a manual line the owner adds; no automatic charge.
- Discounts: a manual minus line with a reason (amount or % of rent), this invoice only.
- Move-out: one final settlement invoice — unpaid charges + damages − deposit →
  refund to the tenant or amount still owed.
- Manual extra lines (plus or minus) with a reason. Paid / partial / overdue shown;
  partial payments allowed.

## B6a implementation (period invoice)

Server
- functions/period_invoice.js: input checks, period rent (the lease's own period
  price for one whole unchanged period; otherwise monthly rent per month, or day by
  day when the rent changes inside), the priced lines, and the "already billed" check.
- functions/invoices.js: kind `period` (includeRent, serviceFeeIds, readings, lines);
  new action `periodPreview` (suggested next period, fees in force, unbilled readings,
  permissions). Create links every reading and marks every fee billed; void releases
  the readings. A period invoice and a single rent / fee invoice can never cover the
  same days. Lists add `overdue` (unpaid and past due date).
- Manual lines (late fee, discount, damage, other) need the price permission.
- Tests: functions/test/period_invoice.test.js.

App
- lib/screens/team/period_invoice_form.dart: choose lease, dates (end shown as the
  last day included), tick rent / fees / readings, add lines (discount as VND or %),
  note, review, create with exact retry after a lost reply.
- Invoices page: "Hóa đơn kỳ" button; list rows show what the invoice is for,
  formatted totals, paid so far, and "Quá hạn". Detail shows the period lines, no IDs.
- Tenant page: "Lập hóa đơn kỳ" for main tenants when the person can collect payments.
- Tests: test/period_invoice_form_test.dart (flows + 18 layouts).

Changed behaviour
- Service fee prices (B5) are per month: a 3-month period charges 3 x the price.
  One-month invoices are unchanged.

Decided (Tom, 2026-10-02)
- Keep the rule: dates before today need "Nhập ngày trong quá khứ"
  (backdateRecords), which the owner gives in Phân quyền (Property group). The
  form warns up front when the period starts or is due before today and the
  person lacks it.

## Live check 1 (staging, 2026-10-02)

- Reload shows "Đang mở lại trang bạn đang xem…" and returns to the page. OK.
- Invoices → "Hóa đơn kỳ" → lease list → Le Van Chinh: suggested 2026-10-02 to
  2027-01-01 (3 months), due 2026-10-05, rent 15.000.000 (period price). OK.
- FOUND: the Rác fee was already billed 10-01..10-31 on a single fee invoice, but the
  form ticked it and Review showed it again (600.000). Create was refused by the
  server ("đã có hóa đơn"), so nothing was billed twice, but the person only learned
  at the last step. FIXED: the preview now sends how far each fee is billed; such a
  fee is unticked and disabled with "đã thu đến hết …" until the start is after it;
  the server refuses overlaps already at Review (quote), for every invoice kind.
- Rent-only period invoice created; list row "Thu · Hóa đơn kỳ", inclusive dates,
  15.000.000 VND. Detail shows the rent line. FIXED: the status pill stretched across
  the page; the invoice note was not shown.
- Void works ("Đã hủy"); the period can be billed again afterwards.
- Tenant page: "Lập hóa đơn kỳ" opens the form for that tenant; Back returns to
  the tenant. OK.
- Noted for the design pass: the invoice edit area still shows the old fee fields
  (internet, TV, hot water, late fee, tax) for every invoice kind.

## Live check 2 (staging, after the fix deploy)

- Rác already billed to 10-31: shown unticked, greyed, "đã thu đến hết 2026-10-31". OK.
- Rent + discount 10% ("Khách thuê lâu năm"): Review 15.000.000 − 1.500.000 =
  13.500.000; created; list and detail show both lines, the note and a status pill
  sized to its text. OK. (Left on staging as the open invoice for period 1.)
- Old "Tạo mới" rent form for the same days: refused at "Kiểm tra tính toán" with
  "Tiền thuê hoặc một khoản phí đã có hóa đơn…". OK.
- Meter readings on a period invoice: not checked live (room 101 has no readings and
  the lease started today); covered by the server tests.
- For the design pass: the old form shows the tenant's internal ID next to the name and
  puts its messages at the top of a long page; the invoice edit area still shows the
  old fee boxes for every kind.

## B6b move-out settlement

Decisions (Tom, 2026-10-03)
- Unused prepaid rent: the owner decides each time (a tickable credit line).
- The owner may keep any part of the deposit, with a reason ("Giữ cọc").
- One flow: "Trả phòng và quyết toán" ends the lease and settles together; "Trả phòng"
  alone stays possible, and a lease that already ended can be settled later.
- The deposit pays every unpaid invoice of the lease first (oldest first), then the
  final invoice; the rest is refunded, or the shortfall stays owed on the invoices.

How it works
- functions/move_out_settlement.js, actions on the leaseLifecycle callable:
  settlementPreview (what can be settled for a date), settlementQuote (exact numbers +
  quoteRevision), settle (writes everything in one transaction, exact retry).
- Final invoice (kind `settlement`): rent not billed yet up to the move-out day (by day),
  service fees from where billing stopped, unbilled meter readings, manual lines
  (damage, late fee, keep deposit, discount VND/%, other ±). It counts for the
  double-billing check like a period invoice and cannot be voided.
- Rent credit (optional): each rent invoice reaching past the move-out day is reduced to
  the rent of the days actually stayed (priced by day like any rent): credit = rent
  charged - rent for the stayed days, never below 0. An invoice wholly after move-out
  gives back all its rent. So a period that does not follow calendar months (e.g. 2 Oct -
  1 Nov) still leaves the tenant paying exactly the daily price. Paid money above the new
  total is returned into the pool.
- Pool = deposit + returned money. It pays open invoices (payment method `deposit`),
  then the final invoice. Left over = refund (cash / bank + account); unpaid = owed.
- Records: leaseSettlements/{id} (all numbers, refund way), invoiceHistory entry on
  every touched invoice, tenant settlementId/settledAt, the same move-out records as
  "Trả phòng" (leaseOccupancy, room bookingRevision, leaseHistory), teamActivity.
- Permissions: manageLease + collectPayments; extra lines, kept deposit and rent credit
  need overridePrices; returning money already paid needs refundPayments; a move-out
  date before today needs "Nhập ngày trong quá khứ". Roommates must move out first.
- App: tenant page "Trả phòng và quyết toán" (or "Quyết toán trả phòng" after move-out),
  lib/screens/team/move_out_settlement_form.dart. Invoices list shows "Quyết toán trả
  phòng" with its lines.

Situations covered by tests (functions/test/move_out_settlement.test.js,
test/move_out_settlement_form_test.dart)
- Roommate still living there (blocked, named); future date; date before move-in;
  backdating without permission; lease already ended (fixed date; other date refused).
- Rent credit with refund of paid money; kept deposit above the deposit refused; final
  total below 0 refused; deposit smaller than unpaid invoices (owed stays on invoices);
  rent not billed yet charged by day; nothing left to bill.
- Refund way required when money goes back; bank account must exist; exact retry after
  a lost reply; second settlement refused; settlement invoice cannot be voided.
- Staff without price / refund permission; outsiders refused.
- Layout: 18 language/size/text-scale combinations.

## Staging (deployed 2026-10-03 ~14:05 PT, B6a fixes + B6b incl. fee credit)
Live check (Test v2, Le Van Chinh, form opened only, nothing confirmed): button
"Trả phòng và quyết toán" shown; roommate block names Pham Thi Dung (review disabled);
unpaid invoices listed (period 13.500.000, service fee 193.548); "Tiền trả trước" offers
rent back 14.677.419 (2 Oct - 1 Jan minus 2 days = 322.581) and fee back 180.644 (2
people x 2/31 of 100.000 kept) - both match hand calculation. Tom OK 2026-10-03: B6b DONE.

## Local check (emulators, 2026-10-03)
1. Lease from 1 Aug, rent 3.000.000, deposit 3.000.000; August unpaid (3.100.000),
   Sep-Oct paid ahead (6.200.000). Settle 3 Oct with rent credit + damage 200.000, cash:
   credit 2.806.452, deposit pays August then the damage, refund 2.506.452. Invoices:
   August paid, Sep-Oct 3.393.548 paid, final 200.000 paid. Settle button gone after.
2. Lease moved out first ("Hợp đồng và trả phòng", 2 Oct), settled later: date locked
   with a note, rent 1 Sep - 1 Oct 5.161.290 + fee 103.226, deposit 1.000.000, owes
   4.264.516; final invoice shows partly paid.
3. Lease from 2 Oct, 1-month period 2 Oct - 1 Nov paid (3.100.000 + fee), settle 3 Oct,
   credit + bank transfer to an account: found the credit was priced by calendar months
   (3.003.333, tenant would pay 96.667 for 1 day) -> fixed rule above, now 3.000.000;
   refund 5.000.000 by bank. No empty 0 invoice is made.
4. (12:55 PT, fresh local data) Lease from 2 Oct, period 2 Oct - 1 Nov paid (3.100.000
   rent + 100.000 fee "by days"), settle 4 Oct with both boxes: rent back 2.900.000, fee
   back 93.548, deposit 1.000.000 -> refund 3.993.548 cash. Invoice kept 206.452 (2 days
   of rent 200.000 + fee 6.452). Fee credit option works end to end.
Fixed during the check: credit line now "+" and the review reads deposit, + rent back,
- what it pays, = result; the "choose how" warning clears when a way is picked; a
settlement with no rent days shows only the move-out date in the invoice list.

Not covered yet
- Fee credit: Tom (2026-10-03) wants it as a separate OPTION. Server done (`creditFees`,
  `feeCredits`; each fee re-priced with its own stored short-stay rule as if the lease
  left on the move-out day; 2 new tests). App checkbox done and checked locally (check 4) (see HANDOFF.md
  "PICK UP HERE").
- Undo of a settlement (by design: none).
