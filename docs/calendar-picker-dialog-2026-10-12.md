# Calendar property menu and rental chooser

User request: put the create-property + beside the picker heading, with tooltip
instead of text; keep long lists within the viewport and scroll their overflow;
replace empty-cell bottom sheet with rental-choice dialog, no cancel footer.
Defer report-problem and assign-cleaning navigation in CALENDAR_HIDDEN.md.

## Situations and scope

- Property creation keeps the existing access check. Rental options follow
  canCreateBookings/canLease and room shortStay/monthly settings. Blocked rooms
  show the existing warning and disable both choices. No authorized rental
  action shows the existing no-action notice. Missing time zone still blocks.
- Owner/admin/manager and custom permissions use the existing projection; revoked,
  suspended and foreign access enforcement is unchanged on the server. No data
  writes added by opening/dismissing either overlay; no backend changes.
- Empty/loading/error property states retain existing notices. Property selection
  retains stale-response guards and refresh behavior; menu closes before creation.
- Close icon, barrier, Escape/Back use normal dialog dismissal. Rental selection
  closes the chooser before opening the existing form. Selected room/day/two-hour
  slot now supplies the short-stay start; checkout remains next day at noon.
- EN/VI; desktop, 320px phone, 800x360 landscape; 100/130/200% text; embedded and
  standalone; long room/property names, occupied/empty/blocked rooms, hourly
  stays, lease badges and inconsistent overlap fixtures remain in layout tests.
- Legacy v1 calendar and hidden building-wide booking toolbar are unchanged.
  Report/cleaning removed only from this empty-cell chooser; existing problem
  details and cleaning bar navigation are preserved for later navigation work.

## Evidence

- New retained dialog regression failed before implementation: centered dialog
  absent while old bottom sheet was present.
- Targeted calendar suites: 46 passed; expanded tests additionally pass all54
  dialog locale/size/scale/scope combinations and 60-property scrolling checks
  including EN/VI narrow phone and landscape at200% text. Last property reachable;
  plus button visible initially; menu bounds within viewport; no layout exceptions.
- Verified create-property form opens via tooltip-only +, blocked choices remain
  disabled, unauthorized lease option absent, and short/long forms receive room
  and date (short start receives the selected hour).
- Actual-font desktop dialog render inspected. Test screenshot contains synthetic
  inconsistent bookings for defensive display coverage, not live saved bookings.
- Focused analysis has no errors/warnings, only four pre-existing style notices.
- Full sequential Flutter suite: all 991 passed before the final menu accessibility
  correction. The heading now uses its own PopupMenuEntry so the + is an enabled,
  independently actionable semantic button. Three targeted menu tests and the
  explicit enabled-button/tap semantics regression passed after that correction.
- Final `--wasm` build and staging Hosting deploy completed on 2026-10-13.
  Browser logs confirm execution from main.dart.mjs. Final live interaction checks
  were blocked by Firebase App Check's reCAPTCHA error and the workspace access
  retry screen, including after a normal reload. Do not count this as a successful
  live menu/dialog check. Evidence: .dart_tool/calendar-spacing/staging-access-check-blocked.png.
- No fresh backend security, physical-device or Safari/Firefox fallback execution
  checks for this UI change. Production was not deployed.
