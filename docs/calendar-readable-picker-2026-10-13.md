# Readable timeline and current-property editing

## Situations to cover

- Narrow phone, landscape and desktop; English/Vietnamese; 100/130/200% text;
  embedded and standalone calendars, actual fonts and light/dark themes.
- Hours remain readable at small day widths. Label density can decrease while
  the two-hour booking slots and visible date range remain unchanged. Current
  time and hover indicators must remain aligned with the grid.
- Empty/occupied/blocked rooms, lease badges, hourly prices, long room/tenant
  names and defensive overlapping-booking fixtures retain their existing tests.
- Selected building is separate from alternatives, not duplicated as an option.
  Edit opens existing building pages; create remains a tooltip-only plus.
  Many properties scroll while the selected building and actions remain visible.
- Existing manage-property/building-scope permissions determine edit visibility;
  no rights means no edit. Single-building users with rights still get the menu.
- Existing details/lease/defaults/fees form validation, save refresh and deletion
  refresh remain in use. Opening menus writes nothing; dismissal is reversible.
- Loading/error/empty states, stale property responses and legacy v1 behavior are
  unchanged. Server membership, suspension, revocation and organization checks
  remain authoritative; this change adds no backend writes or authorization rules.

## Evidence

- Small-window regression failed before the change because painted hour text was
  7.37 logical pixels high. It now requires at least 12 pixels.
- Targeted calendar tests: 48 passed, including 60 populated locale/size/text-scale/
  embedding cases, selected-property navigation and 60-property scrolling. Final
  hover, permission and render checks also passed. Full sequential suite: all 993
  tests passed (.dart_tool/calendar-readable-full.txt).
- Rendered and inspected actual-font phone timeline at 200% and property picker
  on phone/landscape. These are synthetic widget fixtures, including inconsistent
  overlapping bookings for defensive rendering coverage; no live bookings created.
- Analysis: no errors or warnings; six informational notices (existing style and
  deprecated semantics-test APIs). No new server security audit or physical-device
  checks.
- Wasm build and staging Hosting deployment succeeded. Live browser check confirmed
  main.dart.mjs execution, 390px readable timeline, pencil opening the selected
  property's four authorized settings tabs, and 800x360 menu alternatives scrolling
  to the last building while the current building, edit and add controls stay visible.
  No building information was saved. Screenshots: live-readable-phone.png,
  live-property-edit-phone.png and live-property-edit-landscape.png under
  .dart_tool/calendar-spacing/.
- Resizing while a popup is already open retains its opening size; its outer
  scroll keeps content reachable, but the heading can scroll until reopened.
  Freshly opened menus at each tested viewport keep the selected row fixed.
- Production unchanged. Safari/Firefox fallback execution not retested.
