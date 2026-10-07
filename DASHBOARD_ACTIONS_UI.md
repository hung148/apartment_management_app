# Dashboard organization actions UI

Requested change: invite, join, create and co-ownership/sharing are one icon-only group with existing localized labels as tooltips. All screen sizes keep actions alongside the heading in the same row. Order: handshake, invitation, join, create. Buttons are 40px with 18px icons and 4px gaps. At narrow widths with enlarged text the full heading wraps within its column; buttons stay together. Settings stays in the app bar. Empty-state join/create shortcuts are also icon-only. No translation or protected shared/server files were edited by this task.

## Situations and evidence

- Owner/new account, create allowed or denied: automated component matrix verifies create visibility for both values. Dashboard retains AccountEntryGate and the server-provided canCreate flag. Staff, suspended/revoked accounts, conflict accounts and other organizations still use existing gates and server authorization; live authorization was not rechecked.
- Populated organizations, long English/Vietnamese names and role badges: synthetic populated component fixtures checked. v1/v2 records use the same action header; organization data paths were not changed. Whole-dashboard legacy/v2 integration was not tested live.
- Loading/error/empty organizations and missing owner: existing dashboard state builders remain; empty-state shortcuts changed to icon-only. Existing invitation regression covers loading, empty, error, expired/unavailable invitations, denial, retries and private-record clearing. Full dashboard loading/error/empty renders remain unverified.
- Invite navigation and return refresh retained, join/create retain dialog lock; relocated sharing now uses the same lock and still refreshes account entry on return. Automated callbacks and stable button bounds checked. Existing invitation tests cover acceptance retries. Rapid repeated invite navigation, interruptions and simultaneous account changes were not newly exercised.
- Every touched control: invite/mail, join/group-add, create/plus, sharing/handshake, organization heading and empty-state join/create. Settings is the only app-bar action. No data writes or permission policies were changed.
- Automated layout matrix: English/Vietnamese x 360x800 phone, 800x360 landscape and 1200x800 desktop x 100/130/200% text x light/dark x create allowed/denied (72 combinations). Verified localized tooltips, reachable 40px targets, full heading, callbacks, tooltip display, stable positions and no Flutter layout exceptions.
- Rendered visual inspection: actual Roboto and Material icon fonts, app light theme, Vietnamese 360px/200% and English desktop/100%. Screenshots in `.dart_tool/dashboard-ui/`. These are component fixtures, not full dashboard screenshots. Dark, landscape and other scales have automated layout checks only. Live app, keyboard/screen-reader use, reduced motion and server checks remain unverified.

Validation: dashboard action matrix passed; existing team_review_test.dart passed 9 tests. This is a dashboard-local layout change with an opt-in invitation presentation; no full regression suite was run.

Final targeted Flutter analysis: no issues found. Diff whitespace check passed.

## Requested correction

Regression reproduced before implementation: the new 40px size assertion failed because the old controls were 48px. Added persistent assertions for order, same-row vertical alignment with the heading and compact size. The full 72-case matrix and existing invitation regressions passed after correction. Actual-font light-theme English desktop and Vietnamese narrow-phone/200% renders inspected: no clipping or hidden buttons; the 200% phone heading wraps onto four lines to preserve its full text while keeping actions beside it. Full dashboard/live checks remain unverified. The requested compact controls use 40px hit areas, below the 48px Material touch-target recommendation.

Update (Tom, 2026-10-02): the empty-state join/create shortcuts were removed; they duplicated the header buttons beside the heading, which stay visible when there are no organizations.
