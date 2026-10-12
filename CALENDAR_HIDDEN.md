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
| 5 | **Building settings ⚙**: Thông tin, Hợp đồng thuê, Mặc định tòa nhà, Phí dịch vụ | **No** | Editing the building, its lease template, its defaults (layout) and its service fees. |
| 6 | **Tạo phòng** (new room) | **No** | Adding rooms. Tapping a room name opens only that room. |
| 7 | **Sự cố** (all problems of the building) | Partly | Tapping a day → "Báo sự cố" still reports one; the building's problem list is gone. |
| 8 | **Dọn phòng** (cleaning tasks) | Partly | Tapping a day → assign cleaning still works; the list of cleaning tasks is gone. |
| 9 | **Đặt phòng** (new stay) | Yes | Tapping a day in a room's row still offers a short or long stay. |
| 10 | Missing time zone warning ⚠ next to the building | Partly | Tapping a day says the time zone is missing, but nothing warns beforehand. |
| 11 | Phone menus (⋯ actions, legend and reload) | No | Same items as above. |

**Most urgent:** 5 (building settings) and 6 (new room), since they cannot be
reached at all, then 1 (Today) and 7–8 (problem and cleaning lists).

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
- "Thêm cơ sở mới" in the property menu opens the same form as "Tạo tòa nhà".
