# Wider two-hour cells

Tom chose roughly six desktop days after discussing the width/day-count tradeoff.
Desktop calendars now divide their available timeline width by six, instead of
seven. Below 700px calendar width, days are at least 336px wide (28px per two-hour
cell); users scroll horizontally for the rest. Room-column width is unchanged.

## Scenarios and validation

- EN/VI, phone/landscape/desktop, 100/130/200% text, standalone/embedded, actual
  fonts and representative light/dark renders; occupied/empty/blocked rooms,
  lease badges, long names, hourly prices and defensive overlap fixtures.
- Booking times remain two-hour cells; bar positions, hover, current time,
  selecting a date/time, horizontal scrolling and month navigation must agree.
- Existing loading/error/empty states, building selection/edit, role visibility,
  legacy data, server authorization and concurrent-write protections are unchanged.
  No new data writes, retries or authorization paths are introduced.
- Six-day regression failed against the seven-day implementation. Wider cells
  exposed a lease-end bubble overflow at 320px/130%; retained regression reproduced
  it before constraining that label to its available bubble width.
- All 50 targeted tests and all 994 full-suite tests passed, sequentially. Actual-font
  phone (200%) and desktop renders inspected; bubble labels truncate at readable
  size instead of shrinking. Static analysis: no errors/warnings, six existing
  informational notices. No fresh backend
  security audit or physical-device/browser-fallback checks planned for this layout.
- Wasm build and staging Hosting deployment completed. Live 1440x900 desktop
  shows approximately six days; 390x844 phone shows wider cells and horizontal
  scrolling moves dates and updates the month heading. Runtime logs confirm
  main.dart.mjs; no browser warnings/errors recorded during the check. Cell-to-time
  selection is covered by widget tests, not confirmed in this live check.
- Live screenshots: .dart_tool/calendar-spacing/live-six-desktop.png and
  live-six-phone.png. Production unchanged.
