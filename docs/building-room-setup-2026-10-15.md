# Combined building details and room setup — 2026-10-15

## Scope

The calendar building dialog now has Details, Lease and Service fees. Building
layout/defaults live inside Details, with the same shared room setup on Create
building. Floors, prefix, room type, area and room counts are entered once.
Uniform or custom per-floor counts/types/areas generate editable draft rooms.
Shared optional prices apply to the generated drafts; each draft can be renamed,
edited or removed before saving. No existing room is regenerated or modified.

Save sends building details, optional defaults and the draft rooms in one server
transaction. Existing clients may omit the new fields. The new-room batch limit
is 200 per save; saved building layouts can describe more rooms. Prices on
new rooms use the selected currency, while existing building cost and room data
retain their own currencies. The legacy v1 organization flow remains intact.

## Situations to cover

- Authority: owner, administrator, manager (including assigned buildings),
  receptionist, accountant and housekeeper; suspended/revoked membership;
  cross-organization building IDs; v1 organization rejection by the v2 endpoint.
  Server rechecks manageProperty, building scope and overridePrices, including
  retries. Create-building still requires all-building scope.
- Data: absent old defaults, blank optional address/type/area/prices, zero rooms,
  uniform and mixed floor counts, ground floor, prefixes, custom room names,
  per-floor overrides and reopen, room removal, duplicate draft/existing names
  (server Unicode normalization), invalid counts/area/prices and 200-room limit.
- Writes: one atomic save for details/defaults/rooms; exact lost-response retry;
  changed retry rejected; stale revisions; concurrent combined/single room
  creation; currency change before save; no changes to existing rooms/history.
- States: loading and read failure/reload; uncertain-save lock and retry;
  duplicate rejection retaining drafts; revoked-save clearing private fields;
  late replies after a different building opens; optional room generation;
  cancel/delete confirmation and nonempty-building rejection.
- Touched inputs/actions: name, address, timezone/picker, operating cost, floor
  count, prefix, room type/area, uniform/custom switch, per-floor counts/type/area,
  starting floor, shared prices, Generate, Add room, draft fields/remove,
  Save/Retry/Reload/Delete. PropertyLayout's older standalone route still works;
  room creation elsewhere still reads top-level building type/area/prefix.
- Layout: EN/VI, 320px phone, 812x375 landscape, 1440px desktop, 100/130/200%
  text; populated custom floors, long names, prices and validation; light/dark.
  Shared calendar entry points retain permissions and use the merged Details tab.

## Regression development

- Initial combined-endpoint tests failed before implementation (missing room
  permission projection and unsupported combined payload). They then passed.
- Invalid custom floor count 201 reproduced a RangeError with a retained widget
  regression before the guard/render bound fix.
- Initial widget passes exposed feedback being disposed offscreen in the lazy
  property list. Replaced it with a non-lazy scrolling column and feedback near
  actions. Existing old tests' scroll helper was updated for the longer form;
  assertions on save/retry/denial remain.
- Updated tests for the intentionally removed Defaults tab and availability of
  Add room during edit. Old generator tests retain shared-price, renamed-room,
  duplicate, ground-floor, limit and responsive coverage with the new controls.
- Final targeted, full-suite, emulator and visual results are recorded below.

## Limits / behavior to retain

- A batch is generated explicitly and then reviewed; editing defaults afterward
  does not overwrite already edited draft rooms. Only the listed drafts are saved.
- Closing the dialog or switching tabs still discards unsaved page-local edits,
  matching the existing dialog navigation behavior. A pending retry must be
  resolved before starting a different save in the same form.
- Physical-device keyboards/screen readers and the full localhost Auth/functions
  browser stack have not been verified in this change.

## Final verification and existing-room follow-up

- Full sequential Flutter regression: 1,047 passed. Full server suite: 471 passed.
  Analyzer gate passed (pre-existing style infos/warnings remain).
- Real Firestore emulator: 2 combined-save tests passed, including concurrent
  exact retries and contention with single-room creation.
- Actual-font EN desktop and VI320/200% custom-floor screenshots inspected;
  light/dark creation-dialog screenshots inspected. Responsive widget matrices
  cover EN/VI, phone/landscape/desktop, 100/130/200%, generated rooms and saves.
- Initial version deployed to staging successfully; production untouched.
- User follow-up: Edit building must also display existing rooms. Missing list
  reproduced by a failing widget test, then added above shared room setup using
  the existing permission-checked, paginated room-directory endpoint. Read-only
  names/type/area do not become creation drafts. Save/reload refreshes inventory.
  Pagination failures clear stale data and offer retry. Create form omits list.
- Existing-list focused tests: 31 passed; live list verified in the synthetic org.

## Lower-usage room batches (user request)

- Chosen approach: one atomic request for up to 200 rooms rather than four
  50-room calls. Keeps room-by-room history, permission checks, normalized
  duplicate-name checks, revision checks and idempotency.
- Removed one explicit target-document read per new room in both building and
  bulk-room saves. Firestore transaction create preconditions prevent overwrite;
  a collision aborts the entire commit and maps to already-exists.
- Corrected the fake Firestore to preflight write existence constraints before
  applying any writes, matching real atomic commits. Retained collision rollback
  assertions and added a real-emulator collision at the last of 200 room IDs.
- Instrumented unit tests assert 200 rooms, no target reads and exact retry.
  This reduces read/call overhead; it does not reduce room/history writes or
  promise that Firebase usage will remain free. No measured production latency
  improvement is claimed.

## Final release verification

- Latest gate: 100 targeted Flutter tests passed sequentially; all 473 server
  tests passed. Analyzer gate passed with existing warnings/infos (no errors).
  Earlier full Flutter regression passed 1,047 tests before scoped follow-ups.
- Real Firestore emulator: all 3 tests passed, covering concurrent retries,
  single-room contention, 200-room success and atomic rollback on the final
  target collision. Flutter 200-room generation/save regression passed.
- Backend release 2026-10-16t03-09-10-901z and staging hosting completed;
  log: .dart_tool/rooms-usage-release.txt. Production was not deployed.
- Live staging, synthetic owner organization: created QA room flow 2026-10-15
  with QA101/QA102, shared Studio QA type and 25 square metre area. Reopened
  Edit and verified both inventory and saved defaults. Added QA103 manually;
  type/area inherited, save succeeded and existing inventory refreshed to all
  three rooms. Fixture retained. Screenshot: .dart_tool/building-rooms-live.jpg.
- One browser reload interrupted an unsaved edit; reopening and repeating the
  action succeeded. Cause was not established. No failed save was observed.
- Live verification covers the owner/VI desktop flow. Other roles, denial,
  retry/error and responsive states rely on automated coverage described above;
  physical-device keyboard/screen-reader checks remain unverified.
