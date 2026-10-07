# Client roadmap — DailyPlus requests (anh Hưng)

Written 2026-09-30 from anh Hưng's messages, his reference web app
(Homestay / Google Apps Script), the Airbnb year calendar he sent, and his
handwritten notes for long-term and short-term bookings. This file is the
single list for this work. [RELEASE_TASKS.md](RELEASE_TASKS.md) keeps the
release/security tasks and points here.

Rules for every task (from [AGENTS.md](AGENTS.md)): write the situation list
first (who can use it and what the server re-checks; empty/loading/error;
retries, double taps, two people at once; legacy organizations; every field;
en/vi, phone/desktop, large text). Server owns every write for v2. Tests with
each change. Tick a box only after Tom's live test passes.

---

## Start here (next chat)

Read [HANDOFF.md](HANDOFF.md) first: what to do next, how Tom works
with an AI assistant, fast deploys, the live test on staging, design rules.

Status clarification, 2026-10-02: B1–B3 core forms are deployed. Their parent
checkboxes below describe the larger original requests, including dependencies
that are still unfinished; checked subitems identify the completed forms.
B4 is DONE on staging, accepted by Tom 2026-10-02 (see [UTILITY_READINGS.md](UTILITY_READINGS.md)).
B5 service fees is DONE on staging, accepted by Tom 2026-10-02.
B6a period invoice is DONE on staging, accepted by Tom 2026-10-02 (see [PERIOD_INVOICES.md](PERIOD_INVOICES.md)).
Local emulator stack is set up (tool\local.ps1). B6b move-out settlement is DONE on staging, accepted by Tom 2026-10-03. B7a technical problems is DONE on staging, accepted by Tom 2026-10-03. Next: B7b problem photos in Google Drive.

Earlier state on 2026-10-01 (night):
1. Done and deployed to staging: G8 (v2 organization creation, migration
   tool), U1 (workspace navigation + redesign), B1–B3 (new booking button,
   short-stay form with per-night prices, surcharges, co-guests, CCCD masking,
   staff, platform/channel, receiving accounts; long-stay lease form with
   co-tenants, tạm trú, payment period, deposit). Grey theme is the default.
2. Waiting: Tom's run of the tenant-page tests + deploy, then the assistant checks
   the new tenant page live (CCCD masked for roles without "Xem số CCCD").
3. Next features, in order: **B4** electricity/water readings, **B5**
   service fees, **B6** period invoices, **B7** technical problems, then the
   calendar (C). Also: CCCD/tạm trú when adding a roommate later.
4. After all client features: the design pass (notes under B1–B3 below and
   Tom's screenshots), then G8 batch migration of all production
   organizations and removal of the legacy (v1) code.
5. AI/subscription clean-up (Tom, 2026-10-02), after the v2 move and a new
   App Store / Play release that everyone has updated to:
   - delete the dead server files `functions/ai.js`, `functions/ai_import.js`,
     `functions/subscriptions.js` (nothing loads them) and their old tests;
   - remove the six retired stub endpoints (`aiChat`, `aiUsage`,
     `aiImportPreview`, `aiImportCommit`, `aiSyncSubscription`,
     `revenueCatWebhook`) from `functions/retired_ai.js` / `index.js`, delete
     them from the deployed project explicitly (removing the export alone
     does not delete a deployed function), and update the endpoint count in
     `functions/test/staging_identity.test.js`;
   - production: remove the Gemini / RevenueCat secrets and cancel any
     provider subscription (see AI_REMOVAL.md).

Suggested first message for a new chat:

> Read HANDOFF.md, AGENTS.md and CLIENT_ROADMAP.md in my project, then continue
> from "What to do next".

---

## Decisions so far

| Topic | Decision | Who / when |
|---|---|---|
| Staff sign-in | Google sign-in with the company's **ordinary Gmail** accounts (no company domain, too costly). Owner adds each staff Gmail; only listed emails can join. Cut access instantly in the app. No passwords made by the owner. | anh Hưng + Tom, 2026-09-30 |
| Roles | Owner creates role names and ticks what each role may do, with a limit per permission (all properties / properties they manage / only their own records). Current six roles become starter templates. | Tom, 2026-09-30 |
| Investor | Just a role template; every ability optional, limited to their properties. | Tom, 2026-09-30 |
| Booking platform (Airbnb, Booking.com…) | Optional field. Shown on the bar only when filled. | Tom, 2026-09-30 |
| Technical problems | Optional, per booking/room. Blocking the room is an option. | Tom, 2026-09-30 |
| Payment notification | App push notification (shows outside the app on phones). No SMS/Zalo. | Tom, 2026-09-30 |
| Bar colour vs dot | Colour = kind (short-term / long-term / deposit only). Dot = payment (green paid in full, red not fully paid, orange deposit paid). | anh Hưng + Tom |
| Long-term invoices | Yes: each payment period combines rent + electricity + service fees, and other combinations (see B6). | Tom, 2026-09-30 |
| Period invoice contents (B6) | Rent and service fees for the coming period (paid in advance) + every meter reading not billed yet (usage paid behind). Individual B4/B5 invoices stay possible; nothing is billed twice. | Tom, 2026-10-02 |
| Late fees (B6) | Manual line added by the owner when they decide; no automatic charge. | Tom, 2026-10-02 |
| Deposit at move-out (B6) | One final settlement invoice: unpaid charges + damages − deposit → refund or amount still owed. | Tom, 2026-10-02 |
| Discounts (B6) | Manual minus line with a reason, amount or % of rent, on that invoice only. | Tom, 2026-10-02 |
| Commission base | Long-term: on the monthly room price. Short-term: on the price of one night. Record nights sold per staff per month for KPI, salary and bonus. | anh Hưng, 2026-09-30 |

## Open questions (ask anh Hưng)

- [ ] Commission details (sent 2026-09-30, waiting): long-term once at signing
  or every month? short-term once per booking or × nights? cancelled /
  unpaid bookings? bookings across two months? one % per person or separate
  long/short %?
- [ ] Drive/Sheet: one-way automatic backup copy (recommended) or editing in
  the Sheet flows back into the app?
- [ ] What must be in the first release to his staff (proposal: R1, R2, G8+his
  organization migrated, B1–B3, C1, dot colours).
- [ ] Technical problem fields: description, photo, cost, who fixed it, status?
- [ ] Apple: offering Google sign-in on iPhone normally requires Sign in with
  Apple too, unless the app qualifies as a business app using existing
  company accounts. Decide: add Apple sign-in, or check the exception.

---

## Phase R — Access (do first)

- [x] **R1 Custom roles and scoped permissions** — DONE: live staging tests
  1–16 passed (Tom, 2026-10-01). Open idea: "customize for this person"
  shortcut (copy role for one member) — not decided. Decisions (Tom, 2026-09-30):
  grants copied onto memberships; three scopes; "manage roles" is a permission
  the owner gives (not owner-only).
  - Design:
    - Roles are data: `orgRoles/{orgId}_{roleId}` (name, colour, grants
      `{permission: scope}`, revision, tombstone `deletedAt`). No client access
      (rules have no catch-all); purge covers it; copy leaves it with the source.
    - Starter templates keep their old IDs (`administrator`, `manager`,
      `receptionist`, `housekeeper`, `accountant`) plus new `staff` (Nhân viên)
      and `investor` (Nhà đầu tư). They live in `functions/role_templates.json`
      (shared with Dart, parity-tested) and exist without a document until
      someone edits or deletes them. Owner is fixed and never stored.
    - Scopes: **all** = every property of the organization; **managed** = the
      member's own property list (as before); **own** = inside their properties,
      only records with `createdBy` = them or `staffInChargeId` = their staff
      profile. On/off permissions (settings, team, roles, activity, export,
      import, Drive, backdating) are organization-wide. "Own" exists for
      bookings only for now (view, edit); leases/expenses get it with B3/E1.
    - Membership carries `roleGrants` + `roleRevision` + `roleName` (a copy).
      `allows()` stays synchronous; a membership without a copy follows its
      template (so template changes in code still reach it). Saving a role
      rewrites the copy on every holder in the same transaction (max 400).
    - New permissions: `createBookings` (split from manageBookings — templates
      that had manageBookings get both), `backdateRecords` (replaces the six
      hard-coded owner/administrator checks), `manageRoles`.
    - Levels: owner 3 > manage roles 2 > manage team 1 > others 0. You can only
      change people and roles below your level, and only give permissions you
      hold at an equal or wider scope. So only the owner gives/removes "manage
      roles"; a role manager can create roles with "manage team"; an
      administrator without "manage roles" behaves exactly as before.
    - Account-deletion hand-over candidates: active members with settings +
      team permissions over all properties (was: literal `administrator`).
  - Server: `team_access.js` (grants/scopes/levels), `roles.js` (new callable
    `orgRoles`: list / save / delete; endpoint count now **35**), `team.js`
    (invite/accept/setAccess resolve the role in the transaction; an invitation
    gets the role's grants current at accept), `team_read.js` (myAccess returns
    effective grants + roleName; lists carry roleName), `booking_workspace.js` /
    `calendar.js` / `workspace.js` (create vs manage bookings, own-records
    filter), backdate checks in invoices / leases / roommates / lease dates,
    `account_deletion.js`, `organization_settings.js`, `organization_directory.js`,
    `request_security.js`, rules protect the new membership fields.
  - App: `TeamAccess` holds a role ID string + effective grants (TeamRole enum
    removed); Team > **Roles and permissions** screen (list, create from a
    template or blank, edit grid with Off / Own records / Their properties /
    All properties chips, delete when unused); role picker in access editor
    lists the organization's roles the account may give (falls back to the
    templates if the backend is older); role names shown on dashboard, team
    lists, invitations, workspace and activity; "Add booking" button follows
    `canCreate`.
  - Situations covered: (1) owner fixed, never assignable/editable; (2) nobody
    gives more than they have, or changes people/roles at or above their level;
    (3) a role manager cannot edit their own role (it has "manage roles");
    (4) two people editing one role → "changed by someone else", editor reloads
    with the latest; (5) rename shows everywhere at once, activity keeps the
    name at the time; (6) delete blocked while any active/suspended/waiting
    member or unexpired pending invitation uses it (checked in the
    transaction); deleted roles cannot be assigned or accepted; (7) retries /
    double taps: operation ledger + one save lock, retry button keeps the same
    operation; (8) unsaved changes → discard prompt on Back; (9) empty /
    loading / error+retry states; (10) waiting members, suspended/revoked,
    other organizations, closed and legacy organizations unchanged;
    (11) "own" lists filtered by the server with per-record canManage; (12) a
    grant set to All properties lists every property in the workspace;
    (13) starter roles can keep no name of their own (translated name shown in
    en/vi); names unique per organization, 1–40 characters; (14) narrow phones:
    permission rows stack label over chips, chips wrap; desktop: side by side.
  - Verified 2026-09-30 (automated, by Claude): backend unit tests **114/114**
    (17 access-policy incl. 8 new, 11 new roles tests: list/counts, fan-out,
    concurrent edit, retry/reuse, names, manage-roles delegation, delete in
    use/tombstone, invitation gets current grants, admin cannot assign a
    stronger role, closed/legacy). Updated: team test (unknown role names are
    now `team_role_not_found`), staging endpoint count 35.
  - Changes after Tom's review (2026-09-30): scope labels renamed ("Only bookings
    they created" / "Chỉ đặt phòng do người này tạo", "Their assigned
    properties"); per-person permission switches (Quyền tùy chỉnh) removed from
    Manage account access — old switches show a notice and are cleared on save
    (server still honours uncleared ones; no production v2 users have them);
    the "all properties" checkbox became a two-way choice "All properties,
    including ones added later" / "Only the properties ticked below";
    invitation screen lists what the role allows. First release bundling fix:
    `tool/staging_release.cjs` now packs `role_templates.json` (functions had
    crashed on start) and has an `all` command.
  - Live round 1 (2026-09-30, Tom): tests 1–10 run. Found and fixed: test 8
    "permission denied" was really "no room chosen" (seed room was long-term
    only) — server now says `booking_room_required`, form explains it, seed room
    takes short stays; test 11 showed the generic error because the web build
    reports callable reasons differently — new `serverReason()` helper
    (team_service.dart) matches message+details, used by roles, access editor
    and booking form; the "changed" notice now shows inside the reopened editor.
    Older screens still compare `error.message ==` exactly (staff_editor,
    room_rates, room_details, room_booking_settings, property_details,
    lease screens, ai_import) — same web risk, not yet changed.
  - NOT verified yet: `flutter analyze`, `flutter test --concurrency=1` (Flutter
    could not be downloaded in Claude's environment — Tom runs these),
    emulator tests (`npm run test:team:emulator`), rendered screenshots of the
    Roles screen (en/vi, phone/desktop, 130%/200% text), live staging.
- [x] **R2 Google sign-in and staff added by Gmail** — DONE: live staging tests
  1–10 passed 2026-10-01 (Claude drove the browser; Tom did the sign-ins).
  Found and fixed during the live run: join check ran once per page load
  (now once per sign-in); re-adding a Gmail created a second staff profile
  (now reused, and a re-added person gets their old profile back); invitation
  card showed the email twice; Gmail dialog said "Lưu quyền"; revoked
  invitations still said "waiting"; activity showed "Sự kiện nhóm" for the
  new actions. Not checked live: English labels, the add form at phone width,
  Android. Notes: staging screens take 8–15 s (cold functions); the access
  editor briefly shows "Tòa nhà không khả dụng: <id>" while buildings load;
  one leftover duplicate staff profile (S03) from before the fix in staging. Backend unit
  tests 122 (8 new in `team_gmail.test.js`; team test updated: a revoked
  person may now accept again). Endpoint count **36** (+claimMyInvitations).
  - Live tests (A owner test1, B test2, a real Gmail G you can sign in with):
    1. Firebase console (staging): enable Google sign-in. Login screen shows
       "Đăng nhập bằng Google" on web.
    2. As A: Team > Thêm nhân viên bằng Gmail: G, name, Lễ tân, one building.
       Staff list shows the new S0x; Review queue > invitations shows G
       "waiting for first sign-in".
    3. Same Gmail again → "already added".
    4. Sign in as G with Google (private window) → dashboard says "you were
       added to Staging Test Source" and the organization opens as Lễ tân with
       only that building.
    5. As A: add a typo Gmail, then Sửa Gmail to the right one before sign-in.
    6. As A: remove (revoke) a pending one → that Gmail signs in and joins nothing.
    7. As A: revoke G's access, add G again → G reloads and is back.
    8. A Gmail nobody added signs in → empty dashboard with "ask your manager
       to add <email>".
    9. Close the Google window halfway → no error; double tap → one window.
    10. Vietnamese + phone width for the login button and the add form.
  Decisions (Tom, 2026-10-01): Google sign-in on **web + Android** only for
  now (hidden on iPhone until Sign in with Apple is added; iPhone staff use
  the web app); a pre-approved Gmail waits **until used or removed** (no expiry).
  - Design:
    - Sign-in: "Đăng nhập bằng Google" on the login screen (web: popup,
      Android: Firebase provider flow; hidden on iOS and desktop). First Google
      sign-in creates the `owners/{uid}` profile from the Google name/email.
      Email/password stays for existing owners. Same email with an existing
      password account: Firebase treats Google as trusted for Gmail, so it is
      the same account (memberships kept).
    - Add staff by Gmail: Team > "Thêm nhân viên bằng Gmail": name, Gmail,
      phone (optional), role, assigned properties. One server action
      `addStaff` creates the staff profile (code auto `S01`, `S02`…) and a
      pre-approval (a `teamInvitations` record with `expiresAt: null`) in one
      transaction. Refused if that email is already an active member or
      already pre-approved in this organization.
    - Auto-join: new callable `claimMyInvitations`, called by the app after
      every sign-in (dashboard load). It finds pending pre-approvals for the
      account's **verified** email in every organization and accepts each with
      the same checks as accepting an invitation (inviter still allowed, role
      still exists, staff profile free). The dashboard then refreshes and says
      "You were added to X". Unverified email → told to verify; unknown Gmail →
      empty dashboard explains "ask your manager to add this Gmail".
    - Fix a typo: pending pre-approval → "Sửa Gmail" (`changeInvitationEmail`),
      or remove it (existing revoke). Removed staff re-added later: accepting
      now works over a revoked membership (old staff profile is unlinked,
      history kept).
    - Remove access: unchanged (revoke in Manage account access; every call
      re-checks the membership). Revoking the Google session itself needs the
      Auth admin permission — not in R2.
    - Old link/reference invitations keep working (7 days); the
      "Nhận lời mời" button stays for them.
  - Situations: same Gmail in two organizations (joins both); verified vs
    unverified email; typo fixed before first sign-in; re-adding a removed
    person; duplicate add (same Gmail twice); role deleted or inviter lost
    rights before first sign-in (skipped, owner sees it still pending);
    popup closed / cancelled; provider disabled in Firebase; offline; double
    tap on the Google button; legacy organizations (team features need v2).
  - Tom's Firebase setup (staging first): Authentication > Sign-in method >
    enable Google; Authorized domains include the staging site; for Android
    builds add the app's SHA-1/SHA-256 and download google-services.json again.
- [ ] **G8 v2 organization creation + migrate his organization** (from
  RELEASE_TASKS). Decisions (Tom, 2026-10-01): build v2 creation behind a
  release switch (on in staging; production once v2 has calendar and
  statistics); build and rehearse the migration tool now, migrate his
  organization later.
  - [x] v2 creation: `organizationSettings` action `create` (owner membership,
    invite code, activity, operation ledger so a retry returns the same
    organization; max 20 owned; costly rate limit). Server switch
    `V2_ORG_CREATION` in `functions/index.js` (staging only); client switch
    `ReleaseFlags.v2OrganizationCreation` (`lib/config/release_flags.dart`,
    on for APP_ENV=staging, or `--dart-define=V2_ORG_CREATION=true`).
    Production: flip both together.
  - [x] Migration tool `tool/migrate_v2.cjs` (plan with backup / apply /
    undo / anonymized rehearse into staging / rehearse-delete) and pure
    planner `functions/migration_plan.js`; tests `migration_plan.test.js`,
    `migrate_tool.test.js`. Usage in `tool/STAGING.md`.
  - [x] Staging rehearsal passed (2026-10-01): anonymized copies of both his
    organizations → plan (no blockers) → apply → checked in the app (Owner,
    17 rooms, rates, booking 3h = 300,000 VND, Team/Roles) → undo → apply
    again. Found and fixed: booking/payment/task lists showed internal room
    IDs (now room numbers); read-only bookings list used device time (now
    property time). New v2 organization live-tested 2026-10-01 ("Test v2":
    Owner, property, room, housekeeping task shows the person's name).
  - [ ] Both are his (Tom, 2026-10-01): "DAILYPLUS" (`KPujpC5twTi84nnuOskL`)
    and "Daily+ LNQ" (`dJTtpnTSbA4PXpBhOS0a`), each 1 property, each owned by
    a DIFFERENT account (`YYw3r8…`, `1Qkxtu…`), no staff yet. Migrate both.
    Open: keep two organizations (link the accounts as administrators) or
    merge into one after migration (v2 copy)? Tom: both are mostly test data.
  - [ ] Idea (Tom, 2026-10-01, after G8): anh Hưng puts the data exported from
    his other app into a Google Sheet; we read it, create the records in our
    app, and write a separate sheet in our app's format to a location he
    chooses. Not designed yet.
    → NEXT (Tom, 2026-10-05): this is the next feature. Needs a sample of the
    sheet (columns) before design.

## Order decided (Tom, 2026-10-05, evening)
1. Sheet import: read anh Hưng's Google Sheet, create everything in the app,
   write a new sheet in our format.
2. Staff management screen, with a new permission "Xem hợp đồng thuê" (view
   only: lease bars with names and paid state, no edit buttons). Calendar layers
   stay permission-based so custom roles work. No "Kỹ thuật" role (repairs are
   called in; "Đã sửa xong" records who fixed it).
3. Migrate every production organization to v2 and publish to production.
4. Building view: a Phòng | Tòa nhà switch in the calendar. One row per
   building; whole-building contracts as bars (thuê vào / cho thuê), monthly due
   marks, rent payments TRACKED (mark a month paid: amount, date, method, into
   Thu chi; bar solid up to the paid month, red when overdue). A building rented
   out whole: its room calendar shows a note ("Cả tòa nhà đang cho thuê đến …")
   with a link to the building view, rooms hidden, no room bookings.
  - [ ] Real migration — DECIDED (Tom, 2026-10-01): skip moving his
    organization now. After all planned work is finished: move EVERY
    production organization to v2 with the tool (needs a batch mode: plan
    all, review, apply all), turn on the v2 creation switch in production,
    then delete the legacy (v1) code paths and rules. Rehearsal copies were
    deleted from staging.

## Phase U — Screen redesign and navigation

- [ ] **U1 v2 organization screen redesign** (v1-style tabs/sidebar like his
  reference: Dashboard, Bookings, Rooms, Staff, Expenses, Reports, Settings,
  Cleaning schedule) with the NAV fixes from RELEASE_TASKS:
  - Addresses carry IDs (`/#/org/{id}/bookings/{bookingId}`) so reload stays
    on the same page; each screen loads its own data from the ID and checks
    access; clear message when access is gone or the organization closed.
  - Back (app and browser) goes one step back.
  - Menu items appear only when the role allows them.
  - Today (2026-10-01): the v2 organization is ONE widget (`RoleWorkspace`)
    that swaps ~12 sub-screens with on/off flags; a plain button list; the
    property dropdown is on the start page only; Back/reload leave the
    organization; every load also waits 3 s on the splash.
  - Decisions (Tom, 2026-10-01): phones use a bottom bar with Bookings,
    Rooms, Tenants, Money + "More"; Dashboard/Expenses/Reports hidden until
    built.
  - Step 1 live-checked on staging 2026-10-01 (Owner, "Test v2"): phone
    bottom bar + Thêm sheet, desktop sidebar, page tabs, address updates,
    browser Back room rates → list → organization list, reload on
    `money/invoices` reopens it. Tests 266 pass. Not yet checked live: other
    roles, 200 % text, landscape phone, a person with no properties.
  - Built (2026-10-01, step 1):
    `RoleWorkspace` is now the section shell (sidebar ≥ 900 px, bottom bar +
    More on phones, property picker + page chips on top); `OrgShell` page
    keeps the address `#/org/{id}/{section}/{page}?p={property}` (reload
    reopens it via the splash → dashboard → page, list underneath for Back);
    `BackSteps`/`BackStep` make app/Android/browser Back go one step back
    inside a section (room → list, booking → list, lease → list, role editor
    asks first); splash no longer waits 3 s; owner of a new organization
    lands on "create the first property". Old read-only bookings list
    dropped (the booking screen lists them).
  - Redesign (Tom 2026-10-01: "clean, professional, compact, like v1 or
    better, down to dialogs"): organization-colored top bar like v1 with the
    section tabs inside it when they fit (bottom bar otherwise); white strip
    with property + page tabs; `workspaceTheme` (compact 40 px buttons,
    bordered cards, chips, dialogs, snackbars) over the whole workspace;
    shared parts in `ws_ui.dart` (WsPage, WsHeader, WsBack, WsRecord with
    status pill + colored edge, WsBadge, WsEmpty, WsNotice). Converted: rooms,
    bookings, invoices, tenants, cleaning, staff list, money lists. Forms and
    the remaining sub-screens get the theme only (next pass if needed).
    Login: forgot-password link no longer turns grey while signing in; the
    spinner sits inside the button (no layout jump).
  - Step 2 (record addresses): `#/org/{id}/{section}/{page}/{record}?p=…` for
    an open booking, room or tenant; reload / shared link opens it; Back goes
    to the list and the address follows.
  - Design (2026-10-01):
    - Shell `OrgShell` for v2 organizations: top bar (organization name,
      property picker, account menu) + section menu. Wide screens (≥ 900 px):
      sidebar. Phones: bottom bar with 4 sections + "More". Legacy
      organizations keep the old screen.
    - Sections (each shown only if the role allows something in it):
      Bookings (manage / read-only list), Rooms (room list, layout, rates,
      booking settings), Tenants (contacts, leases), Money (invoices, payment
      actions, financial data), Cleaning (housekeeping tasks), Staff (team,
      roles, activity), Settings (property details, contract, create
      property, organization settings). Dashboard / Expenses / Reports appear
      when G4/E1/E2 are built.
    - One property picker in the top bar applies to every section and is part
      of the address. "All properties" combined views come with Reports.
    - Addresses: `#/org/{orgId}/{section}?p={propertyId}` and deeper pages
      `#/org/{orgId}/rooms/{roomId}/rates`, `#/org/{orgId}/bookings/{id}`.
      Reload opens the same page (the splash remembers the address and goes
      there after sign-in, with the organization list underneath so Back
      works). Each page loads its own data from the IDs.
    - Back: deeper pages are real routes, so app Back, browser Back and the
      Android back button go one step back. Switching sections replaces the
      page (no history per tap); Back from a section goes to the
      organization list.
    - Splash: no fixed 3 s wait; continue as soon as sign-in state is known.
  - Situations to handle:
    - Roles: owner, administrator, custom roles, "own records only", members
      limited to some properties, a member with no properties, suspended /
      revoked / waiting-for-role members (clear message + button back to the
      list), role changed while the page is open (next load re-checks; server
      always re-checks).
    - Addresses: unknown organization, organization of someone else, closed
      organization, property removed or not assigned, record deleted, legacy
      organization address, signed-out user opening an address (login, then
      return to it), malformed address.
    - Empty: organization with no properties (owner: create the first one),
      property with no rooms/bookings/tasks.
    - Loading and errors per page (cold start), retry button, offline.
    - Double taps on menu items, switching property while a page loads
      (older result ignored), unsaved form when leaving (existing forms ask?).
    - Layout: EN/VI, phone portrait/landscape, tablet, desktop, 130 % and 200 %
      text, light/dark, long organization/property names, many properties.

## Phase B — Bookings: short-term and long-term

Today: short-term bookings (hourly/overnight/daily pricing, one guest ID,
source walk-in/phone/app/online/other, deposit, payments) and long-term
tenants/leases (main tenant + roommates with CCCD, contract dates, monthly
rent, deposit) are separate. Invoices v2 support rent + charges (electricity,
water, internet, parking, maintenance, other) as unit price × quantity.

- Decisions (Tom, 2026-10-01): B1 starts from a "Đặt phòng mới" button
  (Ngắn hạn / Dài hạn) now; the calendar-cell tap comes with C1/C3. CCCD
  numbers need a new role permission "Xem số CCCD" (owner/administrator by
  default), others see them masked. Short-term keeps hourly / overnight /
  daily pricing next to the new per-night pricing.
- Design B1–B3 (2026-10-01, builds on what exists — no second booking
  system):
  - B1: Bookings section header gets "Đặt phòng mới" → small dialog
    "Ngắn hạn (theo giờ / đêm)" or "Dài hạn (theo tháng)" → the form, room
    prefilled when started from a room. Long-term opens the existing lease
    form (TenantLeaseScreen), extended for B3. Calendar-cell entry later.
  - B2 server (`booking_quote.js`, `calendar.js`, `booking_workspace.js`):
    - pricing type `nightly` beside hourly/daily/overnight: nights counted
      from the property's local check-in/check-out dates; default nightly
      price = room daily price; "same price every night" or a per-night
      list (`nightPricesMinor`, one per night). Editing prices needs the
      existing "Đổi giá" permission (overridePrices), like custom totals.
    - surcharges `[{label, amount}]` added to the total.
    - guests: main guest name/phone/CCCD (exists) + co-guests
      `[{name, idNumber}]`, `numberOfGuests`.
    - `staffId` (staff in charge, must be an active staff profile of the
      organization), `platform` (airbnb, booking, agoda, traveloka, direct,
      other), `contactChannel` (phone, zalo, whatsapp, messenger, other).
    - deposit: amount (exists) + note; deposit/payment commands take a
      receiving account (B8-lite: organization list of accounts + cash,
      edited in Cài đặt by people with "Cài đặt tổ chức").
    - CCCD: new permission `readGuestIds` (owner/administrator template
      default); projections mask numbers (•••• 1234) without it; audit
      never stores them (already the case).
  - B2 client: the booking form in sections — Khách (main + co-guests),
    Phòng & thời gian (nights shown live), Giá (hourly/overnight/daily or
    nightly: same price or per night), Phụ phí, Cọc, Phụ trách & nguồn,
    Ghi chú — with the server quote shown before saving; status names as
    anh Hưng uses them (Đã cọc – chưa nhận phòng / Đang ở / Đã trả phòng).
  - B3: extend the lease form: tạm trú registered (yes/no + date) per
    person, co-tenants with CCCD in the same form, staff in charge, payment
    period (every N months, due day, amount per period), deposit by
    transfer/cash + account. Electricity (B4) and service fees (B5) stay
    separate items.
  - Situations: price changed after quote (room revision check exists);
    nights changed after per-night prices typed (list resized, typed values
    kept for remaining nights, total re-quoted); overlapping booking/lease
    (server refuses, form says which); editing a paid booking (total cannot
    go below paid); deposit/payment over the amount; cancelled/no-show;
    staff profile removed; account removed from the list after use (old
    payments keep the label); CCCD hidden for roles without the permission
    and never in activity history; legacy (v1) bookings without new fields
    open fine; double tap = one booking (operation ledger); EN/VI, phone,
    200 % text.
- Built 2026-10-01 (B1 button + B2, waiting for tests/deploy):
  - Server: `nightly` pricing (property-local nights, room daily price as
    the default, per-night list needs "Đổi giá"; kept on edits while the
    night count fits), surcharges added on top, co-guests with CCCD,
    numberOfGuests, staffInChargeId (active staff profile; counts for
    "own records"), platform, contactChannel, depositNote. CCCD masked
    without readGuestIds; a left-out number keeps the stored one. The
    workspace passes its quote to calendar.js as a trusted context (the
    public callable cannot write surcharges/night prices). Payments record
    `receivedAccountId/Label`; organization `paymentAccounts` edited with
    the new `accounts` action (Cài đặt → Tài khoản nhận tiền).
    Tests: functions/test/booking_details.test.js, organization_settings.
  - App: "Đặt phòng mới" → Ngắn hạn / Dài hạn (long stay opens the lease
    form) → sectioned form (Phòng và thời gian with date pickers and live
    night count, Khách, Giá, Phụ phí, Tiền cọc, Phụ trách và nguồn), quote
    card, fixable refusals keep the form (conflict, staff gone, changed),
    detail view in sections, payments choose "Nhận vào" (cash / account).
    Status names: Đã cọc – chưa nhận phòng, Đang ở. Test:
    test/booking_form_test.dart.
  - Next: B3 lease form; form polish for the other pages.
- B3 built 2026-10-01 (waiting for tests/deploy): the lease form
  (Dài hạn) in sections — Phòng; Người thuê chính with CCCD and tạm trú
  (yes + date); Người ở cùng (up to 10, each with CCCD and tạm trú, created
  as roommates in the same transaction); Hợp đồng và thanh toán (rent
  prefilled from the room price, every 1/2/3/6/12 months, due day, amount
  per period defaulting to rent × months); Tiền cọc (amount, cash or an
  organization account, note); Nhân viên phụ trách. Server: new optional
  fields on tenant_leases `create` (old app versions unchanged), staff and
  account checked, no CCCD in activity history. Tests:
  functions/test/tenant_lease_details.test.js, test/lease_details_test.dart.
  Not yet: showing/editing these details on the tenant page (with CCCD
  masking), and CCCD/tạm trú when adding a roommate later.
- Live check 2026-10-01 (staging, Test v2): whole short-stay flow works
  (2 nights 500k+600k + 150k surcharge = 1,250,000; deposit into an
  account → "Đã cọc – chưa nhận phòng"). Found and fixed: stale icon font
  cached for an hour after deploys (hosting now revalidates assets), header
  buttons centred, hint text looked like values, refund buttons with nothing
  paid, amount not prefilled, redundant "Mở". Grey (slate) theme added as
  the default (Tom). Design notes for the polish pass:
  - Older forms (room prices, property details, invoices, leases) still use
    full-width buttons and plain layout; move them to WsSection/WsActions.
  - Dropdown values are bold (app theme) — lighter weight.
  - Booking detail: too many equal buttons; make the next step primary
    (Nhận phòng / Thu tiền) and put the rest in a "…" menu.
  - Accounts page: section title repeats the page title.
  - Opening an organization right after a deploy takes ~15 s (cold start);
    show a friendlier loading state.
  - Top-corner gaps: waiting for Tom's screenshot (not found in code).
  - B4 live check (2026-10-02): at 200% text the property name in the top
    bar is cut with "…" and the "Sơ đồ tòa nhà và mặc định phòng" chip runs
    off the screen; chips/small buttons have almost no padding at 200%.
    English money shows "VND3,500" (prefer "3,500 VND"). Tariff "Use
    property default" is unticked while the room uses the property price
    (unclear). Room list "Tải lại" repeats the refresh icon; Edit room
    details uses full-width buttons and a "Reload room details" button.
    Settings menu item "ngôn ngữ" starts lowercase. Room list on a 375px
    phone: rental-mode pill cut to "Cho thuê theo th…".
  - Done 2026-10-01 (design pass 1): tenant page = one place per tenant
    (header with room + status + "Ở cùng …", Giấy tờ with CCCD masked
    without "Xem số CCCD" and tạm trú, Hợp đồng with dates/rent/period/
    deposit/staff, Liên hệ edit, then the lease actions); list rows are
    tappable with "Phòng 101 · phone" and "Ở cùng Le Van Chinh" (no IDs);
    "Thêm người thuê"; shorter lease help; lease form stays visible when the
    room is busy and offers "Xong" after saving; back link says "Đặt phòng"
    from Bookings; booking detail: one filled next step (Nhận phòng / Trả
    phòng), cancel/no-show/refunds under "…", "Đóng" instead of "Hủy",
    no "Còn phải trả" on cancelled bookings; dropdown values regular weight;
    accounts card titled "Danh sách tài khoản".
  - B3 live check (2026-10-01, Test v2, grey theme): lease with co-tenant,
    tạm trú, 3-month period, due day 5, 5,000,000 deposit into an account
    saved; both people listed. Room busy with a booking → clear message.
    Notes for the pass: after "room busy" the form disappears (typed values
    are kept, but the form should stay visible with the message); after a
    successful save the page is empty except the message (go back to the
    list, or offer "Xem người thuê"); lease page help text is too long;
    back link says "Người thuê" when opened from Bookings; staff section
    title repeats the field label; tenant list shows internal IDs ("Người ở
    cùng của mã người thuê: lease_…", "Mã tham chiếu phòng") and too many
    long buttons per row — show "Ở cùng Le Van Chinh" and move actions to a
    detail page / "…" menu; "Thêm người thuê / Bắt đầu hợp đồng" →
    "Thêm người thuê"; "Làm mới người thuê" duplicates the refresh icon.
    Booking: a cancelled booking still shows "Còn phải trả"; in the cancel
    panel the "Hủy" button next to "Xác nhận" is ambiguous ("Đóng").
- [ ] **B1 Choosing the kind**: tap an empty calendar cell → "Long-term" or
  "Short-term" → the matching form, with room and start date prefilled.
  Room already taken → explain, no form.
  - [x] Delivered core entry: Bookings → New booking → short-term or long-term form (2026-10-01).
  - [ ] Remaining: empty-calendar-cell entry with room/date prefilled and occupied-cell handling. The parent stays open for this original scope.
- [ ] **B2 Short-term booking form** (his page "Ngắn hạn")
  - [x] Core booking form implemented and deployed; implementation and verification evidence is recorded above.
  - [ ] Remaining dependencies: payment push notifications (N1), technical-problem flag (B7). Restricted-role CCCD masking, active-booking check-in and English/mobile/large-text live checks remain on the verification list; prior automated checks are separate.
  1. Price: (a) same price every night: nights × nightly price = total;
     (b) price per night: Night 1, Night 2… editable, add more nights.
  2. Deposit: amount, transfer date, note. Surcharges (phụ phí) as lines.
  3. Payments: date, amount, received into (bank account from the
     organization's list, or cash), note. Each payment sends a push
     notification (N1) and appears on the collections list.
  4. Staff in charge of the guest (from staff list).
  5. Main guest name + CCCD; co-guests with CCCD; total guests.
  6. Room. 7. Check-in / check-out; nights counted automatically; check-out
     time shown on the bar.
  8. Status: Deposit paid–not checked in / Staying / Checked out
     (+ cancelled / no-show kept). Technical problem flag (B7).
  - Optional: booking platform (Airbnb, Booking.com, Agoda, Traveloka,
    direct, other) and contact channel (phone, Zalo, WhatsApp, Messenger…).
  - Situations: nights changed after per-night prices entered; overlapping
    booking; editing a paid booking; refunds; currency; timezone of property.
- [ ] **B3 Long-term booking form** (his page "Dài hạn") — builds on leases
  (absorbs G3 tenant profile)
  - [x] Core lease form implemented and deployed; live check confirmed co-tenant, temporary residence, payment period/due day and deposit (2026-10-01).
  - [ ] Remaining dependencies: electricity/water (B4), service fees (B5), technical problems (B7), and expiry reminders. These keep the parent open; the completed core form does not need rebuilding.
  1. Room. 2. Main tenant (on contract) + CCCD + **temporary residence
     registered? (tạm trú)**; co-tenants + CCCD + tạm trú; total people.
  3. Staff in charge. 4. Lease term from → to.
  5. Payment period: every N months, due day, amount per period.
  6. Monthly room price. 7. Electricity (B4). 8. Service fees (B5).
  9. Deposit: amount, transfer or cash. 10. Status (same as short-term) +
     technical problems.
  - Situations: renewing, ending early, changing price mid-lease (existing
    rent-change flow), moving room, partial periods, reminder before tạm trú
    or contract expiry.
- [x] **B4 Electricity (and water) meter readings** — DONE on staging, accepted
  by Tom 2026-10-02; individual invoice per measured interval (period
  aggregation is B6). Price per kWh per room
  or property; a reading each month with its date; usage = this reading −
  previous; cost = usage × price; readings go into the period invoice.
  Situations: meter replaced/reset, reading lower than last, missed month,
  tiered electricity prices (Vietnam EVN tiers) as an option.
- [x] **B5 Service fees** — DONE on staging, accepted by Tom 2026-10-02
  (SERVICE_FEES.md; one invoice per fee — combining is B6): (a) flat per room, (b) flat per person (uses the
  number of people), (c) extra services charged separately (shared washing
  machine, parking per vehicle, internet, cleaning…). Defined per property
  with defaults per room.
- [ ] **B6 Period invoices (long-term)**: one invoice per payment period that
  combines rent + electricity + water + service fees + surcharges; also:
  rent only, utilities billed separately, prorated first/last month,
  discounts, late fees, deposit deducted at move-out, manual extra lines.
  Shows paid / partial / overdue; partial payments allowed.
  - [x] B6a period invoice: rent + fees ahead, unbilled readings behind, manual
    late fee / discount (VND or %) / damage / other lines, prorated partial periods,
    overdue status, no double billing (refused at Review). Accepted 2026-10-02.
  - [x] B6b move-out settlement: unpaid charges + damages − deposit → refund or
    amount still owed; optional credit for rent and for service fees paid ahead;
    keep part of the deposit; move out first and settle later. Accepted 2026-10-03.
- [ ] **B7 Technical problems (sự cố kỹ thuật)**: optional per room or
  booking: description, photo, reported by/at, cost, who fixed it, status
  (open / fixed); option "room unavailable while open" which blocks new
  bookings for that room.
  - [x] B7a problems: report (any staff), block new bookings/leases/room moves
    while open (existing ones listed as a warning), edit, mark fixed with who/when/
    cost and optional paid expense in Thu chi, reopen with a reason. Accepted
    2026-10-03 (TECHNICAL_PROBLEMS.md).
  - [ ] B7b photos saved in the owner's Google Drive (needs Tom's Google Cloud
    OAuth setup).
- [ ] **B8 Payment receiving accounts**: organization list of bank accounts +
  cash, chosen on each payment; totals per account.

## Phase C — Calendar

Started 2026-10-03 as the first of two main screens (Calendar + Staff management),
built, local tests pending — see [CALENDAR.md](CALENDAR.md). B7b local check is paused meanwhile.

- [ ] **C1 Booking bars** (his sketch)
  - Guest name at the start; contact icon; platform logo if set.
  - Paid part filled solid up to the date paid (short-term: "paid until
    4/9"; long-term: by payment period T, T+1, T+2, next period empty).
  - Check-out time at the end (e.g. 11:30); status icon (deposit / staying /
    checked out / technical problem).
  - Colour = kind (short-term / long-term / deposit only); dot = payment
    (green / red / orange).
  - Not needed: number of cleanings on the bar.
- [ ] **C2 Year / multi-month view** like the Airbnb screenshot (month grids,
  bars across days, "Today" button, switch week/month/year). Absorbs G5.
- [ ] **C3 Room timeline** (rows = rooms, columns = days) like his reference
  web app, with filters by property/status.

## Phase S — Staff performance, notifications, data safety, money

- [ ] **S1 Commission and KPI** (needs the open answers): commission % per
  staff (maybe long/short separately); report per staff per month: nights
  sold, long-term contracts, commission amount; export for payroll.
- [ ] **N1 Push notifications** (Firebase Cloud Messaging): new payment,
  deposit, booking created/cancelled, check-in/out today, overdue invoice,
  technical problem. Per-user settings. iOS needs the APNs key from the Apple
  developer account; web shows browser notifications while the browser runs
  (iPhone web only when installed to the home screen).
- [ ] **D1 Google Sheet/Drive backup**: owner connects their Google account;
  the app keeps a Sheet in their Drive updated (bookings, tenants, payments,
  expenses) one way. Also scheduled Firestore backups on our side.
- [ ] **E1 Expenses (chi phí)** per property (exists partly as expense
  payments): categories, receipts, who paid; investors can view their
  properties' expenses only.
- [ ] **E2 Reports** (absorbs G4/G6): revenue, occupancy, expenses, profit
  per property and month; investor-limited view; export PDF/Excel.

## Kept from RELEASE_TASKS (not repeated here)

G3 → B3, G4/G6 → E2, G5 → C2, G7 (AI tools for v2) and G8 stay in
RELEASE_TASKS.md and are linked above.

---

## Current test list (PROFILE / STAFFLINK / NAV), 2026-09-29

A = test1 (owner), B = test2 (receptionist), C = test3 (waiting). Deploy the
backend (35 functions since R1) and web first, then reseed:
`node tool/staging_seed_v2.cjs delete` then
`node tool/staging_seed_v2.cjs create --owner trinhhungqt2004+test1@gmail.com --staff trinhhungqt2004+test2@gmail.com --waiting trinhhungqt2004+test3@gmail.com`.

Passed: 1 gear hover, 2 Personal information opens, 3 name and phone.

4. As B change name; as A, Team list shows the new name.
5. Change password checks: wrong current, `12345` too simple, mismatch, same as current.
6. Real password change, sign out, sign in with the new one.
7. Change email checks: current email, email of another staging account.
8. Real email change: link, sign in with the new email; A's Team list shows it.
9. Vietnamese + phone width for all three dialogs.
10. Forgot password with an unknown email: same message, no email.
11. Forgot password with a real email: link works, sign in with the new password.
12. Signed in: Change password → "Email me a reset link" → green note, email arrives.
13. Vietnamese app → reset email in Vietnamese.
14. As A, Hồ sơ nhân sự shows B as S01.
15. As A, give C a role → C appears in Hồ sơ nhân sự as ACC-XXXXXX; change again → still one C.
16. Open an organization, press F5 → dashboard, not a white page.
17. Two tabs, sign out in one → the other goes to login.
18. No Back arrow on the dashboard after sign-in or on login after logout.


## Staff account restrictions — awaiting deployment and live approval
- [ ] Owner/staff account separation; staff go directly to their work area.
- [ ] One employer per staff email. Additional organizations require the same owner.
- [ ] `Phân công nhân viên sang tổ chức khác` in Vai trò và phân quyền: off for all non-owner templates. Owner alone can grant it; delegate must have it in both organizations. Server rechecks current authority.
- Implementation and verification are tracked in [STAFF_ACCOUNT_POLICY.md](STAFF_ACCOUNT_POLICY.md). Do not mark delivered until deployed/live-tested and Tom approves.
- AI chat/subscription removal is planned separately in that document. No removal performed.

### Revised direction after the stricter policy implementation
- [ ] Co-owners with an agreed, configurable permission list (Tom's choice), including sensitive ownership actions; not automatically full access.
- [ ] Explicitly approved staff sharing between separate companies, with separate roles/data access and revocation.
- Current single-owner/different-owner denial is an intermediate implementation. Hold its release until this revised model is settled. Agreement acceptance, joint approval and recovery details remain design work; see STAFF_ACCOUNT_POLICY.md.
