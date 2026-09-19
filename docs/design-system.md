# CanHo360 UI conventions

The app uses a user-selected accent with neutral surfaces. Organization, building,
tenant, and member identities use shades of that accent, not unrelated palettes.

## Color

- Read `Theme.of(context).colorScheme` in widgets. Legacy custom accents use
  `AppThemePalette`; their widgets must depend on `Theme.of(context)` to repaint.
- Use `primary` for actions, selected controls, and card accents; `primaryLight`
  for quiet backgrounds; `primaryDeep` for darker headings and gradients.
- Use `identityGradient(id)` / `identityColors` for identity badges and cards.
- Keep payment states consistent: paid green, pending amber, overdue red.
  Category charts may retain separate colors when they convey distinct data.
- Keep text on neutral surfaces dark. White text requires a sufficiently dark
  background; never put translucent white chips on white Material surfaces.
- Do not put dynamic theme values in `const` constructors or cached color fields.
- Exported PDFs retain their document styling independently of the screen theme.

## Layout

- Reuse `AppDialog`, `ResponsiveFormRow`, and the app input/button themes.
- Use an 8-point spacing rhythm, quiet borders, and restrained shadows.
- Put the primary action where it is easy to find; reserve saturated backgrounds
  for navigation, selected states, and small identity accents.
- Keep destructive actions distinct from ordinary actions.
- Ensure horizontally scrolling controls are reachable on a 360px phone.

## Verification

- Change the theme on an already-open route and check kept-alive tabs.
- Test both English and Vietnamese at phone and desktop widths.
- Check rendered text contrast, not only the declared widget colors.
- Run `test/app_theme_test.dart` and `test/calendar_screen_test.dart` for theme
  changes. The latter exercises all organization tabs and calendar interactions.
