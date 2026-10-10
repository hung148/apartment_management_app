# Live performance checks — 2026-10-09

Target: usable fresh data within one second. This is a target, not a guarantee
for cold starts, interrupted connections, large organizations or every ISP.

## Before this change

Staging, existing owner session, desktop in-app browser. Browser measurements
include automation overhead; server measurements exclude network and rendering.
This is not a controlled Vietnam ISP test.

| Fresh-data interaction | Three browser samples (ms) |
| --- | --- |
| Tenant list (empty selected building) | 792, 555, 554 |
| Invoices (empty selected building) | 533, 542, 544 |
| Account ownership option available | 720, 512, 512 |
| Calendar reload (all accessible buildings) | 1275, 1873, 1576 |
| Staff directory (three populated profiles) | 1975, 1123, 1322 |

Server calendar requests: n=8, median 640ms, p95/max 1183ms; handler median
503ms, max 940ms. Initial workspace request was 1711ms (guard 1647ms).
Initial browser authentication also had a network error; manual retry recovered.
Do not count a cached page shell as fresh-data completion.

## Changes

- Load up to four calendar buildings together, preserving sorted result order
  and existing per-building access filtering. Avoid unbounded query fan-out.
- Reuse one date formatter throughout each day-boundary binary search. The
  previous implementation constructed 59 formatters for one tested boundary;
  now it constructs two including timezone validation. No global data cache.
- Staff listing returns the caller's fresh access projection in the same server
  transaction, removing a separate access request. The client falls back to the
  old access endpoint if an older server does not include this projection.

## Scenario review and verification

- Owner, restricted staff, own-booking privacy, cleaning-only staff, suspended,
  signed-out and foreign-organization callers: calendar unit coverage. Existing
  request guard and handler authorization remain unchanged.
- Empty properties, populated bookings/leases, deposits, invoices, room moves,
  cleaning, missing timezone and date-window filtering: existing projection
  tests retained. Nine-building fixture checks bounded concurrency and identical
  complete projection/order; regression failed with serial loading before fix.
- DST spring/fall, skipped midnight, skipped whole day, invalid dates/timezones,
  backdating rules: date tests retained. Formatter construction regression failed
  before fix (59 versus allowed 2).
- Read retries/double taps: no writes or new shared authorization cache. Each
  request has independent output; a failed building read rejects the request
  instead of returning a partial successful projection. Concurrent rate limits
  remain in the unchanged server guard.
- Legacy/v2: calendar retains its v2 gate; shared date helper preserves legacy
  callers and existing date policy behavior. No financial fields are rewritten.
- Staff loading: one-response regression reproduced before fix; pagination,
  delayed response after organization change, empty/error/suspended states,
  denial clearing previous records, and older-response fallback pass locally.
- UI: no layout, fields or translations changed. Existing populated staff
  EN/VI, viewport, text-scale and theme widget matrix passed; no new screenshots
  rendered for the timing-only change. Live checks cover existing staging data,
  not every data size.

## Backend release results

Release `2026-10-09t15-17-31-714z`: app backend deployed; verifier confirmed four
active functions, both unauthenticated probes denied, and indexes ready.

Calendar reload after deployment: 1610, 822, 792, 780, 1146ms; median 822ms
versus 1576ms before (small samples, varying network). Six calendar server calls
including the first request: median 553ms, max 2028ms; handler median 414ms,
max 704ms. Slowest guard was 1493ms. Thus warm speed improved, but tail latency
and initial loads still miss the one-second goal. Do not report universal success.

Full server suite: 402 passed. Full Firestore integration suite: 84 passed.
Targeted Flutter staff/service tests: 11 passed, including populated layout
matrix and the single-request regression. Full Flutter suite and web release
remain in progress until final results are added below.
