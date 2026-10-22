# Calendar: what the client's design hides

Since 2026-10-11 the calendar matches the client's picture: the page title,
the month with its arrows, and the property box ("CƠ SỞ") with its menu.
Everything below is hidden but its code is kept. `RoomCalendar(showTools: true)`
shows the old tools row again (the tests keep it on through
`test/flutter_test_config.dart`). Each item needs a place in the new UI.

## Hidden controls

| # | Control | Still reachable? | What is lost |
|---|---------|------------------|--------------|
| 1 | **Hôm nay** (Today) | No | A way back to today after scrolling. The page still opens on today. |
| 2 | **Ngày / Tháng** switch | No | The whole month view (Airbnb-style weeks). |
| 3 | **Chú thích** (legend ⓘ) | No | The meaning of the bar colours and status circles. |
| 4 | **Tải lại** (refresh ⟳) | Partly | The calendar still reloads after every save and when opened; there is no manual reload. |
| 6 | **Tạo phòng** (new room) | **No** | Adding rooms. Tapping a room name opens only that room. |
| 7 | **Sự cố / Báo sự cố** | Partly | 2026-10-12: removed from the empty-cell rental chooser at Tom's request. Needs a new navigation location later; existing room problem details remain. |
| 8 | **Dọn phòng / Giao dọn phòng** | Partly | 2026-10-12: removed from the empty-cell rental chooser at Tom's request. Needs a new navigation location later; existing cleaning bars still open their task list. |
| 9 | **Đặt phòng** (new stay) | Yes | Tapping a day in a room's row still offers a short or long stay. |
| 10 | Missing time zone warning ⚠ next to the building | Partly | Tapping a day says the time zone is missing, but nothing warns beforehand. |
| 11 | Phone menus (⋯ actions, legend and reload) | No | Same items as above. |

**Most urgent:** 6 (new room), then 1 (Today) and 7–8 (problem and cleaning lists).

Building settings restored 2026-10-13: the selected property appears above the
scrolling alternatives with an edit icon. It opens Details, Lease, Building
defaults and Service fees according to the existing permissions.

## Looks that changed (earlier choices the picture replaces)

- Past days are no longer grey.
- No lines between rooms inside the grid (the room column keeps them).
- No thicker line where a month starts; every date names its month and year ("T5 - 8/10/2026").
- The small hour ruler (6 · 12 · 18) became the labels 00 02 … 22; today's date pill and the red triangle became the red hour label.
- Weekend dates are no longer coloured.
- Rows are 48 px (were 30 px); bars are 32 px (were 24 px).

## Navigation (not in the picture)

- The app's top bar (organization, role, account) and the bottom tabs (Lịch,
  Người thuê, Thu chi, Nhân sự) are kept as they are. Ask the client whether
  computers should get a side menu instead.
- The picture says **"Cơ sở"**; the rest of the app says **"Tòa nhà"** (for
  example the empty calendar's "Tạo tòa nhà" and the building forms). Choose
  one word.
- The tooltip-only + beside "Chọn cơ sở" opens the same form as "Tạo tòa nhà".
- Empty calendar cells open a centered rental-choice dialog with a close icon,
  no cancel footer; selected room/date/time pass into the authorized rental form.
