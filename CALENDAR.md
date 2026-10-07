# Calendar (C1–C3) — first screen of the two-screen layout

Tom, 2026-10-03: the app will have two main screens, **Calendar** and **Staff
management**, each different per role. This is the Calendar. The old sections
stay (calendar is now the first tab) until the second screen is built; then they
move into it.

## Decisions (Tom, 2026-10-03)
- Rooms are the rows, days are the columns (timeline). Tom first answered the other
  way round, then corrected it the same evening. All properties the person can see,
  grouped under a property band; a property filter narrows to one.
- Pages open as dialogs over the calendar (full screen on phones): a stay → its
  booking page or tenant page; an empty day → new short stay / new lease / report
  a problem for that room and date; a room header → its problems.
- Old sections are kept for now ("Keep, move later").

## How it works
- Server: `functions/calendar_view.js`, callable `calendarView`
  `{organizationId, from, to}` (property-local dates, `to` exclusive, max 100 days).
  Read-only; every write still goes through bookingWorkspace / tenantLeases /
  tenantContacts / technicalProblems. Endpoint count now 42.
- Per property: rooms (number order, shortStay/monthly, blocked, open problem
  titles), today, what the person may do (create bookings, leases, problems).
- Bars: short stays (pending/confirmed/checked in/checked out; cancelled and
  no-show hidden), leases in their current room (from `occupancyStartDate` after a
  room move, else move-in; to move-out, open-ended otherwise, contract end shown
  as "HĐ dd/MM"), and earlier rooms of a moved lease (`leaseOccupancy`).
- Colour = kind: short stay (blue), long-term (green), deposit paid – not checked
  in (amber), someone else's stay (grey, no name/money).
- Dot = payment. Booking: green paid in full, orange only the deposit paid
  (nothing of the stay), red anything else still owed. Lease: green when the rent
  is paid past today and no started rent invoice is unpaid; red otherwise; orange
  for a lease not started yet with a deposit; moved out: green when settled.
- Darker part of the bar = paid. Booking: paid share of the stay ("paid until").
  Lease: up to the end of the last paid rent period (tenantRent, or period /
  settlement invoices that include rent). Thin lines = start of each payment period.
- Icons: not arrived / staying / checked out, phone number, problem in the room,
  "+N" people living with the tenant. Tooltip (hover / long-press) has the details.
- Privacy: a person who may not open a record (bookings limited to their own, or
  no lease access) still sees the room is taken as a grey "Taken" bar, so nobody
  double-books; the server sends no name, phone or money for it.
- Who sees the calendar: per property, anyone with readBookings, createBookings,
  manageLease or manageProperty. Housekeepers only (tasks) get no calendar.
- Flutter: `lib/screens/calendar/room_calendar.dart` (`RoomCalendar`,
  `CalendarPageDialog`); section `calendar/board` first in `role_workspace.dart`;
  phone bottom bar: Calendar, Bookings, Rooms, Tenants, More.
- Dialog mode added to existing pages: `BookingWorkspaceScreen(onClose, startNew,
  initialRoomId, initialStart, initialEnd)`, `TenantContactsScreen(onClose)` (its
  sub-pages return to that tenant), `TenantLeaseScreen(initialRoomId,
  initialMoveIn)`, `TechnicalProblemsScreen(reportRoomId)`. "Back to the list"
  closes the dialog; the calendar reloads after every dialog.
- New short stay from a day: that day 14:00 → next day 12:00 (editable).
- Preview store answers `calendarView` (sample lease + Airbnb stay).

## Situations
- Roles: owner / manager (all), receptionist (bookings, no leases → leases grey),
  own-records staff (others' bookings grey), housekeeper (no calendar), suspended /
  other organization / v1 organization (refused). Server re-checks everything.
- Empty: no property → message; property with no rooms → "No rooms yet" column;
  property without time zone → warning in its header, taps say to set it.
- Error → notice + Retry; lost access → "no longer have access".
- Overlapping stays (should not exist) sit side by side; a 3-hour stay keeps a
  tappable minimum height; stays crossing the month edge are cut at the edge.
- Room closed by a problem: tinted from today, new stay options disabled, report
  still possible.
- Month buttons, Today (scrolls to today), compact rows, filters: all / free
  today / occupied today / problems.

## Tests
- `functions/test/calendar_view.test.js` (10): bars, local times, pay rules,
  roommates, room move history, privacy, refusals, missing time zone.
- `test/room_calendar_test.dart`: en/vi × 320×740, 812×375, 1440×1000 × 100/130/200 %
  (screenshots in `.dart_tool/calendar-layout/`), columns/filters, months/Today,
  dialogs (lease, booking, new stay, new lease, problems), no-access bar, errors.
- `test/role_workspace_test.dart` updated for the new first section.

## Not done yet / next
- C2 year view (month only for now), week zoom. Cleaning tasks on the calendar.
- Drag to move/extend a stay. Speed: reads all bookings/tenants of each property
  per month (fine for anh Hưng's size; add a date index if it gets slow).
- The Staff management screen, then moving the old sections into the two screens.

## Local check (2026-10-03, local emulators, Claude in the app pane)
Fresh "Local Test" (owner), Nha A, rooms 101–103. Verified:
- Calendar opens with rooms as columns, today highlighted, scrolled to today.
- Empty day on a monthly-only room offers only lease + report; on a short-stay room
  also short stay. New lease from 6/10: room and move-in prefilled, saved, bar
  appears (orange dot: upcoming with deposit). New short stay from 7/10: room 102,
  14:00 → next day 12:00 prefilled, Airbnb, saved; deposit recorded → amber bar,
  orange dot; 500,000 of 1,000,000 paid → blue bar, red dot, top half darker.
- Tapping a stay opens its page in a dialog; the page's Back closes it; calendar reloads.
- Problem reported with "stop renting" from a day: room header red icon, column
  tinted from today, new stay options disabled, "Có sự cố" filter shows only 103.
- Phone width (375): two-line toolbar with "10/2026" and ⋮ menu; bars readable.
Fixed after the check: problem "Xong" now closes the dialog (was: problem list).

## Design notes for the pass
- Lease form success text says "Quay lại Người thuê…" also when opened from the calendar.
- (Old) Creating a property stays on its details page instead of opening its rooms.
- (Old) Room list is not in number order (101, 103, 102).

## Timeline layout (2026-10-03, rooms = rows)
Room names fixed on the left, day header fixed on top; the month scrolls sideways,
rooms up and down. Bars run left to right; paid part fills from the left; lease
period lines are vertical; end time / contract end at the right end (bars ≥110 px);
bars under 40 px show only the payment dot. Today is a column; the view opens with
today near the left. Days widen to fill wide screens. Checked locally on desktop and
375 px phone with the same data (lease, Airbnb stay, problem on 103): taps on a day
and on a stay work. Browser note: after a local rebuild a cached old app can show —
reload with the cache cleared.

## Changes (Tom, 2026-10-03 evening)
- Removed the room filters and "Thu gọn". Day header on one line: "T5, 1".
- One building at a time: its name (or a picker when there are several) above the
  calendar, with "Tạo tòa nhà" and "Tạo phòng" next to it (who: create building =
  all-buildings + manageProperty; create room = manageProperty for that building).
  An empty organization shows "Tạo tòa nhà đầu tiên".
- Building pages moved into a dialog: tap the building name row in the calendar →
  Thông tin tòa nhà / Hợp đồng thuê cả tòa nhà / Sơ đồ tòa nhà và mặc định phòng /
  Phí dịch vụ (same permissions as before). Removed: Rooms section, Settings →
  Thông tin tòa nhà, Hợp đồng thuê cả tòa nhà, Tạo tòa nhà.
- Room pages in a dialog: tap a room (manageProperty) → that room's card with
  Sửa thông tin / Cài đặt đặt phòng / Điện nước / Phí dịch vụ / Giá và hình thức, plus
  "Sự cố" in the title bar. Without manageProperty, tapping a room shows its problems.
  `RoomDirectory(onlyRoomId, startCreate)`.
- Old addresses `/rooms/...` and `/settings/property|contract|newProperty` now fall
  back to the first allowed section.

## Short-stay pricing (Tom, 2026-10-03)
- Only "Theo đêm" and "Theo giờ". Removed "Qua đêm" and "Theo ngày" from the form
  (the server still prices them for older app versions; old bookings show as before
  and are priced again per night/hour when edited).
- Theo đêm: "Số đêm" and "Giá mỗi đêm" side by side. Typing nights moves the check-out
  date (same time); changing dates updates nights. Total = nights × price, or the
  sum when "Giá khác nhau mỗi đêm" is on. Live "Tạm tính" line; the server's quote is final.
- Theo giờ: "Số giờ" (from the times) and "Giá mỗi giờ"; total = hours × price, never
  switched to a day price. Server: `hourlyPriceMinor` (bookingWorkspace quote/save),
  stored as `hourlyPrice` on the booking and kept on edits that leave it out.
- The price box is the room's price; only "Đổi giá" (overridePrices) can change it
  (server checks: another hourly price or night prices need overridePrices).
- Tests: functions booking_quote / booking_workspace / booking_details (+3);
  test/booking_form_test.dart (+3).

## Live-check fixes and deposit (Tom, 2026-10-04)
- "Tạo tòa nhà" / "Tạo phòng" dialogs close once the building or room is created
  (`PropertyDetailsScreen.onCreated`, `RoomDirectory/RoomDetailsScreen.onCreated`); the
  calendar then shows the new building. This also removed the "X needs two clicks"
  after creating a room (the X first went back from the edit form to the room card).
- Pages inside a calendar dialog (`DialogPageScope`, workspace_page_scope.dart) drop
  their own big heading, the "Không gian làm việc"/"Quản lý phòng" link where it only
  closed the dialog, and reload buttons (shown again only if loading failed). A
  sub-page inside the room dialog says "Quay lại". The booking dialog has no
  "Quay lại" / "Đặt phòng mới" heading (`WsHeader` hides an empty title).
- Room type is optional (server room_details.js + form label "Loại phòng (tùy chọn)").
- Room prices: Giá thuê theo tháng, Giá mỗi đêm (`nightlyPrice`), Giá mỗi giờ. Removed
  Giá ngày, Giá qua đêm, Ngưỡng giá ngày. Saving clears `dailyPrice`,
  `overnightPrice`, `dailyPriceThresholdHours`; an older day price is shown as the night
  price until the room is saved. Short stays need a night or an hour price (one is
  enough). roomRates now takes `ratesMinor {roomPrice, nightlyPrice, hourlyPrice}` only.
- Booking form: "3 giờ × …" (was "3 số giờ"). Removed "Tổng tiền tùy chỉnh" and
  "Lý do tùy chỉnh giá" (the server still accepts them from older apps; an edit now
  prices from the room / per-night / per-hour price).
- Deposit ("Tiền cọc"), replaces "Ghi chú cọc": amount; once there is an amount,
  "Trả bằng" Tiền mặt / Chuyển khoản / Thẻ (cash / bankTransfer / creditCard) and the
  day ("Ngày chuyển khoản" for a transfer, else "Ngày trả cọc"; default today in the
  building's time zone, not after today). It is part of the total: "Kiểm tra tính
  toán" shows Tổng cộng, − Tiền cọc (and − Đã thanh toán on edits), Còn phải trả.
  Saved with the booking in one transaction as a payment (`type: hourlyRent`,
  `descriptionKey: booking_deposit_payment`, `paidAt` = that day at 12:00 property time,
  or now if today) and `booking.depositPayment {amount, paymentMethod, paidOn, paidAt,
  paymentId}`; `paidAmount` goes up, so "Còn phải trả" and checkout collect the rest.
  Needs "Thu tiền" (collectPayments); one deposit per booking (later money: "Thu tiền").
  Older bookings keep their "Đã cọc x / y" line and separate deposit commands.
- Server tests: functions/test/booking_deposit.test.js (6); team.integration.js updated
  for the new room prices (emulator suite). Flutter: booking_form_test (+3),
  room_rates_test (+1), room_creation_test (+1), calendar/property/room tests updated.

## Surcharges, statuses, problems (Tom, 2026-10-04, later)
- Live check of the earlier fixes passed (new room closes its dialog, type optional,
  three room prices, one-click X, deposit by transfer with the remaining amount).
  Small fixes: "Quay lại" left-aligned; "− Tiền cọc" lined up under the total.
- Phụ phí: each line "Theo phòng" (the amount once) or "Theo người" (amount × number
  of guests, once — Tom's choice; not per night). Guests = "Tổng số khách", else main
  guest + co-guests. Server: `surcharges[{label, amountMinor, basis?:'person'}]`,
  quote/save get `numberOfGuests`; stored line `{label, amount (line total), basis,
  unitAmount, count}`; an edit that leaves surcharges out re-prices per-person lines
  with the new guest count. Quote returns `surchargeLines`. calendar.js checks
  unitAmount × count = amount.
- Statuses in words: "Đã đặt cọc – chưa check in" → "Đang ở" → "Đã trả phòng" (booking
  pill; calendar legend; and on calendar bars at least 70 px wide: "Đã cọc", "Đang ở",
  "Đã trả phòng"). Set by the existing buttons (Nhận phòng / Trả phòng).
- Sự cố kỹ thuật: a section in every booking and every lease (open problems of that
  room + "Báo / xem sự cố", which opens that room's problems in a dialog:
  `TechnicalProblemsScreen(onlyRoomId)`, `RoomProblemsSection`). The "Sự cố" menu page
  is gone for everyone who has the calendar; it stays only for housekeeping-only
  roles (no calendar), who otherwise could not report a problem.
- Tests: functions/test/booking_surcharges.test.js (3); Flutter booking_form_test (+2),
  room_calendar_test (+1), role_workspace_test updated.

## Bars, "Đặt phòng", long-stay lease (Tom, 2026-10-04, evening)
- No more "hình thức cho thuê": every room takes short stays and leases. Saving room
  prices writes `rentalMode: 'both'`; the server no longer checks the mode anywhere
  (room_rates, calendar, booking_workspace, tenant_leases, lease_lifecycle,
  tenant_roommates). Rooms list `shortStay: true, monthly: true`.
- Bars: two colours only (ngắn hạn / dài hạn). At the end of the bar: the check-out
  time ("12:00") and a status circle (hollow = not checked in, filled colours for
  đã cọc / đang ở / đã trả). No payment dot, no status word. Lease bars have a thin
  divider at every payment period. Legend: 2 colours + 4 circles.
- "Đặt phòng" button next to "Tạo phòng": a sheet Ngắn hạn / Dài hạn, then the booking
  form or the lease form in a dialog, any room. The Đặt phòng menu page is gone.
- Lease (dài hạn):
  - Tiền cọc is not in any total; shown with "hoàn lại khi hết hợp đồng". When the
    contract end date has passed (`contractEnded`), the tenant page says to settle the
    move-out, which gives the deposit back (existing settlement).
  - Status pill (tenant page and list, `stayStatus` from tenant_contacts): Đã đặt cọc –
    chưa check in (moves in later, deposit > 0) / Chưa check in / Đang ở / Đã check out.
  - Phụ thu (`tenant.surcharges[{id,label,amountMinor,basis:'room'|'person',
    frequency:'period'|'once'}]`): typed in the lease form, edited later on the tenant
    page (`tenantLeases` action `surcharges`, manageLease; ids kept). Billed on the
    period invoice: `surcharges:[{id,amountMinor}]`; per person = main tenant +
    roommates living there in the period. Another amount than the lease's needs
    "Điều chỉnh giá". Billed twice is refused (`period_surcharge_billed`): a once line
    on any live invoice, an every-period line on an overlapping one. Voiding frees it.
  - Tiền điện: "Giá điện mỗi kWh" in the lease form (needs Điều chỉnh giá) sets the
    room meter price from the move-in day (or the last reading, if later). Tenant page
    section: price, last reading, "Ghi chỉ số" (meter number + day + photo; the app
    shows kWh × price before saving; the server subtracts the previous reading),
    "Đổi giá", "Lịch sử" (full readings page). Photos go to Drive folder "Điện nước"
    (utility_readings `addPhoto` / `photo`, max 3 per reading, 2 MB).
  - Sự cố kỹ thuật: the room's problems section on the tenant page.
- Tests: functions/test/lease_surcharges.test.js (6), utility_photos.test.js (2);
  Flutter lease_surcharges_test (4), lease_electricity_test (4), room_calendar_test.
- Live check (local, 2026-10-04 evening): lease from "Đặt phòng" with deposit and two
  phụ thu; tenant page shows "Đang ở", deposit note, phụ thu (edited 100.000 → 120.000),
  electricity price 3.500/kWh and a first reading 1.200 kWh; period invoice 2.000.000 +
  120.000 + 50.000 = 2.170.000; the next period shows "Vệ sinh" greyed "đã thu".
  Fixes after it: the lease form and the tenant page opened over the calendar have no
  back link or second title (the dialog bar has them), and the lease dialog closes once
  the lease is created; clearer electricity labels. Not checked locally: meter photos
  (need Drive) and a priced second reading (needs another day).
- Bars follow the screen (Tom): while the month scrolls sideways, a bar's name, icons,
  end time and status circle stay inside the part of the bar on screen
  (`CalBarTile.scroll` / `viewWidth`, the grid's `_hBody`). The period divider of a
  lease is now the bar's colour, 2.5 px, with a white edge (it read as a grid line);
  it sits at 12:00 of each period's first day (the first one of a lease from 05/10 is
  on 05/11, so October shows none). Test: room_calendar_test "a long bar keeps its
  name and status on screen while scrolling".
- Edge bubbles (Tom): a bar scrolled almost off screen (under 24 px left) shows a small
  bubble next to that sliver, pointing at it, with the name and the status circle;
  tapping it opens the bar. Only for bars cut by the screen edge, not for bars that are
  simply short. `CalEdgeBubble`, `_edgeBubbles`; test "a bar almost off screen shows a
  bubble with its name".
- Infinite scroll (Tom): no cut at the end of a month. Three months are loaded (the
  one before, the one shown, the one after; one `calendarView` call, ≤ 92 days of the
  server's 100); scrolling within 5 days of either end moves the window by a month and
  jumps the scroll by the same days, so what is on screen does not move. The toolbar
  names the month at the left of the screen; ‹ › bring the previous/next month's first
  day to the left; a thicker line where each month starts and "1/11" on its header.
  Day header keys are `calendar-day-YYYY-MM-DD`.
- Edge bubbles show the whole name: up to the screen width minus 40 px, and only a
  longer name is drawn smaller (never "…").
- Day hours, hover card, compact rooms column (Tom): each day header has small hour
  marks 6 · 12 · 18 under the date, with faint lines at those hours across the rows
  (days keep their width). A bar's details show in a small card next to the mouse
  that follows it and flips near screen edges (`CalHoverInfo`; a long press on touch
  screens). The rooms column is narrower (92 px wide screens / 66 px phones), the
  building row lower (28 px), and its settings gear sits right after the name.
- No building row in the grid (Tom): the toolbar already names the one building shown,
  so the grey "Toa A ⚙" row above the rooms is gone; the settings gear (same key
  `calendar-building-pages-<id>`) and the time-zone warning sit right after the
  building's name (or picker) in the toolbar.
- Hour ruler (Tom): under each date a tick for every one of the 24 hours (`_HourRulerPainter`),
  longer ticks with numbers at 6, 12 and 18; the faint lines across the rows stay at
  6, 12 and 18 only (one per hour would grey out the grid). Header 43 px.
- Now line (Tom): a red line at the property's current time across the dates and the
  rooms, with a small triangle in the header. The server sends the property's wall
  clock (`now: "YYYY-MM-DD HH:MM"` in calendarView); the app moves it on by the time
  passed and redraws every minute.
- Month label: when the screen shows the end of one month and the start of the next,
  the toolbar names both ("Tháng 10 – 11, 2026"; across years "Tháng 12, 2026 – Tháng
  1, 2027"; phones "10–11/2026").
- Names never cut (Tom): when a name does not fit in the visible part of its bar (next
  to the status circle), the bar shows only icons and status and the name goes into a
  bubble beside the bar right away (on its right when there is room on screen, else
  its left). The end time gives way first: it is dropped before the name moves out.
  `CalBarTile.nameFits`; test: the 3-hour "Hourly" stay shows its bubble.
- Fix (live check): dragging the date header forward near the end of the loaded months
  threw the view back to September. The window now moves only when no drag or fling is
  moving the dates or the rooms (checked on both scroll controllers; a
  ScrollEndNotification re-checks when the scroll stops), both scrolls jump together,
  and the margin is 7 days. Test: "flinging the dates forward keeps going forward".
- Wide days (Tom): a day is about a fifth of the dates' width on a wide screen and a
  quarter on a phone (never under the old 56/48 px), so a day shows its hours. The
  three loaded months scroll sideways as before. Hour numbers and the faint lines
  follow the width (`calHourMarks`): every 2 h when a day is ≥200 px, every 3 h when
  ≥110 px, else 6 · 12 · 18; the 24 small ticks stay.
- Two views (Tom, like Airbnb): "Ngày | Tháng" in the toolbar (key `calendar-mode`; on
  phones it sits on the building line). "Tháng" (`month_calendar.dart`, `CalMonthView`)
  shows whole months stacked, weeks from Monday, every room of the building: each stay
  is a pill "101 · Name" placed by its times, clipped to the week and month, with the
  status circle where it ends; today's date in a red pill, past days grey. Tapping a
  pill opens the stay like on the timeline; tapping a day opens "Đặt phòng" from that
  date. ‹ › and Hôm nay move by month in this view; scrolling near the top or bottom
  loads the month before or after. Back to "Ngày" shows the month that was on screen.
  Keys: `calendar-month-head-YYYY-MM-01`, `calendar-month-day-YYYY-MM-DD`,
  `calendar-month-bar-<barId>-<monday>`.
- Fix (test): a neighbour's name bubble could cover the bubble of a bar about to leave
  the screen, so tapping it opened the wrong stay. Edge (sliver) bubbles are now drawn
  on top of name bubbles; the test checks the bubble opens its own stay (b1).
- Fix (live, 2026-10-04, Tom): a 3-hour stay's name bubble covered the next guest's
  name in the same room. Tom: every short stay still needs its name, and the bubble
  should move up, down, left or right depending on what it would cover. Now each
  bubble tries the right of its bar, then the left, then above, then below, and takes
  the first place that is on screen and covers no other stay's text: name and icon
  line (`CalBarTile.textZones`.label), end time and status circle (.foot) or another
  bubble. Covering a plain stretch of another bar is allowed. With no such place it
  shrinks beside the bar (down to 56 px, the name scales down); failing that it takes
  the place that covers least. Slivers are placed first, keep their side when nothing
  is free, and are drawn on top. The bubble's tip points at the bar (`pointer`,
  `tipAt`). Test "a name bubble never covers the stay next to it" (fixture
  `sandwich`: "Hourly" between a stay ending 12:00 and one starting 20:00; closer,
  the 18 px minimum bar would overlap it and split the row into two lanes): Hourly's
  bubble goes above it and covers no text of its neighbours.
- Day width (2026-10-04, Tom: "at least it should be able to show a bar for 1 hour";
  he chose 18 px an hour): every day is 432 px on every screen (`calHourW`), so a
  1-hour stay is drawn at its real length, as wide as the shortest bar. About 1.6 days
  show on an 800 px window, 3 on 1440 px, most of a day on a phone; the loaded months
  scroll sideways as before. Hour labels every 2 hours. Opening at today (and Hôm nay)
  puts the current time a quarter of the way into the dates (it was "one day before
  today at the left edge", which would fill the screen with yesterday). `today` is stamped
  at 12:00 (`calStamp` with no time), so the now check compares the date only (test
  caught it: the line opened 12 hours off). Tests: day is
  432 px, the 3-hour stay is 54 px, the now line at a quarter of the view.
- Status once, end in the bubble, lease end (2026-10-04, Tom: "why trang thai show at
  two place and where is end time ... add end date and time for long term"):
  - A name bubble shows the status circle only for a sliver (the bar cannot show its
    own); otherwise the circle stays on the bar alone.
  - The end label the bar has no room for ("12:00") goes in the bubble after the name
    (`calendar-bubble-end`): a short stay's when its end is on screen, a lease's always.
  - A lease's bar always shows its end at the right end of what is on screen: "HĐ
    30/06/2027 12:00" for the contract's planned end, "15/03/2027 12:00" after moving
    out (leases are stamped at 12:00 like the server's calendar). On a soft background
    so a payment line never cuts it. The end label's width is measured
    (`_footWidth(context, w)`), not fixed.
  - The hover card gives a lease's dates with the year and time.
- Stronger colours, one coloured column (2026-10-04, Tom: "more opaque"; "some column
  have different color"): bars are 72 % colour where paid and 30 % where still to pay
  (were 50 % / 13 %; `calPaidAlpha`, `calDueAlpha`), the legend matches, and the soft
  box behind a name or lease end uses the 30 % tint. Month-view pills 45 % (were 28 %).
  Saturdays and Sundays are no longer shaded (header cell and grid); only today's
  column has a colour. Weekend dates keep their coloured label in the header. Month
  view keeps past days grey. Test: Saturday's column has no fill, today's has.
- No today shade, stronger again, no platform (2026-10-04, Tom): today's column is no
  longer shaded either (no column is); today is marked by its date pill and the red
  now line. Bars 85 % paid / 40 % to pay (`calPaidAlpha`, `calDueAlpha`); month pills
  60 %. Every name and end label now sits on the light box (was leases only), and the
  icon line uses full-strength ink, so text stays readable on the strong colour. The
  booking platform (Airbnb, Agoda…) is no longer shown on the calendar: not on bars,
  not in the hover card (it is on the booking page). Test: today's column has no fill.
- Month-view day cells stand out from the page (2026-10-04, Tom): days to come are
  white with an outline and a soft shadow on the #F6F7F4 page; past days keep their
  grey but stronger (#DDE1DD, outlined, flat; was a faint surfaceContainerHighest).
  Dark mode: a lifted surface for days to come, the lowest surface for past days.
  Test: 1 October (past) is #DDE1DD, 3 October is white and raised.
- Before deploy (2026-10-04, Tom):
  - Electricity billing: readings recorded on the lease page are room-meter readings
    (`utilityMeters`); the period invoice offers every reading not billed yet ("usage
    behind"). The local data had no electricity line because those readings were
    already on earlier invoices, and nothing said so. Now the lease page tags each
    priced reading "Đã lập hóa đơn" / "Chưa lập hóa đơn", and the period invoice says
    why there is no electricity line (`period-no-electricity`): already invoiced up to
    a date, only a starting point / no price, or no reading yet. Server: periodPreview
    returns `lastElectricity` {date, status: invoiced|unbilled|noCharge} (optional).
    Tests: period_invoice.test.js, period_invoice_form_test, lease_electricity_test.
  - "→" is not in Roboto (the app font) and showed as a box: menu paths now use "›"
    ("Cài đặt › Google Drive"), date ranges "–", amounts "=" (service-fee lines). The
    Excel export keeps "→" (Excel uses system fonts). Other symbols checked: only
    emoji (debug logs, old v1 room screen) are outside Roboto.
  - The now line is drawn under the bars: full red in empty cells, faint through a
    bar, never through a name or end label. Test: the line comes before the bars.
- Fix (live, 2026-10-04): the hover card showed a box between the two times: the web
  font has no "→". The day and month hover cards now use "–", like the booking page.
- Month view names (Tom: "the name is the most important"): the name sits in the pill,
  made up to a quarter smaller to fit (live check: a one-day piece cut "Khach Da…").
  A pill too narrow even then shows only its status circle, and the name goes in a
  tag right after it (before it when the week ends; made smaller, never cut). The tag
  opens the stay and shows the same hover card. Lanes keep room for tags, so a tag never
  covers another stay. Key `calendar-month-tag-<barId>-<monday>`.
- Month view, name once (Tom): "101 · Name" shows on the piece where the stay starts;
  as soon as that piece starts to go under the top edge, on the stay's next piece that
  is whole on screen (it moves while scrolling; a partly shown piece keeps it only
  when no later piece is whole). The other pieces show only the colour, and the status circle
  where the stay ends. (`_labelsAt`, keyed by stay, month and week.)
- Month view status (Tom): the status circle sits right after "101 · Name" (in the pill
  or its tag), not at the stay's end, so an open-ended lease shows it too. Pieces
  without the name show only the colour. Key `calendar-month-status-<barId>-<monday>`.
- Month view label (Tom): the toolbar names the month 40 % of the way down the screen
  (the one filling most of it), not the month whose last strip is still at the top.

## Long-stay lease form, round 2 (Tom, 2026-10-04 evening)

- Contract end date is required (form and server `tenant_leases` create: a valid
  date after the move-in day). Label no longer says "không bắt buộc".
- "Ngày thu khác ngày dọn vào" switch: off = due on the move-in day (shown as "Thu vào
  ngày N hằng tháng"), on = the day field (required, 1–31).
- "Số tiền mỗi kỳ khác" switch: off = rent × months (shown), on = the amount field,
  prefilled with rent × months.
- Section "Điện và nước": electricity price (people who may change prices), the meter
  reading at move-in with a photo (only when moving in today or earlier; later move-ins
  get a note), and water per person per month.
  - The reading is saved right after the lease (utilityReadings read → record on the
    move-in day → addPhoto). If it fails the lease stays saved and the form says why
    (no electricity price / a later reading exists / other) and to add it on the tenant
    page. A photo without a reading is refused in the form.
  - Monthly readings with photos stay on the tenant page (Tiền điện → Ghi chỉ số).
- Water (tiền nước): a lease surcharge line with `kind: 'water'`, per person,
  `frequency: 'month'` (new): a period invoice charges price × people × months of the
  invoice (part months by days, like rent). At most one water line. The tenant page
  has its own "Tiền nước" section (Edit; empty = stop charging); the Phụ thu list and
  its editor leave the water line out and send it back unchanged. Invoice line reads
  "Tiền nước (2 người × 3 tháng)". Tests: functions/test/lease_surcharges.test.js
  (water + end date), test/lease_water_test.dart, test/lease_details_test.dart.

## Lease page buttons (Tom, 2026-10-04 evening)

The six buttons at the end of the lease page (each a separate page) are gone. Now:
- Hợp đồng section: "Sửa" next to the end date (dialog: date + reason, leaseLifecycle
  `terms`); "Đổi" next to "Tiền thuê hằng tháng" (dialog: from which day, after today
  + new rent + reason, tenantRent `schedule`); the rent changes listed under it
  ("Từ 2026-10-01 · 2.000.000 VND · đã lên lịch / đang áp dụng / trước đây"), a planned
  one with ✕ (dialog: reason, tenantRent `cancel`). Only with the "Đổi giá" right;
  others see the rent only. "…" menu: "Chuyển phòng" (dialog: room, date it happened,
  reason; leaseLifecycle `move`). File: lib/screens/team/lease_actions.dart.
- "Người ở cùng" section: the people living with the tenant (server tenantContacts
  `read` now returns `roommates`), tap to open their page; "Thêm" opens the roommate
  form in a dialog that closes after saving.
- At the end only "Lập hóa đơn kỳ" and "Trả phòng" (move-out + final bill; "Quyết toán"
  when already moved out). Recording a move-out without settling is no longer offered
  for the main tenant (Trả phòng can settle later).
- A roommate's page: "Chuyển phòng" and "Trả phòng" (dialogs, leaseLifecycle `move` /
  `moveOut`).
- The old pages (LeaseLifecycleScreen, TenantRentScreen, TenantRentHistory) are no
  longer opened from the app; files kept (not deleted). The audit list of rent edits
  (who changed what) stays in Activity.
- Tests: test/lease_page_test.dart (new), tenant_rent_test, tenant_rent_history_test,
  tenant_roommate_test updated; server lease_surcharges.test.js checks `roommates`.
- Follow-ups (Tom, same evening): the roommate form asks CCCD and tạm trú
  (server tenant_roommates `create` takes optional nationalId / residenceRegistered /
  residenceDate; test functions/test/tenant_roommate_papers.test.js) and has no
  "Tải lại lượt thuê chính" next to save (reload only after a failed load / a change by
  someone else). "Số tiền mỗi kỳ" moved into the rent rows and follows rent changes: a
  special amount typed with the lease shows "· đến <first planned change>" and stops
  once a change is in effect (then rent × months, like the period invoice); planned
  changes show their amount per period when a period is more than one month. The
  contact section shows "Tải lại liên hệ" only after "changed by someone else".
- Water per person or for the whole room (Tom): "Mỗi người" / "Cả phòng" chips under
  the water price in the lease form and in the tenant page's water dialog. Whole room =
  the line's basis 'room': price × months of the period, whoever lives there. Tests:
  lease_surcharges.test.js (450,000 for 3 months at 150,000), lease_water_test.dart.
- Short-stay booking page buttons (Tom): the row at the end is gone. "Sửa" on the
  booking card (key booking-edit); "Thu cọc" / "Thu tiền" in the Tiền section's header
  (booking-collect-deposit / booking-collect); "Xác nhận đặt phòng" moved into "…" with
  cancel / no-show / refunds; at the end only "…" and the next step (Nhận phòng /
  Trả phòng). Test: booking_form_test "one button at the end".
- Month view, paid part (2026-10-05, Tom): pills fill like the day view's bars — solid
  (85 %) from the pill's left end to where the stay is paid (paidUntil; a booking
  paid in full is all solid), lighter (40 %) after. Per week piece, so a lease paid to
  15/10 is 3/7 solid in that week. The name sits on a light box. Weeks without the
  name show just the room number (Tom's "name once" rule from 2026-10-04 is kept).
  Keys calendar-month-fill-<bar>-<monday>, calendar-month-room-<bar>-<monday>.
- New booking, per night or per hour (2026-10-05, Tom): a room with only one kind of
  price uses it; otherwise the dates decide — crosses a night (14:00 → next day
  12:00) = per night, same day = per hour, not filled in yet = per night. It follows
  the dates until staff tap a chip or type a price. Test: booking_form_test "picks
  per night or per hour from its dates".
- Room area (2026-10-05): label "Diện tích (m², bắt buộc)"; error says "100,000 m²";
  typed area uses the quantity rule (dot for decimals, comma only for thousands:
  "25,5" is refused, not read as 25.5). appParseQuantity in app_number.dart.
- Day bars, one line (2026-10-05, Tom): name, then the problem icon and "+N" on one
  line in the middle of the bar (no second icon line); no phone icon (also gone from
  the legend); corners 12 px (calBarRadius) like the month pills; text starts 8 px in.
- Day view, thin rows (2026-10-05, Tom): rows 30 px (× text size up to 1.3), bars
  24 px with 3 px above and below. Overlapping stays keep the full bar height; the
  row grows by a lane (24 + 2 px) for each extra one. The room column is as wide as
  the longest room name needs (44–110 px wide screens, 44–80 px phones; names over 8
  characters on two smaller lines). Days before today are grey (#DDE1DD; dark mode
  surfaceContainerLowest) like the month view; today and later stay white.
- Labels (2026-10-05, later, Tom): month view names a stay on EVERY week's piece
  ("101 · Name" + status; a too-narrow piece gets its tag) — the "name once / moves
  while scrolling" rule and the room-number-only pieces are gone. No light box behind
  names or end labels in either view: the paid fill shows through.
- 2026-10-05 (Tom), evening:
  - Room dialog (tap a room): no card with five buttons; the room's pages are right in
    the dialog under chips — Thông tin · Cài đặt · Điện nước · Phí dịch vụ · Giá thuê
    (chip keys edit-room-<room>, settings-room-…, utilities-room-…, fees-room-…, rates-room-…), details first, no back links (PageTabScope). The room list
    in the workspace keeps its card + buttons; its area line now reads "Diện tích:
    30 m²" (it showed the form label "Diện tích (m², bắt buộc)").
  - "Báo sự cố" next to "Đặt phòng" (key calendar-report-problem): the report form
    for any room of the building (TechnicalProblemsScreen startReport).
  - Hover card: not shown when the bar is clicked (it appeared 350 ms later on top of
    the opened dialog and stayed), nor over a route opened since.
- 2026-10-05 (Tom), late:
  - Toolbar buttons are icons with the name in a tooltip: Tạo tòa nhà
    (add_business), Tạo phòng (meeting_room, new icon), Sự cố (every room's problems;
    "Báo sự cố" is on that page; key calendar-problems), Dọn phòng (housekeeping
    tasks in a dialog; key calendar-cleaning), Đặt phòng (filled). The "Buồng phòng"
    section (renamed "Dọn phòng") now only shows for people without the calendar.
  - Room dialog: "Cài đặt" merged into "Thông tin" (room details, then booking
    settings, one scroll; StackedPageScope). "Phí dịch vụ" has "Phí tòa nhà"
    (key room-fees-building) → closes the room dialog and opens the building's
    pages on "Phí dịch vụ".
  - Building chips: Thông tin · Hợp đồng thuê · Mặc định tòa nhà · Phí dịch vụ.
  - Buttons straight in a form column (full width, touching the next one) are now
    in WsActions rows (right-aligned, 8 px apart) on 19 team screens; the layout
    page shows "Tải lại" in a dialog only after loading failed.
- Cleaning on the calendar (2026-10-05, Tom chose: planned + actual, auto "needs
  cleaning" after check-out, cleaners get the calendar with cleaning only):
  - Server: housekeeping tasks take an optional planned window (plannedStart /
    plannedEnd, property wall clock "YYYY-MM-DD HH:MM", both or neither, end after
    start, else task_invalid_time) and record startedAt when started. calendarView
    adds cleaning bars (type/kind 'cleaning', id cleaning:<task>): start = earliest of
    plan/actual start, end = latest of plan end / done / now while in progress, no
    plan and no times → created + 1 h; solid part (paidUntil) = done time, or now
    while in progress. Managers and reception see every cleaning; a cleaner only
    their own. rooms[].needsCleaning = a check-out (checkedOutAt, else end) or lease
    move-out after the room's last completed cleaning. A member with only
    readAssignedTasks now gets the property with cleaningOnly: true (no stays).
    Properties also say canAssignCleaning / canReadCleaning. Tests:
    functions/test/calendar_view.test.js (cleaning, cleaner view),
    functions/test/housekeeping.test.js.
  - App: purple bars "Dọn phòng · <cleaner>", hover card with what / planned /
    worked / state; broom icon on rooms that need cleaning (+ legend); tapping a
    cleaning opens the Dọn phòng list; a day's menu has "Giao dọn phòng" (room and
    12:00–14:00 filled in). The assign form has planned start/end; tasks list shows
    the plan. Cleaners use the calendar; the Dọn phòng and Sự cố sections are gone.
  - Live check fixes (2026-10-05): the cleaner's name on the bar comes from their
    staff profile, else their membership name/email (tasks are assigned to an
    account, so staff profiles keyed by staff ID never matched). The tasks list
    gets startedLocal / completedLocal (property time zone) and shows
    "Thực tế: … – …". Labels: heading "Dọn phòng", buttons Giao việc / Bắt đầu / Xong.
  - Tom (2026-10-05, later): a cleaning has its own states, not a stay's —
    bar status = the task status (assigned / inProgress / completed); the circle
    and hover say Chưa bắt đầu (hollow purple) / Đang dọn (blue) / Đã xong
    (teal), with their own legend group "Trạng thái dọn phòng". A finished
    cleaning's bar shrinks to the real work time (Bắt đầu → Xong); marked done
    without Bắt đầu: from the planned start if earlier, else 30 min before done.
    The plan stays in the hover. Every "buồng phòng" text is now "dọn phòng"
    (role name Dọn phòng). Form fields got gaps (Dọn phòng, Sự cố, rename fee);
    checked the whole app with a scan for fields that touch.
# Property selector and compact actions (2026-10-06)

Tom requested a wider one-line property selector and dropdown without ellipsis,
a three-dot menu for the five calendar actions when the screen is too narrow,
and a larger property settings gear. The selector measures the longest property
name with the actual title style instead of using the old fixed 240px width.
The gear is 28px. Compact actions retain the existing permission conditions and
callbacks, including new property, new room, problems, cleaning and new stay.
On phones narrower than the full name, the selector row can scroll sideways;
the actions menu stays visible. Landscape retains the scrolling toolbar.

Situations to verify: one/multiple properties; long EN/VI names; owner versus
restricted staff; absent properties; missing time zone; loading/error; five or
fewer permitted actions; selector/menu selection and disabled loading actions;
embedded/standalone calendar; populated empty/occupied rooms, hourly/long stays,
overlaps; phone/landscape/desktop at 100/130/200% text and relevant themes.
The ellipsis regression failed before the fix. Targeted calendar tests passed
27/27 before adding compact-menu coverage. Actual-font desktop and narrow
Vietnamese screenshots were inspected. Full-suite and staging evidence follows
after completion; untested combinations must not be inferred from these renders.

Final evidence: full Flutter run passed 621 tests with one obsolete navigation
helper failure. The helper now opens the compact menu; all 34 calendar and
property-creation tests passed on rerun. The compact-menu test checks five
authorized entries and a reachable menu; the existing populated matrix covers
EN/VI, narrow phones, landscape, desktop and 100/130/200% text. Analysis reports
no errors (422 warning/info items). Desktop and narrow Vietnamese actual-font
renders were inspected. Every possible permission/theme/content combination was
not visually reviewed; provider/server logic was unchanged.

Staging hosting updated and live-checked: the exact Utility verification long
name fits on one line in selector and dropdown, gear is larger, the compact menu
shows all five actions, and create-building opens its existing form. No record was
created during this check. Screenshot: `.dart_tool/calendar-layout/staging-toolbar.jpg`.
