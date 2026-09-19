# Project testing and UI verification

These rules apply to all work in this repository. Apply checks relevant to the
changed behavior; passing unrelated tests is not evidence that a change works.

## Bug fixes

- Reproduce a reported bug before changing the implementation. For a testable
  defect, add a regression test and confirm that it fails for the reported reason
  before fixing the code. If reproduction is unavailable, state that limitation.
- Keep the regression test after the fix. Do not weaken assertions merely to get
  a passing result. Update outdated expectations only when intended behavior has
  changed, while preserving meaningful behavioral coverage.

## Realistic UI coverage

- Before changing layout, identify the content and states that could affect it.
  Use representative populated fixtures, not only empty or minimal screens.
- For calendar changes, cover the affected combinations of empty and occupied
  rooms, long-term tenant badges, hourly prices, long room and tenant names, and
  overlapping bookings. Include loading, error, and empty states when affected.
- Check affected layouts in English and Vietnamese, on narrow phones and desktop
  windows, in phone landscape, and at normal and enlarged text sizes (including
  130% and 200% for text-sensitive changes). Check both embedded and standalone
  calendar layouts when shared code changes.
- Assert that Flutter reports no layout exceptions. Also check for clipping,
  obscured controls, unreachable actions, and layout movement during interaction;
  absence of a RenderFlex error alone does not establish usability.
- Render and inspect representative screenshots for visual layout changes using
  the app's actual fonts. Include the populated or edge-case state that motivated
  the change. Check relevant themes when colors or theme-dependent layout change.
  Do not equate generating or updating golden images with visually reviewing them.

## Validation and reporting

- Run targeted tests after changes. Run the full regression suite for shared
  layout or cross-cutting behavior changes, and whenever explicitly requested.
- On this machine, run Flutter tests sequentially with `--concurrency=1`. Avoid
  simultaneous test, build, and screenshot-generation jobs.
- Preserve useful regression coverage. Once appropriate checks pass, repeat or
  broaden them only for further edits, failures, or unresolved concerns.
- Report what scenarios were actually verified and any remaining gaps. Distinguish
  automated checks from rendered visual inspection and live-app verification.
  A test count alone is not proof that representative content was covered.
- Do not claim that all UI states are correct or that verification guarantees
  zero defects. If a required check cannot run, explain why and what remains
  unverified.
