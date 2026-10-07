# Organization page spacing and repeated controls

The organization shell already supplies Back and Refresh. The agreements screen
also supplied an AppBar, causing the duplicated arrows in the reported screenshot.
Its centered 900 px body, and 720–960 px limits on other pages, left large desktop
gutters. Regression tests reproduced both defects before implementation changed.

Embedded organization pages now use the available width with their existing
16 px padding. A workspace scope applies this consistently to shared page bodies
and property, room, tenant, staff, role, activity, utility and payment forms.
Standalone pages retain their existing width constraints. Agreements suppresses
its toolbar when embedded. Staff, room directory, tenant directory and housekeeping
omit their redundant general refresh action inside the shell.

Detail-to-list Back, filter application, write retry, conflict recovery and status
checking remain: these actions have specific behavior beyond shell navigation.
The shell refresh rechecks access and recreates the current page.

## Situations and verification checklist

- Roles: owner, manager, receptionist and other restricted roles; suspended or
  revoked access; another organization. No grants, server checks or data formats
  change. Existing workspace role and lost-access tests cover client behavior;
  this change does not constitute fresh backend authorization verification.
- Loading, empty, failure and populated lists: existing regression tests plus
  populated embedded page fixtures. Error retry controls remain available.
- Retries, interrupted writes, double taps and simultaneous actions: existing
  write regression coverage remains. No write logic changes. Agreement retry
  test checks identical requests and double-tap blocking.
- Legacy v1 organizations: legacy screens are unchanged. Shared team screens
  outside the organization scope retain their width and refresh controls.
- Every touched field/button: only layout constraints and redundant general
  refresh controls change; editing, filtering, submit, cancel, detail navigation,
  conflict reload and recovery actions remain. General shell reload can reset
  drafts as before; no new draft persistence is claimed.
- English/Vietnamese, narrow phone, desktop, phone landscape, 100/130/200% text:
  new populated embedded matrix covers staff, activity, housekeeping, property,
  contract and property layout. Existing agreements matrix covers permission
  forms and long names. Existing workspace matrix covers both themes.
- Visual review: actual Roboto and Material Icons screenshots are generated for
  English desktop and Vietnamese narrow phone at 200%. Review results below.
- Calendar: calendar-specific code/layout is unchanged.

## Results

Full Flutter suite: 421 passed, sequentially with `--concurrency=1`.
Direct Dart analysis of team screens and the changed tests: no errors or
warnings (eight informational style notices). The Flutter analyzer wrapper
stalled without output, so the direct SDK analyzer was used.
After refining the screenshot fixture to open each page directly and assert its
screen type, all 12 workspace tests passed again. The populated matrix covers
108 page/locale/size/text-scale combinations without layout exceptions.
The desktop regression asserts wide page bodies and a single refresh icon.

Inspected 12 rendered workspace screenshots (six pages, English desktop and
Vietnamese 320 px/200%) and agreement desktop/phone permission screenshots.
Page bodies and headings render in actual Roboto and use the available width.
Some workspace buttons/chips still render with the test engine's Ahem block font;
registering Roboto under that fallback name did not replace it. Their actual-font
visual verification remains incomplete. Existing narrow/large-text housekeeping
record truncation and the shell property-name ellipsis remain separate issues.
The screenshot review is not a claim that every control or UI state is correct.
Logs: `.dart_tool/organization-layout-tests.txt` and
`.dart_tool/organization-layout-render-tests.txt`.
No deployment or live browser verification has been performed for this change.
