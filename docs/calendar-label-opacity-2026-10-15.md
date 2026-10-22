# Calendar names, opaque bars and current time (2026-10-15)

Approved scope: complete bubble names; opaque timeline bars while retaining paid/unpaid shades; current-time line above bars and bubbles; property title wraps. On phones the property selector gets a full-width row. End time is below the bubble name to avoid competing for width.

## Scenarios

- Owners, authorized staff, anonymous occupancy and denied records: rendering only; no changes to server authorization, reads, writes, membership or organization boundaries. Existing role tests retained; no new suspended/revoked/cross-org live fixtures.
- Empty, loading, error/retry, missing timezone and multiple properties: existing calendar tests retained.
- Booking, lease and cleaning bars; partially paid, fully paid and unpaid; long names, long room labels, hourly rates, roommate badges, overlaps and edge slivers; scrolling, month navigation, opening the correct record, and cleaning bubbles below the last row.
- Full names wrap; end time remains visible; bubble dimensions participate in placement. Dense calendars still use existing least-overlap fallback, so simultaneous labels can overlap when no free area exists.
- Current-time line is last in the timeline stack with IgnorePointer, above bar/bubble paint without consuming clicks. Header marker stays aligned.
- Paid/unpaid color shades remain distinct but are composited against an opaque surface before painting. Month-view fills were already composited and unchanged.
- English/Vietnamese,320x740 phone,812x375 landscape,812x255 constrained workspace,1440x1000 desktop,100/130/200% text. Client/legacy toolbar variants retained; dark-mode paint check added. Physical devices and screen-reader navigation not independently verified.
- No persistence/schema changes; legacy/v2 share rendering. Retries/concurrent commands unchanged because this change adds no writes.

## Evidence

- Before fix: current-time layering regression failed (.dart_tool/calendar-opaque-before.txt).
- Initial responsive tests reproduced narrow enlarged bubble overflow; fixed by giving end time a separate line and reserving measurement space while scrolling.
- Calendar39 tests pass, including full-name paragraph containment assertions and opaque fill/layer ordering. Final full suite adds dark-mode coverage; release log .dart_tool/calendar-opaque-release.txt.
- Actual-font screenshots inspected: Vietnamese desktop100% and phone200%. Phone title initially wrapped into very narrow fragments; fixed with separate full-width selector row and inspected again. Screenshots under .dart_tool/calendar-layout.
- Full regression completed:1042 passed,9 failed, all reporting vertical overflow in short embedded calendar/workspace views. Release stopped before deployment. Fixed by providing a vertically scrollable320px calendar in shorter viewports; retained existing assertions and added a direct header/grid reachability regression. Affected suites are rerunning in .dart_tool/calendar-embedded-tests.txt.
- Dark-theme screenshot inspected: paid/unpaid shades distinct and opaque, red current-time line above bars. Final staging verification pending.
- Follow-up affected suites:109 checks passed, including all9 previously failing cases. New compact-layout test originally hit-tested the full multi-month canvas center (outside the viewport); corrected to hit-test the visible horizontal scroll viewport, retaining the reachability assertion. Final release gate in .dart_tool/calendar-opaque-final.txt.
- Completed October16: final calendar41/server473 passed; analyzer gate completed without errors (existing warnings/info remain). Wasm build and staging hosting release succeeded; backend/rules unchanged and skipped. Full suite was not rerun after the compact-layout fix; all affected files were rerun and all original failures resolved.
- Inspected compact-landscape screenshot after scrolling: date header/grid reachable with opaque bars and topmost current-time line. Final live staging screenshot .dart_tool/calendar-labels-live.png shows the original QA name in full, the complete long property title wrapped across two lines, no calendar grid through the booking fill, and red current-time line crossing above the bar. No booking data changed during this calendar verification.
