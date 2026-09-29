# Operational workflows — combined acceptance guide

This guide covers the operational replacement batch. Source changes are local;
backend/rules/client deployment and real-account acceptance remain release work.
Do not migrate an organization solely because the disposable preview works.

## Start the disposable preview

```powershell
flutter run -d chrome -t lib/team_preview.dart
```

Choose Owner, Riverside. In Property details, select Asia/Ho_Chi_Minh and save.
The preview's fixed business date is 2026-09-27; reloading resets sample records.
It does not connect to Firebase. Server authorization, transactions, DST and
concurrency are verified separately with emulator tests.

## Property defaults

Open Property layout and room defaults. Set floors to 2, counts to `2, 3`,
prefix to `R`, default type to `Studio`, area to `35.5`. Save and reload.
Existing rooms must retain their details. Manage rooms → Add room should suggest
the prefix/type/area; review and complete the room number before saving.
These are inventory descriptors/defaults, not an automatic bulk room generator.
Prices, rental mode, operating windows and timezone have their existing editors.

## Lease terms, room moves and move-out

Open Tenants → Lease terms, moves and move-out for Anh. Set contract end to
2026-12-31 with a reason, review and confirm. The room remains occupied; the
agreement end date is not a move-out. Check Lease change history.

Add a roommate with the existing Add roommate action. Trying to move or end the
main tenancy must require that roommate to be handled first. Open the roommate's
lease actions and record move-out for 2026-09-27 with a reason. Then move Anh to
vacant room 102 on 2026-09-27, reviewing the destination and reason first.

The server supports moving a roommate into another existing main tenancy by
choosing its destination main tenant. It checks current access to both
properties, destination occupancy/bookings, monthly rental mode and currency.
Moves are actual events, not future scheduled moves. A move must occur after
the start of the current room occupancy; same-instant moves are rejected.
Past moves/move-out require owner/admin and a reason. Former occupancy remains
available for booking-conflict checks and property-specific invoices.

After testing the move, test move-out separately using Reset sample data and
reselecting the property timezone. Existing rent schedules, invoices and payment
records must not be rewritten by a move or move-out. There is no hard deletion.

## Invoices and building expenses

Reset sample data and set the timezone. Open Invoices and building expenses →
Create new → Tenant rent. Choose Anh, period start 2026-10-01, end 2026-11-01,
due date 2026-10-05, zero fees and a reason. Review calculation, then confirm.
The end date is excluded: October 1 to November 1 covers all of October.
The full-month baseline is 1,500,000 VND in the sample.

Before creating another test invoice, schedule rent of 3,000,000 VND effective
2026-10-16. A fresh October quote should be 2,274,194 VND:
15 days at 1,500,000/31 plus 16 days at 3,000,000/31, rounded once. An already
saved invoice retains its original amount. Overlapping non-void invoice periods
for the same tenant and type are rejected; void an unpaid test invoice first.

Edit fees and due date with a reason; the saved rent principal stays fixed.
Review Financial history. Use the workspace's collection/refund action on a new
income invoice. The total cannot be reduced below its collected balance, and a
paid invoice cannot be voided until its full balance is refunded. To correct the
rent principal or period, refund if necessary, void and reissue.

Other tenant charge supports electricity, water, internet, parking, maintenance,
deposit, penalty and other charges. Enter a unit price and quantity (up to three
decimal places); the server calculates the charge in exact minor units. Price
permission is required for these custom charges and nonzero additional fees.

In Whole-building contract, configure an active rent-in contract, then create a
Whole-building rent invoice. It must show Expense. Record an expense payment and
reverse part of it with a reason. It must never offer income collection. Repeat
with rent-out: the resulting invoice must show Income and support collection.
Contract terms are copied into the invoice so later contract edits do not change
saved invoices. Contract end dates are inclusive; invoice period ends are exclusive.

Manager/accountant cannot enter past invoice start or due dates; owner/admin can
with a reason. Existing legacy invoices remain preserved and collectable through
the existing authorized payment workflow; the new fee editor operates on v2
invoices with an explicit calculation snapshot.

## Bookings

Use vacant room 102. Set Pricing and rental mode to hourly/both and an hourly
price of 100,000 VND. Open Manage bookings → Create new. Enter a guest, arrival
2026-10-01 09:00 and departure 2026-10-01 11:00 in the property timezone.
Review should show 200,000 VND; confirm and reopen it.

Confirm the booking, check in, collect a partial payment, collect a deposit if
one was required, refund deposit separately from booking-payment refunds, and
check out. Checkout explicitly collects the remaining booking balance. Cancel
and no-show are retained status changes, not deletion.

Receptionist can use configured server-calculated rates but cannot set a custom
price. Owner/admin or a manager with price permission may enter a custom total
with a reason. Hourly calculation uses elapsed time; daily/overnight rates charge
each started 24-hour block. A configured daily threshold switches hourly pricing
to daily pricing. Room operating windows, closures, cleaning gaps, minimum stay,
current and historical tenant occupancy and other bookings are enforced by the
server when saving. DST skipped times are rejected; repeated times offer first
or second occurrence explicitly. Amounts use the room currency.

## Access and recovery

Try all relevant roles and selected-property scopes. Viewer is read-only;
receptionist has booking/payment actions without lease/property/financial-report
management; housekeeper retains the housekeeping workspace. Managers still obey
price/refund overrides. Revoke access between loading and saving: writes must be
denied and private response data cleared. These cases require the emulator or
staging to verify actual authorization, not merely changing the preview dropdown.

Invoice and booking operations save their pending request locally before sending.
After a lost reply/reload, retry the identical request; it must not create another
invoice, booking or payment. Storage failure must not send the financial request.
Pending requests are isolated by account, organization and property. Lease and
property edits retain exact retry requests while their forms remain mounted.

## Automated checks

Flutter checks must run sequentially:

```powershell
flutter test --concurrency=1
```

Backend unit and emulator suites require the project's installed Node/Firebase
runtime and a demo project. Never point integration tests at production.
Automated test results, screenshots and remaining live verification gaps are
recorded in TEAM_ACCESS_IMPLEMENTATION.md when the batch validation completes.
