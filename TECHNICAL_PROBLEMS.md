# B7 technical problems (sự cố kỹ thuật)

Roadmap: CLIENT_ROADMAP.md B7. Split: **B7a** problems (this file, DONE on staging,
accepted by Tom 2026-10-03) and **B7b** photos saved in the owner's Google Drive.

## Decisions (Tom, 2026-10-03)
- Cost: saved on the problem; when marking fixed, a tick can also record it as a
  paid building expense in Thu chi (invoice kind `repair`, direction expense).
- "Room unavailable while open": blocks new short-term bookings AND new leases
  (and lease moves into the room). Existing bookings/leases are kept and listed
  as a warning, never cancelled.
- Who: anyone working on the property reports (manageProperty, createBookings,
  manageBookings, manageLease or updateAssignedTasks); reading also for
  readBookings / readAssignedTasks. Blocking, editing, marking fixed and reopening
  need manageProperty. Recording the expense also needs collectPayments.
- Photos: Google Drive directly (B7b), not Firebase Storage.

## How it works (B7a)
- Server: `functions/technical_problems.js`, callable `technicalProblems`,
  actions list / report / update / fix / reopen. Problems in
  `technicalProblems/{id}` (+ `problemHistory`), retries in `problemOperations`,
  teamActivity `problem_*`. Server-only collections (no client rules).
- Block: problem id kept in `rooms/{id}.openProblemBlocks`; written with
  bookingRevision+1 so a booking racing the block serializes on the room.
  Checked in calendar.js (new/moved booking, new lease via calendar),
  tenant_leases.js (prepare + create; rooms list returns `blocked`),
  lease_lifecycle.js (move). Error key `room_has_open_problem`.
- Report remembers who lived there then (lease or checked-in booking).
- Fix: who fixed (free text, person or company), date (report date..today),
  cost optional, optional expense (cash / bank + account), note. Unblocks.
- Reopen needs a reason; blocks again if it was blocking; a recorded expense
  stays in Thu chi.
- App: section "Sự cố" (`lib/screens/team/technical_problems_screen.dart`):
  list (Đang mở / Đã sửa / Tất cả), report, details, edit, mark fixed, reopen.
  Booking form, lease form (room greyed + note) and room move explain the block.
  Invoice list shows the expense as "Chi · Sửa chữa: <title> (<room>)".

## Tests
- functions/test/technical_problems.test.js (4): roles, block + booking refused
  + room move refused + unblock + reopen + lift, fix with expense / retry /
  refusals, input checks. calendar, lease and settlement suites still pass.
- test/technical_problems_screen_test.dart: report with block + warnings, fix
  with bank expense + refusal + exact retry, non-manager view, reopen,
  18 layout combinations.
- team.integration.js needs the Firestore emulator (npm run test:team:emulator).

## Local check (emulators, 2026-10-03 ~15:15 PT)
1. "Sự cố" appears under Thêm; empty list says "Không có sự cố đang mở".
2. Report in room 101 (has a lease) with "Tạm ngừng cho thuê": saved; warning lists
   "Hợp đồng Pham Van Thue: 2026-10-04" (kept, not cancelled).
3. Report in empty room 102 with the block: the new-lease form greys out 101 and 102
   with "Phòng đang có sự cố kỹ thuật chưa sửa, chưa nhận hợp đồng mới: 102, 101".
4. 102 marked fixed by "Tho dien Hung", 350.000 by bank to "TK test", recorded in Thu
   chi: list shows "Chi · Sửa chữa: Mat dien o cam (102)", 350.000, paid. The lease form
   then offers 102 again; 101 stays blocked.
Fixed after the check: the expense card had an empty title -> now shows who was paid;
a repair expense can no longer be edited or voided from Thu chi (fees/due date make no
sense for it); paying/reversing still works. Flutter 61 tests passed; integration 87/89
(1 outdated key list fixed, 1 timing-sensitive rate-limit test to re-run).

Staging check 2026-10-03 (Test v2, Toa A): report in 101 with the block showed the
lease warning "Hợp đồng Le Van Chinh: 2026-10-02"; marked fixed with no cost; moved to
"Đã sửa". Test record "Kiem tra staging: den phong tam hong" left in the fixed list.

## B7b photos in Google Drive (built 2026-10-03, local check next)
How it works:
- Settings → Google Drive (connectDrive only): Connect opens Google's pop-up
  (GIS code flow, scopes openid email drive.file, redirect "postmessage"); the
  callable `googleDrive` (status/connect/disconnect) swaps the code for a refresh
  token kept in `driveConnections/{orgId}` (server-only). Refused: Drive box not
  ticked (drive_scope_missing), no long-lived token (drive_no_offline_access: remove
  CanHo360 at myaccount.google.com/permissions, connect again). Disconnect revokes
  the token; files stay in Drive. Google refusing the token later marks
  "needsReconnect" (shown on Settings and on each problem).
- Photos (technicalProblems addPhoto/photo/removePhoto): JPG/PNG/WebP, max 2 MB
  (the app shrinks to 1600 px first), max 6 per problem. Folder "CanHo360 /
  <property> / Sự cố", recreated if deleted. Staff who can report add photos while
  the problem is open; managers any time; removing: manager, or whoever added it
  while open. Removing takes it off the problem, then moves the file to Drive's
  trash (never deleted for good). A lost reply is retried with the same operation
  id: no double upload. Viewing goes through the server (the files are private to
  the owner's Drive).
- Local emulator: functions use a stand-in Drive kept in the emulator's Firestore
  (`localFakeDrive`), and Connect skips the pop-up. Only the real pop-up and Google
  APIs need staging.
- Tests: functions/test/drive.test.js (6), test/problem_photos_test.dart.

Google Cloud setup DONE by Tom 2026-10-03 (staging): Drive API + Secret Manager API
enabled; consent screen "CanHo360 (staging)" stays In production (shared with Google
sign-in; Testing would block non-test accounts), scope drive.file only; web client
"CanHo360 staging Drive" (JS origins web.app + firebaseapp.com, no redirect URI, popup
code flow), client ID in functions/drive.js CLIENT_IDS (the app gets it from the
server); client secret
in Secret Manager `drive-oauth-client-secret`, readable only by app-functions-runtime
(Secret Accessor on that secret). Staging deploy refuses secret bindings, so the server
reads it through the Secret Manager API at run time. Before production: a real privacy
policy page (branding currently points at the home page) and the same setup there.
- The owner connects their Google account once (permission `connectDrive`, already
  in the role list). Scope `drive.file` (the app only sees files it created).
- Server keeps the refresh token in a server-only document; staff upload through
  the server (photo resized in the app first), server saves into
  "CanHo360/<organization>/Sự cố/" in the owner's Drive and shows thumbnails to
  staff through the server (staff need no Drive access).
- Needs from Tom (Google Cloud console, cannot be done by the assistant):
  OAuth consent screen + Web OAuth client for staging (and later production);
  client id/secret stored as Functions secrets. Steps will be written when B7b
  starts. Locally a fake Drive is used so the flow can be tested without Google.

## Not covered yet
- Photos (B7b). Problem on the calendar bar (C1) and push notification (N1).
- Charging the tenant for damage from here (settlement "Hư hỏng" line covers it).

## Drive connected on staging (2026-10-05)
- First connect failed: "token 401 invalid_client: The provided client secret is
  invalid" — the value in Secret Manager did not match the web client. Tom added a
  new client secret on "CanHo360 staging Drive" and a new version of
  `drive-oauth-client-secret`; after ~15 min (instances recycled) the connect worked:
  Đã kết nối, trinhhungqt2004@gmail.com. Old client secret can be disabled.
- The server now sends a setup failure's short reason in the error details (`why`)
  and the Drive page shows it in brackets; the app says "(app: no client id)" when
  the server sent none. Function logs were not readable with Tom's CLI login.
- The pane (and browsers) only open Google's pop-up from a real user click.
- Photos on the report form (2026-10-05, Tom): "Thêm ảnh" while reporting (Drive
  connected only); kept on the device, removable, up to 6; uploaded right after the
  problem is saved, on the "Đã lưu" page (Xong / Xem sự cố wait for the upload).
  Test: problem_photos_test "photos chosen while reporting".
