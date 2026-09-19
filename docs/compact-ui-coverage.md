# Compact UI rollout

## Design

Property operations, with the existing user-selected accent. Base colors:
white #FFFFFF, ink #172D3B, muted #475569, border #E1E6E3,
background #F6F7F4, default accent #176B70. Roboto throughout.
56px navigation; 8/12/16px content spacing; 12px surface corners.
Content determines row height. Preserve 48px button targets and allow large text
to grow content. Use menus at narrow widths instead of clipped navigation.

The skill search's property-marketing hero recommendation was rejected because
this is an operations app. Its data-dense dashboard style fits; preserve the
established color and font system instead of adopting a marketing typography kit.

## Scope and verification ledger

| Surface | Implementation | Verification |
|---|---|---|
| Dashboard, organization picker, settings | Compact header and account strip, tighter cards/dialogs; original property image retained as a compact strip | Full suite; image strip visually inspected |
| Organization: calendar | Existing compact toolbar and measured rows preserved | Full suite; occupied labels tested at 100/130/200% text |
| Organization: buildings | Combined summary/actions, tighter cards | Full suite; populated organization fixtures |
| Organization: tenants | Tighter summaries, cards and forms | Full suite; populated organization fixtures |
| Organization: payments | Tighter cards and shared controls | Full suite; populated payment fixtures |
| Organization: statistics | Tighter summary surfaces and shared controls | Full suite; populated payment/room fixtures |
| Organization: members/invitations | Tighter summaries/cards/dialogs | Full suite; populated member fixtures |
| Building room list, room editor, room information | 56px header, tighter rows/forms | Full suite; Dart analysis no errors |
| Room detail: tenants, payments, vehicles and tenant forms | Single-row navigation and tighter surfaces | Full suite; Dart analysis no errors |
| Building rental and rental payment form | Compact header/cards/form | Full suite; Dart analysis no errors |
| Booking creation and details | Shared controls and tighter dialog spacing | Full suite; booking dialog regression |
| Payment creation, edit, view, delete | Shared controls and tighter dialog spacing | Full suite; currency/payment regressions |
| AI import/review and subscription | Tighter surfaces and shared controls | Full suite; populated review and overlay tests |
| Login and registration | Tighter authentication panel and shared controls | Full suite; input and responsive form tests |
| Splash | Existing transient branding retained; no data controls to compact | Source reviewed |
| Chat and subscription overlay | Shared controls | Full suite; 390px and 1200px overlay tests |
| PDF/Excel exports | Output document layout outside on-screen density scope | Source reviewed |

The sequential full suite currently passes 28 tests. Dart analysis reports no
errors; remaining output is lint, deprecation, and unused-code guidance. Visual
inspection covered the calendar's populated occupied-room state and the restored
dashboard image strip. Live-app inspection of every route remains a follow-up
when a running app session is available.
