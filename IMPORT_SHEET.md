# Sheet import (anh Hưng's old app → CanHo360) — design

Decided with Tom 2026-10-05. Structure only: this file holds NO customer data.
The real file is anh Hưng's and confidential: never copy it, or anything from
it, into staging, the repository, docs or tests. Staging is tested with a
made-up file in the same format (tool/import_sample.xlsx, generated).

## Source file (export of his old app, one .xlsx)
| Tab | Columns | Notes |
|---|---|---|
| Phòng | ID, Tên cơ sở, Giá thuê cơ sở, Mã phòng Json, Ghi chú | one row per building; rooms JSON list of {maPhong, trangThai, ghiChu}; Giá thuê cơ sở = rent the business pays for the building |
| Đặt phòng | ID, Tên cơ sở, Mã phòng, Ngày tạo, Tên khách hàng, Số điện thoại, Nguồn, Nhân viên, Hình thức phòng, Ngày giờ checkin, Ngày giờ checkout, Đơn giá, Phụ phí, Tổng doanh thu, Ghi chú, Thanh toán Json, Số tiền còn lại, Dọn phòng Json | Tổng = Đơn giá + Phụ phí always (Đơn giá is the whole stay / package price); payments JSON list of {ngayThanhToan YYYY-MM-DD, soTien int, ghiChu} — "cọc" in the note = deposit; dates are real datetimes (local time) |
| Nhân viên | ID, Tên nhân viên, Tên đăng nhập, Mật khẩu, Quyền, Quản lý cơ sở, Màu, Tỷ lệ hoa hồng, Hoa hồng | PASSWORDS IN PLAIN TEXT: never read that column |
| Chi phí | ID, Ngày chi, Cơ sở, Nhóm chi phí, Nội dung chi, Số tiền, Ghi chú | |
| Cài đặt | Key, Value (JSON), Ghi chú | sources, room_methods (packages), expense_categories, room_status |
| Dọn phòng | free layout | skipped |

## Decisions (Tom, 2026-10-05)
- Upload the .xlsx in the app (owner only); the app reads it, shows a preview
  (counts, problems) and creates nothing until confirmed.
- Stays "Thuê dài hạn", and unlabelled stays over 20 days → LEASES: tenant +
  lease in the room from check-in to check-out, monthly rent = Đơn giá ÷ months
  (rounded), their payments become rent payments. Everything else → short-stay
  bookings: total = Tổng doanh thu, surcharge = Phụ phí, the package name kept
  (Hình thức phòng) in the notes; status from the dates (past = checked out,
  now = checked in, future = confirmed); payments with "cọc" = deposit.
- Overlapping stays in one room: imported, then listed for review.
- Staff: profiles with name, role (Admin → Quản trị, Quản lý → Quản lý,
  Nhà đầu tư → Nhà đầu tư, Nhân viên → Nhân viên) and commission %, waiting
  for an email invitation. No accounts, no passwords.
- Phones: "ko có", "xxx", "k" and similar → empty; numbers that lost their
  leading 0 (9 digits) get it back.
- Building rent (Giá thuê cơ sở) → whole-building contract "thuê vào" with that
  monthly amount (start date / due day to be filled in by the owner).
- Expenses → Thu chi expenses with their category.
- After the import: a new Google Sheet in our format in the owner's connected
  Drive (CanHo360 folder); later kept up to date (D1 backup).
- Re-running the same file must not create duplicates (each source row keeps
  its old ID as the import key).
- Real import only in production, after publishing.

## Built (2026-10-05)
- App: Cài đặt → "Nhập từ file" (owner / co-owner only),
  lib/screens/team/sheet_import_screen.dart. The file is read on the device
  (lib/services/sheet_import_files.dart, package excel); only the columns
  listed in `oldAppColumns` are sent — never "Mật khẩu", never the unnamed
  change-log column. Screen: choose file → preview (counts, "đã có" on a
  second run, problems by kind, overlapping stays) → Nhập → confirm → result →
  "Lưu Google Sheet" (the app builds the .xlsx with syncfusion xlsio; the
  server uploads it to Drive / CanHo360 converted to a Google Sheet) → "Mở Sheet".
- Server: callable `importSheet` (functions/sheet_import.js; costly bucket,
  8 MB request limit): preview | apply | saveSheet. Refuses a password
  column, unknown tabs/columns, objects in cells; owner only.
- IDs: imp_<kind>_<sha256(org, kind, old ID…)> → a second run creates
  nothing and never overwrites (existing docs are only counted).
- Shapes written = what the app's own screens write: buildings (timeZone
  Asia/Ho_Chi_Minh, VND, address '', importedRentInMinor), rooms (area 0,
  rentalMode both), staffProfiles (code S01…, importedRole,
  commissionPercent, accountId null), bookings (status from dates, totalPrice
  = Tổng, surcharges [Phụ phí], depositPayment = first "cọc" payment,
  payments type hourlyRent method 'other'), tenants (leases: monthly rent =
  Đơn giá ÷ round(days/30), deposit = "cọc" payments, ended → moveOut), rent
  payments (invoiceVersion 2, tenantRent, paid), expenses (invoiceVersion 2,
  invoiceKind 'expense', direction expense, paid; Thu chi shows
  "Nhóm: Nội dung"). Every record has importSource {kind:'oldAppSheet', sourceId, runId}.
- Price type: Thuê giờ → hourly, Qua đêm → overnight, xNyD / Combo → nightly,
  else by length. Source: Booking/Agoda… → online+platform, Chính chủ → walkIn,
  ads → online/other, others → other; the original word is kept in the notes
  ("Nguồn: …", "Gói: …"). 0 đ payment lines are skipped.
- Property contract screen: no contract yet + importedRentInMinor → starts as
  "thuê vào" with that amount (landlord, dates, due day by the owner).
- Problems listed (kept, not blocking): room_added, building_added,
  long_term_no_lease, overpaid, staff_unknown, no_name, bad_payment;
  skipped rows: bad_dates, bad_amount, stay_no_room, duplicate_id,
  expense_no_building.
- Tests: functions/test/sheet_import.test.js, test/sheet_import_files_test.dart,
  test/sheet_import_screen_test.dart. Sample: tool/import_sample.xlsx from
  tool/make_import_sample.py (made-up; dates relative to the day it is made).
- Not done yet: keeping the Google Sheet up to date (D1 backup).
