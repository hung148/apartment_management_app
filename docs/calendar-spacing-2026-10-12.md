# Calendar width and hour spacing

Request: use the window width, separate the two-hour labels while keeping the
same visible day range, and omit “Tháng” from the Vietnamese month heading.
Preserve the existing uncommitted compact rows, filler rows, scrolling and hover.

## Situations to review

Follow-up: reduce vertical space. Target 30 px regular rows (was 36), keeping
24 px stay bars, and a 48 px date/hour header (was 72, or 52 on short screens).
The existing text scaling cap remains. Recheck long room names, cleaning/status
icons, long tenant badges, hourly prices, overlap lanes, filler rows, hover and
current-time alignment. The role/access, state, retry and legacy scenarios below
still apply; no server/data changes. Review both scopes, locales and text scales
using populated actual-font renders before the final Wasm staging release.

Compact follow-up local verification: both new height regressions failed before
the fix (72 vs 48 px header; 36 vs 30 px row pitch). After the fix, all 71
targeted tests and all 989 full-suite tests passed sequentially. This supersedes
the four short-landscape failures recorded below: the compact header resolves
them. Inspected populated VI desktop, VI320 at200% and dark VI812 at130% renders;
booking bars retain height, overlapping lanes remain separate and long room
names fit their two-line cells. Existing narrow-phone header truncation remains.
Focused analysis: no errors/warnings, four existing informational notices.

Compact follow-up deployment: Wasm release build and staging Hosting deployment
succeeded. Reloaded the signed-in app; main.dart.mjs startup logs confirm Wasm.
Inspected the 1440x900 desktop with hourly/multi-day sample bookings and the
800x360 landscape layout. Verified previous/next month and property selection;
no browser errors/warnings observed. Saved staging-compact-desktop.png and
staging-compact-landscape.png in `.dart_tool/calendar-spacing/`. Production and
backend unchanged. Safari/Firefox fallback execution remains unverified here.

- Owner, administrator, manager, receptionist, accountant, investor, housekeeper
  and custom roles: retain server-projected rooms, anonymous stays and allowed
  actions. Suspended/revoked/foreign accounts must still be refused by the server.
  This change touches presentation only; no new authorization or writes.
- Loading, failed load/retry, access denial, no properties and no rooms: retain
  existing notices and recovery controls. Populated fixtures include vacant and
  occupied rooms, long room/tenant names, a lease with roommate badge, hourly
  stays, overlapping bookings, blocked rooms and missing property time zone.
- Next/previous month, cross-month/year scrolling, property switching, hover,
  opening/closing stays and empty-cell actions: alignment and day range stay
  consistent. Repeated actions and late responses retain existing guards.
- Legacy v1 calendar is separate and unchanged. V2 calendar records and all
  server writes/financial fields remain unchanged; historical records continue
  through the same projection.
- Touched presentation: outer calendar/header margins, numeric Vietnamese month
  heading and two-hour ruler spacing (including the current-time badge). Keep
  all twelve labels and grid/hover/current-time alignment.
- English/Vietnamese; 320/390 phones, 812 landscape, 1440/2048 desktop;
  100/130/200% text; standalone and workspace scope; representative light/dark
  actual-font renders. Existing 130% calendar text cap remains in effect.
- Local widget regressions first, targeted calendar tests, then full sequential
  Flutter suite because the calendar layout is shared. Inspect generated images
  separately; record live-browser and server verification gaps honestly.

## Evidence

- Before the fix, retained regressions failed for the expected reasons: desktop
  left gutter 40 px (requested at most 12), adjacent rendered hour-label gap 2 px
  (requested at least 5), and heading “Tháng 10, 2026”. All three pass after it.
- New suite: 5 tests pass, including 60 populated locale/size/scale/scope
  combinations, all twelve two-hour marks, seven-day desktop range, midnight
  spacing, and same-year/cross-year month headings. The English month names and
  compact phone date format are retained.
- Actual Roboto/MaterialIcons renders inspected in `.dart_tool/calendar-spacing/`:
  VI 2048 desktop, EN 1440 desktop, VI 320 at 200%, and dark VI 812 landscape
  at 130%. Wider card, separated ruler labels, current-time badge and populated
  overlap lanes were reviewed. The existing narrow-phone title ellipsis/property
  fade remain; hour labels are necessarily small with twelve marks per 160 px
  phone day. These are known limitations, not a claim of complete mobile polish.
- Focused Dart analysis: no errors/warnings; four pre-existing informational
  notices in `room_calendar.dart`. Whitespace check passed.
- Targeted existing calendar/screen/workspace run: 56 passed and one width
  assertion failed because it measured the scrolling timeline without the fixed
  room column. The assertion now measures the entire calendar card and retains
  the >1300 px requirement. It passes in the full run.
- Full sequential Flutter suite: 983 passed, four failed. All calendar and role
  workspace checks passed. The four failures are the direct-workspace fixture
  at 800x360, EN/VI, 130/200%: a 0.600 px bottom RenderFlex overflow. Re-running
  all four with the previous margins, hour spacing and single-month heading
  restored reproduced the identical failures. They are existing short-landscape
  limitations, not introduced by this spacing change; they remain unresolved.
  Current code was restored automatically after this baseline comparison.
- Also visually inspected the actual desktop workspace fixture in
  `.dart_tool/organization-layout/en-1440-1.0-calendar-board.png`; full-width
  card and fixed room/timeline alignment were reviewed. This fixture enables
  historical calendar tools for coverage; the new screenshots use default tools
  hidden, as required by the latest calendar design.
- No fresh backend/emulator authorization or real-device test, and no production
  change. Server logic and legacy-v1 UI were
  not edited. Workspace-scope renders are widget fixtures; the actual shell is
  exercised separately by the existing workspace regression suite.

## Staging release and live verification (2026-10-12)

- Built with `flutter build web --release --wasm` and the staging defines;
  Hosting-only deployment to `apartment-management-staging` succeeded. An earlier
  JS-only local build was corrected before deployment. Updated stale build
  examples in tool/STAGING.md and WEB_DEPLOYMENT.md to match CLIENT_ROADMAP W3.
- Generated bootstrap lists dart2wasm/skwasm first and dart2js/canvaskit fallback.
  Both main.dart.wasm and main.dart.js are present. Browser startup logs from
  main.dart.mjs confirm the live Wasm runtime; server calendar data loaded.
- Inspected signed-in Vietnamese desktop at 2048x1021: approximately seven days,
  12 px gutters, separated two-hour marks, numeric single/range month headings,
  empty rooms and populated sample bookings. Checked next-month transitions to
  September and October and property switching to Nhà Mẫu A.
- Inspected live 390x844 phone layout; controls visible, compact month heading.
  Browser reported no errors/warnings during these checks. Resizing moves the
  visible date window in the existing calendar implementation.
- Screenshots: `.dart_tool/calendar-spacing/staging-wasm-desktop.png` and
  `staging-wasm-phone.png`. Safari/Firefox fallback execution was not tested;
  only fallback packaging/configuration was verified. Existing four automated
  short-landscape failures above remain unresolved.
