# B5 service fees — next implementation

DONE on staging — accepted by Tom on 2026-10-02.

## Implementation (2026-10-02)

- Server: `functions/service_fee_math.js` (rules, shares, rounding, period resolution), `service_fees.js` (callable `serviceFees`: read / define / rename / roomRate), `service_fee_invoice.js` (per-person source for `invoices` kind `service`, billed markers). Documents: `serviceFees/{hash(org,building)}` (fees with dated versions, `billedThrough`) and `serviceFeeRooms/{hash(org,room)}` (dated room overrides: rate / off / inherit, per-fee `billedThrough`). Operations in `serviceFeeOperations`; activity `service_*`.
- Rules: price changes inside a billed period are refused (`service_fee_boundary_required`, bill to the change date); new versions/overrides cannot be dated before what was billed; void keeps the billed marker (conservative). Quantity extras bill one service date (period = that day) and may repeat; other fees refuse overlapping invoices per fee, room and lease. People = the lease's main tenant and its roommates, from current records and `leaseOccupancy`; roommates count only on days the lease is in the room. A person present the whole period always pays 100%.
- Permissions: read with lease or finance access; define/rename/room rates need price authority; billing uses invoice permissions (collect payments; backdate rules apply).
- Room/property deletion is refused while fee documents exist; organization copy remaps both lookup IDs; purge removes them (organizationId).
- App: Rooms → "Phí dịch vụ" page (property fees, add / dated change / stop / rename); room list → "Phí dịch vụ" per room (room price, off, invoice with per-person review; address `fees--<room>`); invoice details show the fee and lines.
- Verified locally: all server suites pass (27 new B5 tests: rules, shares, thresholds, check date, free people, rounding, quantity, boundaries, overrides, billing, duplicates, backdating after billing, retries, permissions, currency, past rooms, void, copy). Flutter: full run 382 passed; the 7 failures found (accountant saw Rooms; rounding dropdown, tenant chips and long chip labels overflowed at 130%/200%) were fixed and the targeted rerun passed before deployment.

Live check on staging (2026-10-02 evening, Test v2, Vietnamese, desktop pane): added "Rác" (per person, 100.000 VND, by days, from 2026-10-01) — worked example and list summary correct; room 101 fee page opens with the `fees--<room>` address; invoice review for October showed Le Van Chinh and Pham Thi Dung 30/31 days → 96.774 VND each (lease moved in 2026-10-02), total 193.548 VND; invoice created and listed in Thu chi with the fee name and per-person lines; a second invoice for the same fee, lease and days was refused with a clear message, form kept; the fee editor shows the billed boundary (2026-11-01). Fixed after the check (not yet deployed): the change date now starts at the first allowed date after billing; the review no longer repeats "Ở không đủ kỳ". Noted for B6 (invoice screen): end date shown exclusive, totals without separators, internal invoice ID and English status on the detail; a duplicate is only refused at Create, not already at Review.

Property definitions support a fixed room fee, a per-person fee, and quantity-based extras (parking, laundry, internet, cleaning). Rooms inherit property defaults and can carry explicit dated overrides. Store money in currency minor units and freeze the definition, quantity basis, interval and calculation when billed. Do not reuse utility meter quantities for unrelated services.

## Decision: partial-period rule (Tom, 2026-10-02)

One setting per fee, used for per-person fees and for the fixed room fee when a lease starts or ends inside a period. Each person (or the room) gets a counted share from 0 to 100%; charge = rate × sum of shares.

1. **By days (default):** share = days present ÷ days in the period.
2. **By day thresholds:** owner-defined steps "at least X days → Y%" (presets: any day = 100%; ≥15 days = 100%; ≥1 day = 50% and ≥15 days = 100%). Fewer days than the first step = 0%.
3. **By check date:** people present on the period's first or last day count 100%, others 0%.

Optional: people included free (fee starts from person N+1; the first N by move-in date are free), and rounding of each line to a currency step (e.g. 1,000 VND). The rule is frozen on each invoice; invoice lines show "name: days/period days → amount".

## Situations and verification plan

- Owner, limited co-owner, scoped manager and staff: server checks financial/lease access for reads and billing, plus price authority for definitions. Deny outsiders, revoked/suspended members, closed organizations and foreign property/room/tenant IDs. Keep legacy v1 behavior separate.
- Empty definitions, disabled service, inherited versus overridden price, zero price, missing currency, loading, permission loss, failed reads and uncertain saves. Provide explicit retry/reload paths.
- Fixed operation IDs for retries; double taps, concurrent rate changes and invoice creation cannot duplicate charges. Quote revision must bind the price, quantity and occupancy used.
- Per-person fees must explain the people counted and interval. Occupancy changes and move-in/out must use dated occupancy evidence; do not silently charge today's headcount for an older period. Proration policy must be explicit before billing partial periods.
- Quantity extras need a measured/entered quantity, service date and reason. Validate decimal limits, negative/oversized values, currency, timezone and backdate authority.
- Effective dates preserve old charges; edits or cancellation retain history. Paid invoices require existing refund/void handling. B6 combines eligible unbilled charges without billing them twice.
- Copy/export, room/property deletion, organization closure/purge and account deletion must preserve or remove related records consistently.
- English/Vietnamese, populated long names, phones/landscape/desktop and 100/130/200% text: no truncated names or multi-line action labels; inspect actual-font screenshots and live staging states.

Begin by extending shared invoice calculation/source handling rather than creating an independent payment system. B4 already provides reading-linked invoice transactions and void/rebill protection to use as a reference.
