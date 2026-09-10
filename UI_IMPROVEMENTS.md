Implemented form, localization, and calendar improvements

Money inputs now use comma grouping, preserve USD cents, keep caret/selection positions, and leave IME composition intact. Parsers accept grouped amounts, including booking totals, room rates, tenant rent/deposits, building rent, payment items, paid amounts and tax. Monetary keyboard layouts allow decimal entry. Prefilled room rates and edited payment totals use grouped values without rounding away cents.

New independent records default to USD in English and VND in Vietnamese. Buildings, rooms, tenants and bookings now persist currency; legacy documents without that field remain VND. Bookings and payments derived from an existing room, tenant or building retain that source currency. Language switching never converts existing amounts. Generated rooms inherit the building currency, and booking settlement carries currency to its payment.

Shared date fields now use the localized Material date picker, including its validated typed-entry mode. They preserve the selected date across language changes, synchronize parent updates, clamp the calendar's initial date to its permitted range, support required validation, and allow clearing optional dates. Vietnamese displays DD/MM/YYYY; English displays MM/DD/YYYY.

Shared field labels remain visible. Seven pairs of fields stack vertically in narrow dialogs or with enlarged text. Tenant forms use more comfortable density and room for grouped amounts. Resize handlers no longer discard dialogs or pop pages merely because the window becomes small.

The calendar retains its fixed room column and room-by-time day layout. The month view now summarizes busy/free rooms, uses localized short weekdays and locale-specific week starts, highlights today, provides accessible day descriptions, and opens the day timeline on tap. Date navigation opens a date picker. The room column is narrower on phones; the building dropdown respects available width. A request generation check prevents an older date response from replacing a newer selection.

Calendar research: Guesty documents a multi-calendar for reservations and availability, with mobile access and reservation details. This informed retaining the room timeline and making the month view an overview with day drill-down. Sources: https://help.guesty.com/hc/en-gb/articles/28012752150685-Navigating-the-Multi-Calendar and https://help.guesty.com/hc/en-gb/articles/9363972460189-Managing-your-calendar-in-the-Guesty-mobile-app . These sources informed the design; the app does not implement Guesty's full feature set.

Verification: 11 Flutter tests pass, covering comma formatting, decimal preservation, IME composition, caret handling, English/Vietnamese phone-width date pickers, changing language with a selected date, clearing optional dates, enlarged-text responsive fields, currency persistence and legacy defaults, and the actual calendar day/month screens at 360px in both languages. Static analysis reports no errors; existing warnings and lint findings remain. The original unrelated counter smoke test was replaced with application-model regressions. No live Firestore writes or physical-device QA were performed.

Issues identified in the first pass (follow-up implementation below):

- High priority: organization revenue charts and exports aggregate numeric amounts without grouping by currency. Mixed USD/VND reporting must use separate totals or an explicit exchange-rate policy. See organization_screen.dart, especially the revenue calculations and fixed VND spreadsheet format.
- High priority: booking_service.dart catches calendar query failures and returns empty results. A failed query can look like free inventory. Surface a failed/offline state with retry rather than displaying availability as confirmed.
- High priority: booking availability checks and booking creation are separate operations. The service itself documents the low-concurrency assumption. Enforce overlap prevention on the backend for simultaneous staff bookings.
- Payment PDF/export output and several display-only amount helpers still assume VND or use their own translation maps. These need a separate currency-aware reporting/export pass. Input currency persistence is implemented; reporting is not fully multi-currency.
- There are still legacy hardcoded display/error strings outside the updated form/calendar paths. Centralizing them and adding a translation-key parity check would prevent regressions.

Existing uncommitted user changes were preserved. This work was not committed or deployed.


Follow-up implementation

The calendar now offers day/week/month/agenda, all room rental modes, search and occupancy filters, retryable server-load failures, booking edits and lifecycle actions, payment/deposit collection and refunds, room details, tenant details and invoice creation. Cancelled reservations remain in agenda/room history for refunds without blocking availability. Historical tenants with recorded move-out dates remain visible for their occupancy interval.

USD/VND reporting totals are separated with a currency selector; individual amounts and PDF/Excel exports use record currency. Export translations live in app localization. PDFs no longer default to an unsaved 10% tax and include saved late fees. Mobile Excel export opens the native share sheet instead of reporting success without a file.

Cloud Functions use a shared room transaction lock for bookings and leases and atomically record booking payments. Firestore rules protect those writes, scope reads to organizations, and prevent self-assigned admin membership. See FIREBASE_DEPLOYMENT.md for rollout and operational limits.

Verification: 14 Flutter tests, 6 backend unit tests, and 4 real Firestore emulator tests passed. The emulator verified concurrent reservations produce only one booking, unauthorized writes fail, valid invitations work, and organization creation succeeds. No production deployment, physical-device validation, or Git commit was performed.


Production rollout, 2026-09-09

Both calendar callables and the Firestore rules are deployed. A second-generation callable request-format mismatch was corrected and covered by an additional regression test (7 backend unit tests now pass). Live signed-out checks return the expected UNAUTHENTICATED response for both functions. No production test data was created. The updated app is required for protected booking/tenant writes; authenticated physical-device verification remains outstanding.


Dialog styling and two-click calendar selection

Shared dialog surfaces now cover the application's custom dialogs and confirmations across 15 files. The common theme provides consistent indigo accents, rounded fields, visible focus borders and larger action targets. Dialogs use smaller phone margins and keyboard-aware height limits; standard confirmations scroll and booking cancellation/payment-method dialogs can scroll on short screens. Existing form actions and booking confirmation remain intact.

In the day timeline, left-click (or tap) a free time to select a start, then a later time in the same room to select an end. Times snap to 30-minute boundaries. A highlighted range and bilingual prompt guide selection; mouse hover previews the end. The existing booking dialog opens with those dates and times. Escape or Cancel clears selection. Selecting a different room starts a new selection; date/view/building changes clear it. Selecting an invalid duration, out-of-hours end, or a range crossing an active booking is rejected. Existing reservations still open their details when clicked, and the room-panel booking button remains available.

Verification: all 16 Flutter tests passed, including mouse/touch selection, Escape, invalid end times, phone dialogs, enlarged text and keyboard layouts. Additional English/Vietnamese conflict-selection checks passed. Static analysis found no errors in the updated components. Rendered booking dialogs were inspected in both languages at 360px. No backend deployment is needed for this UI change; the app must be rebuilt/restarted to load it.


AI manager, imports and subscription implementation

AI requests now go through authenticated Cloud Functions with a server-owned professional property-manager prompt, bounded read-tool access and per-account transactional quotas. The app no longer contains a Gemini request implementation or bundles `.env`. The debug bundle builds and excludes that asset; stale generated copies were removed.

Free usage is 5 messages and 1 successful extraction daily (UTC). AI Pro is configured for the approved $4.99/month launch plan with 300 messages and 30 imports per billing period. Entitlements come from server-side RevenueCat verification; client claims and unauthenticated webhooks cannot grant access. Apple purchase/restore and Windows hosted checkout code require provider/product configuration before use.

Imports accept image/PDF/text/CSV/JSON/XLSX and produce editable review records. Saving creates organizations, buildings, rooms, tenants and payments atomically with parent validation, currency checks, booking/lease conflict checks, local-date preservation and idempotent retries. No records are saved merely by extraction.

Verification: 18 Flutter tests, 10 Firestore emulator integration tests and 7 backend regression tests passed. The AI Dart components have no static errors. No live AI/billing deployment or paid purchase was performed. See AI_SETUP.md for replacement-key, Apple, RevenueCat, Stripe and release steps.
