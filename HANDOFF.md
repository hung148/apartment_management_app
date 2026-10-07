# Handoff — how to continue this project (for any AI assistant or developer)

Everything learned while building G8, U1 and B1–B3 (2026-09-30 → 2026-10-01),
so a new chat — with any AI assistant — or a developer can continue without
relearning it. "The assistant" below means whichever AI is helping Tom. Read this together with
[AGENTS.md](AGENTS.md) (rules), [CLIENT_ROADMAP.md](CLIENT_ROADMAP.md) (what to
build next, decisions, design notes) and [tool/STAGING.md](tool/STAGING.md).

## What to do next (read this first)

Calendar tooltip/spacing follow-up: compact options tooltip now names both
“Chú thích và tải lại” / “Legend and refresh”. When the toggle moves below date
navigation, an explicit 6px row gap matches the gap above navigation. Calendar
suite 28/28 passed; narrow Vietnamese render inspected; staging web build passed.

Toolbar spacing refinement: reduced name-to-arrow allowance by 24px; compact
calendar options are now aligned directly below the actions menu on the right
edge, including when date controls need two rows. Calendar suite 28/28 passed
after this alignment refinement; staging release web build passed.
date navigation, Ngày/Tháng and calendar options share a wrapping row instead
of reserving a whole row for the toggle. Calendar options now use `Icons.tune`,
while the five-action menu keeps three dots. Targeted populated calendar suite
28/28 passed; inspected 200% Vietnamese phone render; staging web build passed.

2026-10-06 toolbar follow-up: widened the one-line calendar property selector and
dropdown based on the longest name; removed ellipsis, enlarged settings gear to
28px, and put the five permitted actions in a three-dot menu when space is tight.
Staging hosting updated and live-checked with “Utility verification — Tòa nhà
kiểm tra điện nước”: full selector/dropdown name, larger gear, all five menu
entries, and create-building form opens without writing data. Extremely narrow
phones use horizontal scrolling for names wider than the viewport. Full Flutter
run: 621 pass / one obsolete navigation helper failure; after updating that
helper, all 34 calendar/property-creation tests passed. Analysis: zero errors.
Actual-font populated EN/VI phone/landscape/desktop renders inspected; see latest
CALENDAR.md section for scenarios and gaps. No backend or production deployment.

### >>> PICK UP HERE (2026-10-06: single organization accounts) <<<

Tom approved one account / one organization, no staff organization creation,
additional workplaces, co-ownership or joint governance. Implemented and on
staging: direct authorized workspace entry, transactional account binding checks,
owner-only organization lifecycle, and a separate consented ownership handover.
The detailed situations, rollout plan and limits are in
[SINGLE_ORGANIZATION_PLAN.md](SINGLE_ORGANIZATION_PLAN.md), sections 10, 13 and 14.

Existing multi-owner accounts get a merge dialog with a unified name. Checked
organizations merge; unchecked organizations close for deletion after 30 days.
Deletion needs its own explicit confirmation and at least one organization must
remain selected. Source organization metadata stays archived; operation IDs make
lost-response retries safe. Mixed data versions, legacy organizations with staff,
ambiguous ownership/access, several Drive connections or oversized transactions
require migration review before any write. No production deploy or data change
was performed. Production's four existing multi-organization groups remain intact.

Staging owner's Test v2, Test Import and Agreement UI verification were merged
through the genuine signed-in browser with App Check into **Staging Unified**.
Test v2's ID/Drive connection is retained. The property picker shows all four
properties; the account audit shows one active owner membership and one bound
organization. A read-only before/after manifest matched all 146 business/history
record hashes, excluding intentionally changed organization/meter/role references.
The existing Drive problem photo rendered successfully in the merged workspace;
no OAuth reconnect or photo upload was needed for this preservation check.
The separate synthetic seed owner remains a multi-organization fixture; do not
merge different owners' data. Deletion confirmation was live-checked without
submitting a deletion of those three staging organizations.

Validation: 619 full sequential Flutter tests passed, followed by 22 final dialog
tests after fixing a reproduced 200% Vietnamese label truncation. Server suite:
332 passing tests. Full Firestore emulator: 99 passing integration tests. Final
Dart analysis has zero errors (420 warning/info items; lint cleanup remains).
Actual Roboto/Material Icons renders were inspected for desktop and narrow 200%
Vietnamese merge/delete dialog and workspace navigation. Landscape keyboard
overflow and label truncation have retained regressions that failed before fixes.
Web release build succeeded; staging backend release
`2026-10-07t00-47-01-811z` has four active endpoints and the authorization probes
were denied as expected. Staging rules and hosting were deployed afterward.

Evidence is local/ignored under `.dart_tool/single-organization-*` and
`.dart_tool/single-org-*`; screenshots are in
`.dart_tool/single-organization-screenshots/`. The plan records remaining provider,
legacy migration, old-client, complete local-stack and calendar/theme coverage
gaps. The standalone handover requires consent; the historical account-deletion
transfer still uses its existing immediate transfer behavior.

Git push was requested by Tom. A zero-byte `.git/index.lock` from September 30
blocked staging; no Git process was running, so it was preserved as
`.dart_tool/stale-git-index-lock-2026-09-30`. The delivery snapshot includes
the tested pre-existing app changes as well as this feature, excluding local
logs, `_to_delete` archives, backups and credentials. Compare HEAD with origin/main
when continuing; these excluded local artifacts intentionally remain untracked.

### >>> PICK UP HERE (updated 2026-10-05, 14:05 PT) <<<
2026-10-05: all on staging and live-checked by the assistant (full test run passed):
month pills show the paid part + room number on later weeks; new bookings pick per
night/per hour from the dates; room area label "(m², bắt buộc)", "100,000 m²",
dot-decimal area; day view: thin rows (30 px, 24 px bars, one line, 12 px corners,
no phone icon), room column fits the names, past days grey. See CALENDAR.md.
Staging test data: room 102 + booking "Nguyễn Thị Lan" 6–8/10 (invented).
Google Drive DONE on staging (16:16 PT): connected as trinhhungqt2004@gmail.com
(fix: new client secret version, see TECHNICAL_PROBLEMS.md); problem photo and meter
photo upload, show in the app, and land in Drive CanHo360/Toa A/Sự cố and /Điện nước.
Staging test data added: problem "Test anh Drive" (room 101, open) and reading
1150 kWh 2026-10-06 on Le Van Chinh's lease. Slow reload (~30 s) and the day view
briefly showing 1/9 while loading are noted for the design pass.
17:10 PT also on staging and checked: photos on the report form, Báo sự cố next to
Đặt phòng, room dialog with chips (Thông tin · Cài đặt · Điện nước · Phí dịch vụ ·
Giá thuê), hover card no longer stuck over dialogs, area shown as "Diện tích: 30 m²".
NEXT: Staff management screen.
### >>> earlier (updated 2026-10-04, 22:50 PT) <<<
Calendar, lease page and booking page: all done locally and accepted by Tom
(2026-10-04 evening). All flutter tests pass (Tom's runs); NOT yet on staging.
Added since 16:30 (details in CALENDAR.md, newest sections):
- Lease form: end date required; due day and per-period amount behind switches;
  "Điện và nước" (price, move-in reading + photo, water per person or whole room).
- Lease page: the rent, rent history and lifecycle sub-pages are gone; end date
  (Sửa), rent change (Đổi), roommates (Thêm, with CCCD/tạm trú), Chuyển phòng in
  "…", two bottom buttons (Lập hóa đơn kỳ, Trả phòng). Scroll kept on refresh.
- Booking page: Sửa on the card, Thu cọc/Thu tiền in the money section, one button
  at the bottom plus "…".
- Day view: 18 px an hour (a day = 432 px; Tom chose it); name bubbles go right,
  left, above or below to avoid other stays' text; status shown once; the end time
  goes in the bubble when the bar is short; lease bars show "HĐ dd/mm/yyyy 12:00";
  stronger colours (85 % paid / 40 % due, names on a light box); no column shading
  (today = date pill + now line); no platform on the calendar; hover card uses "–".
- Month view: stronger pills; past days stronger grey, days to come white + outline.
Fixed before deploy (23:30 PT, tests pass): electricity billing is explained (lease
page tags readings "Đã/Chưa lập hóa đơn"; the period invoice says why there is no
electricity line; server preview returns `lastElectricity`); "→" (not in Roboto)
replaced by "›", "–" or "="; the now line is drawn under the bars.
Local data from 2026-10-04 was LOST (hidden emulator window closed, never saved);
tool\local.ps1 now auto-saves every 5 min, saves on Ctrl+C, and has -Stop.
NEXT: full test run + deploy everything to staging, live check (meter photos need
Drive; real short stays; lease/booking pages), then the Staff management screen.

(Earlier the same day:) Calendar rounds 2026-10-04 (CALENDAR.md, last three sections): bars (2 colours, end
time + status circle, lease period dividers), "Đặt phòng" dialog from the calendar,
no rental mode, booking deposit/surcharges/statuses/problems, and the long-stay lease
(phụ thu, electricity price + meter readings with photos, stay status, deposit
reminder). Server suite passes; waiting for Tom's flutter tests + local check.
Copy-to-laptop tip: edit files directly on the laptop shell; "commit files" wrote
stale copies twice on 2026-10-04.

(Earlier, 2026-10-03 21:30 PT:)
NEW DIRECTION (Tom, 2026-10-03): the app becomes two main screens, Calendar and
Staff management, different per role. Calendar built (CALENDAR.md), waiting for
Tom's flutter analyze + tests, then local check. Next: the Staff management screen.
B7b (photos in Drive) is built but its local check is paused.

B6b move-out settlement DONE on staging, accepted by Tom 2026-10-03 (rent + service-fee
credit options, keep deposit, settle after move-out; details PERIOD_INVOICES.md).
B7a technical problems DONE on staging, accepted by Tom 2026-10-03 (TECHNICAL_PROBLEMS.md;
"Sự cố" under Thêm). NEXT: B7b photos in Google Drive (Tom chose Drive; first write
his Google Cloud OAuth setup steps).
- If staging_verify.cjs says "403 cloudfunctions.functions.list denied" right after a
  good deploy, it was a stale sign-in: rerun it, then staging_all.ps1 -MarkDeployed. Then calendar C,
design pass, G8 v2 migration, AI/subscription clean-up.
- analysis_options.yaml excludes functions/** (node_modules Dart template broke analyze).
- Local data is lost if the emulator window is closed without Ctrl+C; current local
  data (if saved): org "Local Test", Nha A, room 103, fee Rac, 1 settled tenant.
- Design-pass notes: lease form end-date label cut with "..."; payment screen shows long
  invoice id; payment list lacks tenant names; moved-out list doesn't show "not settled
  yet"; period-invoice lease list includes ended leases.

Organization page spacing fix (2026-10-02): local changes widen embedded v2
pages, remove the agreements' nested toolbar and redundant directory refresh
controls. Full Flutter suite 421 passed; final workspace rerun 12 passed.
Not deployed. Scenario coverage and screenshot-font/live verification gaps:
[ORGANIZATION_LAYOUT.md](ORGANIZATION_LAYOUT.md).

**Current authorized delivery sequence (Tom, 2026-10-02):**
1. Implement co-owner agreements and cross-company sharing, test locally, deploy to staging, verify live.
2. **DONE on staging; accepted by Tom, 2026-10-02:** remove AI chat/subscription features and verify live. Remaining verification gaps are recorded below.
3. Continue the remaining client roadmap features.
See [DELIVERY_QUEUE.md](DELIVERY_QUEUE.md). No stage should be marked done before verification.
Implementation of stage 1 is underway: governance.js/governance_access.js and the
OwnershipAgreementsScreen are added and deployed to staging. Local
checks passed: 332 Flutter, 186 server, 94 emulator tests. Six synthetic live
backend scenarios passed, including exact grants, cross-company approval,
revocation and joint closure. Live UI exposed a wrong translation prefix;
its regression failed before the fix, then all 22 agreement tests passed.
The corrected web build is deployed and its translated group headings were verified live. New owner
agreements need recipient and current-owner consent; operational grants are copied
exactly and sensitive controls are separate. Temporary synthetic live verification
script: tool/staging_governance_live.cjs. Current runtime is Windows PowerShell with
Flutter at C:\Users\ASUS\Desktop\UI\flutter\bin; older VM-only notes below are historical.

**AI/subscription stage — DONE on staging, accepted by Tom (2026-10-02):** removed launcher, chat/import/purchase UI,
purchase SDK and provider bindings. Six inert compatibility endpoints refuse old
requests; all six verified live. Staging web deployed successfully after clearing
a stale generated purchase-plugin registrant. Vietnamese mobile/desktop dashboard,
populated Test v2 booking list, detail and return navigation were checked live with
no AI overlay. Evidence: `.dart_tool/ai-removal-screenshots/`. Server suite 188 passed;
full Flutter run 331 passed plus one shared-helper import failure, fixed and both
dependent files passed five checks. Analysis has no errors. English/large-text live
checks and actual purchase cancellation are not claimed. See AI_REMOVAL.md.

**B4 — DONE on staging, accepted by Tom (2026-10-02, evening).** Final live
fixes: room pages have their own address (`utilities--`/`settings--`/`rates--`
records), re-tapping the open tab returns to the list, utility errors show next
to the action (Retry only when it can help), the invoiced-reading dialog only
explains the invoice step, and a conflict-mode account reopens its own
organization after a reload. Test account conflict came from a seed staff
membership (revoked); diagnose with `tool/staging_account_conflict.cjs EMAIL`
(read-only). Layout items for the design pass are in CLIENT_ROADMAP.md.
**B5 service fees — DONE on staging, accepted by Tom (2026-10-02).** Details,
live check and the partial-period rule: SERVICE_FEES.md. Two small fixes after the
check (editor start date, review wording) go out with the next deploy.
**Working rule (Tom, 2026-10-02): test locally whatever can be tested locally, and
deploy only for the things that can't** (details in AGENTS.md, "Local first").
**B6a period invoice — DONE on staging, accepted by Tom (2026-10-02).** One invoice
per lease period (rent + fees ahead, unbilled readings behind, manual late/discount/
damage/other lines), from Invoices ("Hóa đơn kỳ") or the tenant page ("Lập hóa đơn
kỳ"). Double billing is refused at Review for every invoice kind; fees already billed
show greyed out. Fee prices are per month (3-month period = 3 × price). Backdating
keeps the "Nhập ngày trong quá khứ" permission rule. Reload now shows a neutral
"Đang mở lại trang…" screen (still slow, ~4 s of server calls; possible later speed-up
of listMyOrganizations). Details and both live checks: PERIOD_INVOICES.md.
**Local emulator stack: DONE and working (2026-10-02, see "Local testing" below).
Local data: organization "Local Test" (owner@canho.test).** B6b move-out settlement
DONE on staging, accepted 2026-10-03. B7a technical problems DONE on staging,
accepted 2026-10-03. Next: B7b photos in Google Drive.
Another AI may do UI work in parallel: B6 owns
`functions/`, invoice/payment/lease/tenant screens, B4/B5 screens, team_service,
preview stores, role_workspace, room_directory; ws_ui/app_theme only after asking.

Earlier B4 release notes: utility readings, dated property/room tariffs,
meter replacement, audited latest-reading reversal, and invoices from saved usage
are implemented. Room navigation and callable export are connected. Local checks:
211 server tests, 97 emulator checks, full Flutter 354 tests then final targeted
utility/room 29 tests. Actual-font populated tariff views inspected in Vietnamese
phone/200% and English desktop/100%. Web build succeeded. Backend release journal:
`.dart_tool/staging-release/2026-10-02t21-20-19-549z` (six endpoints).
Backend/web deployment succeeded. Five live callable checks passed; signed-in Vietnamese phone UI saved baseline, property tariff, 25 kWh / 87,500 VND and a linked invoice. A billed-reading correction was refused; wrapped server errors showed generic text, reproduced by a failing test and fixed (24 utility tests now pass). Hosting message-fix rollout is finishing; recheck that exact message live. English/large-text live checks remain open. (Superseded: B4 accepted 2026-10-02.)
Period invoice aggregation stays B6. See UTILITY_READINGS.md for scenarios and gaps. B5 scenario plan is in SERVICE_FEES.md; implementation has not started.

**Roadmap status clarified (Tom, 2026-10-02):** B1–B3 parent checkboxes remain open
for calendar entry, notifications, utilities/fees, technical problems and reminders.
Completed core forms are now checked subitems; do not rebuild them or imply the
full original scope is complete merely because those forms were deployed.

**Earlier design notes (superseded by the authorized implementation above):**
Tom now wants BOTH. Current code implements the earlier stricter single-owner
policy and the new delegable additional-workplace permission; it does not yet
implement co-ownership or cross-company sharing. Keep this policy release pending
until the revised model is agreed and implemented. See the latest-direction section
in STAFF_ACCOUNT_POLICY.md. Tom chose a configurable co-owner permission agreement, like Vai trò và phân quyền,
including sensitive authority; no fixed primary-owner-only rule was accepted.
Joint approval and agreement-change consent are proposed details, not implemented.

**Earlier implementation: staff account policy and delegable additional-workplace permission.**
Implementation/verification: [STAFF_ACCOUNT_POLICY.md](STAFF_ACCOUNT_POLICY.md).
Owner and staff accounts are exclusive; another employer is refused. Under the
same owner, only the owner or a delegate authorized in BOTH organizations can
approve another workplace. The owner alone grants this new role permission.
Staff enter their work area instead of the owner dashboard. This is not deployed
or signed off. Use the full `tool\staging_all.ps1` command (without `-Tests`)
for this cross-cutting release; it includes server tests and Firestore rules.
Deploy server/rules and the new web client together because old clients used
direct legacy organization creation. AI/subscription removal is a separate plan,
not implemented or marked done.


1. **Deploy completed by Tom; owner live checks completed 2026-10-02.**
   Verified in Test v2: Le Van Chinh's documents, lease/payment-period/deposit
   details; Pham Thi Dung's "Ở cùng Le Van Chinh" label; cancelled booking
   hides "Còn phải trả" and exposes deposit refund in the overflow menu.
   **Deferred checks — still unverified:**
   - Restricted-role CCCD masking (Test v2 currently has only its owner).
   - Active-booking "Nhận phòng" button (only a cancelled booking was available).
   - English, mobile, and enlarged-text layouts (including 130% and 200%).
   Owner checks were read-only, in Vietnamese at desktop size; no automated
   tests were run in this live-check session. Do not treat these as full sign-off.

   Previous deploy command (tenant page + first design fixes; already completed):
   `powershell -ExecutionPolicy Bypass -File tool\staging_all.ps1 -Tests tenant_contacts,tenant_lease,tenant_rent,tenant_rent_history,tenant_roommate,lease_details,role_workspace`
   If a test fails, give the failing part of the output to the assistant.
2. **Live-check reference checklist** (see completed and deferred items above):
   open Test v2 → Người thuê → tap "Le Van Chinh".
   The page should show Giấy tờ (CCCD, tạm trú), Hợp đồng (moved in, rent,
   "Mỗi 3 tháng vào ngày 5", 15.000.000 per period, deposit 5.000.000 ·
   Vietcombank 0123 - Test) and Liên hệ. "Pham Thi Dung" should say
   "Ở cùng Le Van Chinh". A role without "Xem số CCCD" must see •••• 3333.
   Bookings: the detail page has one filled button (Nhận phòng) and a "…"
   menu; a cancelled booking shows no "Còn phải trả".
3. **Next: B7b problem photos in Google Drive, built and tested locally first** (B4, B5, B6a done 2026-10-02; B6b and B7a done 2026-10-03), then the calendar (C).
   Details and decisions are in [CLIENT_ROADMAP.md](CLIENT_ROADMAP.md) under
   Phase B / Phase C. Small leftover: ask CCCD and tạm trú when adding a
   roommate to an existing lease.
4. After all client features: the design pass (notes in CLIENT_ROADMAP.md,
   "Design notes for the pass", plus Tom's screenshots), then move every
   production organization to v2 (G8 batch) and delete the legacy code.
5. Then the AI/subscription clean-up (Tom, 2026-10-02): delete the dead
   `functions/ai.js`, `ai_import.js`, `subscriptions.js`; remove and
   explicitly delete the six retired stub endpoints once no old app version
   is in use; remove production Gemini/RevenueCat secrets. Checklist in
   CLIENT_ROADMAP.md "Start here" item 5 and AI_REMOVAL.md.

Suggested first message in a new chat:

> Read HANDOFF.md, AGENTS.md and CLIENT_ROADMAP.md in my project, then continue
> from "What to do next".

## How Tom wants to work

- Buttons should have concise single-line labels. Do not hide headings or owner names with ellipses to make them fit; adjust the layout and keep full information visible. Tom rejected these compromises on 2026-10-02.

- When work is finished and Tom says "OK" to that completed item, mark it
  done in the relevant roadmap/checklist and update this handoff. Keep any
  deferred or unverified checks explicitly open; approval of a proposal is
  authorization to implement it, not evidence that implementation is complete.
- Write code straight into the project (D:\apartment_management_project_2);
  give Tom a short list of what changed. Tom runs Flutter and the deploy
  script; the assistant reads the output files.
- Think through every situation before handing over a feature (AGENTS.md).
- **Do all client features first; the UI design pass comes after.** While
  working, note design problems in the roadmap ("Design notes for the pass").
- After every deploy, **the assistant does the live test on staging itself** (see
  below), sends screenshots, and lists anything that looks wrong — bugs,
  bad layout, unclear wording, design problems.
- the assistant never types passwords or signs in; Tom signs in himself. Never copy
  live tenant data or provider secrets into staging.
- Delete files only when Tom asks.

## Where things run

(These notes describe the setup used with Claude. Another assistant may not
be able to run commands on the laptop or drive a browser; then Tom runs the
commands and checks, and pastes the results.)

- Tom's laptop: Windows, project at `D:\apartment_management_project_2`,
  Flutter + Firebase CLI. Only Tom can run `flutter`.
- The assistant's shell on the laptop is a Linux VM; the project is mounted at
  `$HOME/mnt/apartment_management_project_2`. There is no Flutter or Dart
  there and the network allowlist blocks downloading it.
- Server tests (Node) run in the assistant's copy `$HOME/work/functions`
  (`npm test`). Copy changed `functions/*.js` and tests there first. One test
  ("Dart and server policies…") fails only in that copy because `lib/` is
  not there — ignore it.
- The Dart analyzer tool of the Flutter plugin often answers "No errors"
  even when there are errors. Trust only Tom's `flutter analyze`.
- Editing: files keep CRLF line endings. the assistant uses a small Python helper
  (`$HOME/work/edlib.py`, `rep(path, [[old, new, count?]])`) that keeps them.
  Large new files are written in the cloud workspace and copied over with
  "commit files"; **check afterwards that the file on the laptop really
  changed** (once an older copy was written).
- PowerShell output saved with `*> file.txt` is UTF-16; read it with
  `iconv -f UTF-16LE -t UTF-8 file.txt`.

## Local testing (no deploy) — use this first

`powershell -ExecutionPolicy Bypass -File tool\local.ps1` starts the Firebase
emulators (Auth, Firestore, Functions; demo project `demo-canho360`, no cloud
data) in a second window, creates local test accounts, and runs the app at
http://localhost:5300. Needs Java 11+ for the Firestore emulator.
- Accounts (local only, from `tool/local_seed.cjs`): owner@canho.test /
  local-owner-123, staff@canho.test / local-staff-123, staff2@canho.test /
  local-staff-456.
- The app is a release build in `build/local-web` (never `build/web`/staging-web),
  served by `tool/local_serve.cjs`, which also forwards sign-in, Firestore and
  functions paths to the emulators: the page calls only its own address (the
  Claude pane blocks calls to other localhost ports and cannot connect to Flutter
  debug mode). After app changes: Ctrl+C in the app window, then the same command
  again (~1-2 min; emulators keep running). Server changes in `functions/` reload
  by themselves. `-Debug` = `flutter run` with hot reload (`r`) for Tom's own
  Chrome; its forwarding comes from `web_dev_config.yaml` (debug only). If a browser still talks to port 9199 after a change, clear
  its session storage (FlutterFire remembers the emulator address there).
- Local data is saved to `.local-data\` every 5 minutes while the emulators run
  and when the app is stopped with Ctrl+C (2026-10-04: the emulator window is
  hidden; closing it lost a whole day of seeded data). Stop the emulators with
  `tool\local.ps1 -Stop` (saves, then stops; never close windows). `-Save` saves
  while running; `-Fresh` starts empty (old data is moved, not deleted); `-NoApp`
  starts only the emulators. Emulator UI: http://localhost:4100.
- Local mode is the `LOCAL_EMULATORS` dart-define (lib/services/local_emulators.dart).
  On the server, App Check is skipped only when FUNCTIONS_EMULATOR is set AND
  the project is a `demo-` project (request_security.js `localEmulator()`,
  tested); v2 organization creation is on locally.
- `local_serve.cjs` also adds a small script to index.html that sends requests
  for Google's sign-in servers to the local Auth emulator: FlutterFire restores a
  remembered sign-in while Firebase starts, before `useAuthEmulator` runs, so
  without it a reload signs you out (`__FIREBASE_DEFAULTS__` does not help:
  FlutterFire uses initializeAuth, which ignores it).
- If a rebuild does not show an app change (build/local-web/main.dart.js keeps
  its old time), make a real content change in the edited file (a comment is
  enough): a build that started just before an edit can record the new content as
  already built; touching the file does not help (Flutter compares content).
- Copying files to Tom's computer: the "commit files" step keeps the FIRST version
  of a file name; a second send of the same name can silently write the old content.
  Send changed files under a new name (or edit on the device) and compare md5sum.
- Not testable locally: App Check/reCAPTCHA, real email, Google sign-in/Drive,
  hosting headers. Those, and the final check of a finished feature, go to staging.

## Deploying to staging (fast)

`tool\staging_all.ps1` does: analyze → tests → functions deploy → web build →
hosting deploy, and stops at the first failure.

- Functions deploy is **skipped automatically** when nothing in `functions/`
  changed since the last successful deploy; web build + hosting are skipped
  when nothing in `lib/ web/ assets/ pubspec` changed. Each step prints how
  long it took.
- Run only the tests for what changed:
  `powershell -ExecutionPolicy Bypass -File tool\staging_all.ps1 -Tests booking_form,operational_workflows`
  (names of `test\<name>_test.dart`; the script refuses unknown names).
  Run **all** tests (no `-Tests`) after changes to shared pieces (`ws_ui.dart`,
  `app_theme.dart`, preview stores, translations used everywhere) and before
  anything goes to production.
- `-Force` deploys everything; `-MarkDeployed` only records the current
  functions as deployed (after deploying them another way).
- Full test run ≈ 7–8 min; 269+ tests. Save long output with `*> tests.txt`.
- Never stop a run during "Functions deploy" (half-updated functions).

## Live test on staging

- Site: https://apartment-management-staging.web.app (Claude used the
  built-in browser of the Claude desktop app; any browser works). Tom is already signed in there.
- Test organization: **Test v2** (owner), property **Toa A**, room **101**
  (monthly + short stay; 5,000,000 / month, 100,000 / hour, 500,000 / day,
  300,000 overnight, daily threshold 6 h). Test data made by the assistant: a
  cancelled booking "Nguyen Van An" (300,000 deposit still recorded), lease
  "Le Van Chinh" + co-tenant "Pham Thi Dung", account "Vietcombank 0123 - Test".
- After a deploy, **reload the page** (`location.reload()`); changing only the
  `#/…` address does not load the new version. The first call after a deploy
  takes 10–15 s (server cold start).
- The app is drawn on a canvas: there is no page text tree, so work with
  screenshots and coordinates. Fill one field at a time and take a screenshot
  when the layout may shift (e.g. "2 đêm" appears and pushes fields down);
  the first click on a button sometimes only focuses the page — click again.
- Opening a URL in the pane reuses the same tab, so unsaved form state is
  lost; finish one flow before checking another page.
- Save the useful screenshots and send them to Tom with a short caption.

## Design rules learned (apply in new work, fix old screens in the pass)

- Build pages from `lib/screens/team/ws_ui.dart`: `WsPage` (centered, not a
  lazy list — every field/message must stay built), `WsHeader`, `WsSection`
  (titled card; its header button stays on one line and moves under the title
  when there is no room), `WsFieldRow` (fields side by side on wide screens),
  `WsActions` (right-aligned buttons that wrap to a new line, never
  full-width), `WsInfo` (label/value rows), `WsRecord` (tappable list row,
  `tapKey` for tests/links), `WsPill`, `WsNotice`, `WsEmpty`, `WsSpace`.
- Buttons: short 1–3 word labels, one line, never two-line text. One filled
  button for the usual next step; rare or undoing actions go in a "…" menu.
  No "Open"/"Reload" buttons that repeat a tappable row or the refresh icon.
- Numbers (Tom, 2026-10-05), the same in Vietnamese and English: money with a comma
  between thousands and a dot before cents ("5,000,000 VND", "2,000.50 USD"); kWh, m³,
  kg and hours with no thousands mark and a dot for decimals ("1200.5 kWh"). Money
  boxes group while typing. Use `lib/utils/app_number.dart` (`appMoneyMinor`,
  `appQuantityMilli`, `appParseMoney`, `appMoneyInput`), never a per-screen NumberFormat.
- Never show internal IDs ("lease_c23d…", "Mã tham chiếu"). Show names and
  room numbers ("Ở cùng Le Van Chinh", "Phòng 101").
- Colors, text and field styles come from the theme (`workspaceTheme`), not
  from widgets. Hint text is light grey so it never looks like a value.
  Dropdown values in regular weight. Grey (slate) is the default accent.
- Prefill what is known (room price, amount still owed). Keep the form and
  what was typed when the server refuses something fixable, and show the
  message next to the buttons.
- Status words as anh Hưng uses them: "Đã cọc – chưa nhận phòng",
  "Đang ở", "Đã trả phòng".

## Engineering conventions learned

- Version-2 data: the server owns every write; callables check permissions
  again. New fields are **optional** so older app versions keep working.
- CCCD numbers: full only with the "Xem số CCCD" permission (`readGuestIds`),
  otherwise `•••• 1234`; leaving the box empty keeps the stored number; never
  in activity history.
- The preview stores (`lib/preview/*`) are the fake server for widget tests;
  keep them in step with the real callables.
- Widget tests: `find.text` also matches text inside input boxes; `press()`
  needs exactly one button with that label; keep `ValueKey`s stable.
- Hosting: assets must be revalidated (`Cache-Control: no-cache`), otherwise
  browsers keep an old icon font and new icons show as blank gaps.

## 2026-10-06 — Co-ownership and Google Drive on the home screen (Tom)
- Đồng sở hữu và chia sẻ is no longer a page in each organization's Cài đặt.
  The home screen's handshake button opens it; a "Tổ chức" picker lists the
  organizations this account owns/co-owns (listMyOrganizations now marks
  `owner: true`), "Lời mời gửi cho bạn" shows agreements sent to you.
- Google Drive is connected once per owner account on the home screen (Drive
  button, owner accounts only): `googleDrive` without organizationId works on
  driveAccounts/{uid}. Every organization uses its own older connection
  (driveConnections/{org}) if one is active, else its owner's (owner first,
  then co-owners) — drive.js driveConnectionFor(). Photos, meter photos,
  problem lists and the import's Google Sheet all go through it. The Google
  Drive page is gone from organization settings.
- Tests: functions/test/drive.test.js (owner's own Drive),
  test/problem_photos_test.dart (home-screen connect sends no organization).

## Next fixes (Tom, 2026-10-06) — not started
1. Calendar building picker (several buildings): too much space between the
   name ("Nhà Mẫu A") and the dropdown arrow — make the box fit the name.
2. Calendar with one building: the "Toa A" label and its settings (gear)
   button are too small — make them the same size as the picker.
3. Idea (Tom considering): move Thu chi into Thống kê.
4. Đặt phòng ngắn ngày — "Giá mỗi đêm": let people save common prices and pick
   one (chips) instead of typing each time. Decided: the list belongs to each
   room (rooms have different prices). Who may add: those the owner or a
   manager allows — a permission in roles (on for owner/manager by default).
5. Editable total, for short stays AND leases (dài hạn): the calculated
   total/rent can be changed when the price is negotiated up or down. Decided:
   every change records the reason and the employee who made it (and the
   original calculated price). Keeps the "Đổi giá" permission.
6. Done 2026-10-06: home-screen role badge hidden until the role has loaded
   (it showed "Vai trò riêng" first).
7. Calendar cleaning bubble ("Dọn phòng · tom 09:46"): it shows beside the
   short cleaning bar and covers the name on the booking bar next to it.
   Wanted: show the bubble BELOW the cleaning bar. The bubble may draw outside
   the calendar (on top of everything, not cut off at the calendar's edge) —
   it seems stuck beside the bar now because it is only allowed inside the
   calendar. When a bar's name still has no room, move only that NAME label
   out of the way (the bar itself keeps its place and size).

## Speed (2026-10-06) — plan, not started
- Measured causes: the web app is ~15 MB (main.dart.js 7.5 MB + canvaskit.wasm
  7.2 MB, revalidated on every load; "?v=" in tests forces a full download);
  every callable runs in us-central1 (USA) and does a rate-limit transaction
  plus membership reads before its own work, so each step pays several
  US round trips from Vietnam; only listMyOrganizations, calendarView,
  readWorkspace and readTeam stay warm (minInstances 1), the rest start cold;
  the Claude browser pane itself adds clicks lag (QUIC timeouts seen).
- Production has the same setup, so it will not be faster by itself.
- Order: (1) measure in normal Chrome on staging (time to calendar, time to
  open a booking); (2) if Firestore is in Asia, move functions to
  asia-southeast1 (biggest win, app must call that region); (3) keep the
  booking/problems functions warm; (4) fewer reads per call (rate limit +
  membership in one read); (5) web: show the shell fast (deferred loading).

## Speed step 2 (2026-10-06): functions moved next to the database
- `node tool/where_is_data.cjs`: Firestore is in asia-southeast1 (Singapore) in
  BOTH projects; functions were in us-central1, so every read crossed the
  Pacific twice. Now every function declares REGION from functions/region.js
  (asia-southeast1): createSecureCallable adds it, plus the purge schedule
  and the retired webhook. The app calls that region through
  lib/services/app_functions.dart (`appFunctions`, never
  FirebaseFunctions.instance). Staging tools read the same constant;
  staging_release.cjs creates the image repository in a new region.
- Staging: after the first deploy, the old us-central1 functions still exist
  (and the old purge schedule still runs). `node tool/staging_release.cjs
  remove-old-region` lists them; `--delete` removes them — only when Tom says.
- PRODUCTION WARNING: the published app still calls 6 functions in
  us-central1 (mutateCalendarBooking, mutateCalendarTenant, AI…). A production
  functions deploy from this code puts everything in asia-southeast1 and the
  Firebase CLI will offer to delete the us-central1 ones: answer NO until the
  new app version is published and old versions have updated.
- Staging always deploys minInstanceCount 0 (tool/staging_release.cjs), so on
  staging every function can start cold; production keeps the 4 HOT ones warm.
- Tom (2026-10-06): remove the old us-central1 functions once the speed work
  is finished (target market is Vietnam). Staging: remove-old-region --delete.
  Production: only after the new app is published and old versions updated.

## Speed step 3a (2026-10-06): fewer startup calls before the calendar
- Before (warm, from the pane): 7 calls one after another, about 9 s; cold about 41 s.
- dashboard_screen.dart: a reload on an /org/... address opens that organization right
  away (post-frame), while the account check runs underneath. If the account turns out
  not to be allowed there (not listed, waiting, email not verified, or in conflict and
  not the owner), the page is closed again and the entry screens show why.
- dashboard_screen.dart: the organization list reuses the account check's list when every
  organization is version 2 (one listMyOrganizations less).
- account_entry_service.dart: the listed organizations also keep updatedAt.
- role_workspace.dart: access (myAccess) and the building list load at the same time.
- Still to measure after deploy; calendarView still starts after the workspace load.
- Measured after deploy (pane, reload on the calendar address): the server
  calls now run in 2 rounds instead of 7 in a row (claim + settings + team +
  buildings together, then calendarView). Warm: first call at 3.1 s (app
  download/start), calendar data at 7.3 s (server part ~4.2 s, was ~9 s).
  Fairly cold: calendar data at 12.3 s (was ~41 s).

## Speed step 5 (2026-10-06): server time, full CPU
- tool/function_times.cjs (read-only): server time per staging function from
  the Cloud Run request logs, plus each function's memory/CPU.
- Found: every function had 256 MB = 1/6 CPU. Warm server time for a few
  database reads was 0.3-2.6 s (organizationSettings, 512 MB = 1/3 CPU, was the
  fastest). The browser saw ~0.5-0.8 s more per call (travel from California
  + the browser's extra CORS check call, the 204 lines in the log).
- First try (cpu 1 for all 43 functions) STOPPED the staging deploy: "Quota
  exceeded for total allowable CPU per project per region" after 20 functions
  (every new copy stays around idle for a while and counts).
- Change now: index.js FAST = {cpu:1, memory:'512MiB'} only for the calls a
  screen start makes (claimMyInvitations, listMyOrganizations,
  organizationSettings, readTeam, readWorkspace, calendarView,
  bookingWorkspace). The rest keep the default (256 MB, 1/6 CPU). One idle copy
  of every function now adds up to ~13.7 CPU. tool/staging_release.cjs passes
  cpu and concurrency (80) to staging, and reads memory safely.
- tool/function_times.cjs also prints the region CPU quota.
- Step 4 (grouping functions into a few) also helps here: fewer copies, so
  all of them could get a full CPU.
- Cost: billed only while answering requests (staging and production without
  warm instances), so normal use stays in the free tier.
- Tom (2026-10-06): no monthly cost. index.js HOT is now {} (no always-running
  copies, in staging and production). Do not turn it back on without asking Tom.
- Measured after the FAST deploy (pane, California): warm calendar data at
  4.6-5.5 s after the page opens (was 7.3 s); fast calls ~0.6 s each, mostly
  travel. Cold: ~3.6 s per call (was 6-8 s), calendar data at 10.8 s.
- Region CPU quota (staging): Total CPU allocation = 20 CPUs.
- tool/staging_release.cjs now always sends the CPU (Google keeps the old one
  when it is left out: deleteMyAccount/importSheet kept a full CPU).

## Speed step 4 (2026-10-06): grouped functions
- Why: 43 one-call functions each started (cold) on their own and each kept
  its own idle copy; a full CPU for all went over the region limit (20 CPU).
- Now 4 deployed functions: app (every normal call; cpu 1, 512MiB, 80 calls at
  once per copy, max 5 copies), heavy (importSheet only; cpu 1, 1GiB, max 3),
  purgeClosedOrganizations (schedule) and revenueCatWebhook (unchanged).
- How: functions/request_security.js createCallableGroups. index.js registers
  each call by name (secureCallable = callables.register; {group:'heavy'} for
  importSheet) and exports app/heavy. The app sends {fn:<name>, data:<data>}
  to the group (lib/services/app_functions.dart appCallable/functionGroup).
  Every call still goes through the same guard UNDER ITS OWN NAME (App Check,
  sign-in, size and rate limits, organization budget); an unknown name or a
  call of another group is charged, then refused (not-found unknown_call).
- No old app version uses the asia functions (production only has the 6 old
  us-central1 ones), so no compatibility layer was needed. After production
  is published, a call name can never be renamed or moved to another group
  without keeping the old route for old app versions.
- Tests: functions/test/call_group.js (via) for tests that ran one exported
  function; request_security.test.js has 5 group tests; test/app_functions_test.dart
  checks the app's group map against functions/index.js.
- Tools: staging_live_test.cjs / staging_governance_live.cjs send to the
  groups. tool/staging_release.cjs remove-unused [--delete] lists/deletes the
  functions in the region that the last finished release no longer has (the
  43 old ones). Run --delete only when Tom says so.
- Deployed 2026-10-06. Checked in the pane: calendar, Người thuê, Thu chi,
  Nhân sự, Cài đặt all load through 'app'. Warm: calendar data 4.9 s after the
  page opens (calls ~0.45 s each, from California). The 43 old functions still
  exist on staging until Tom says to run remove-unused --delete.
- 2026-10-06: Tom ran remove-unused --delete: 41 old functions removed; staging now has app, heavy, purgeClosedOrganizations, revenueCatWebhook (asia-southeast1). Calendar checked after: works.

## Speed step 1 (2026-10-06): copy of server answers on the device
- lib/services/read_cache.dart (ReadCache): saved server answers in
  SharedPreferences (localStorage on web), key = account + sha256(call + request).
  Max 40 entries / 3,000,000 characters (oldest dropped), 30 days; a full
  storage wipes the copy instead of failing.
- Wiped: sign-out and account switch (main.dart listens to auth changes and
  keeps only the current account's entries); an access error from the server
  (permission-denied, unauthenticated, not-found) wipes that organization.
- Only to SHOW: every change still goes to the server, which checks the role.
  TeamService uses the copy only for the app's own service (a test transport
  gets none unless the test passes cache:).
- Used now: RoleWorkspace (saved role + building list open the pages at once;
  a network failure keeps them, any access problem clears them and the copy),
  RoomCalendar (calendarViewLive: saved copy with the progress bar running,
  then the server's answer; unreachable server keeps the copy with the error
  notice; refused access clears the screen).
- Not yet: the home-screen organization list (account check), the organization
  name in the header, other pages (bookings, tenants, money...). Next: step 3,
  one call per screen elsewhere, and more screens on the device copy.
- Tests: test/read_cache_test.dart.
