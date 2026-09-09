Implemented form, localization, and calendar improvements

Money inputs now use comma grouping, preserve USD cents, keep caret/selection positions, and leave IME composition intact. Parsers accept grouped amounts, including booking totals, room rates, tenant rent/deposits, building rent, payment items, paid amounts and tax. Monetary keyboard layouts allow decimal entry. Prefilled room rates and edited payment totals use grouped values without rounding away cents.

New independent records default to USD in English and VND in Vietnamese. Buildings, rooms, tenants and bookings now persist currency; legacy documents without that field remain VND. Bookings and payments derived from an existing room, tenant or building retain that source currency. Language switching never converts existing amounts. Generated rooms inherit the building currency, and booking settlement carries currency to its payment.

Shared date fields now use the localized Material date picker, including its validated typed-entry mode. They preserve the selected date across language changes, synchronize parent updates, clamp the calendar's initial date to its permitted range, support required validation, and allow clearing optional dates. Vietnamese displays DD/MM/YYYY; English displays MM/DD/YYYY.

Shared field labels remain visible. Seven pairs of fields stack vertically in narrow dialogs or with enlarged text. Tenant forms use more comfortable density and room for grouped amounts. Resize handlers no longer discard dialogs or pop pages merely because the window becomes small.

The calendar retains its fixed room column and room-by-time day layout. The month view now summarizes busy/free rooms, uses localized short weekdays and locale-specific week starts, highlights today, provides accessible day descriptions, and opens the day timeline on tap. Date navigation opens a date picker. The room column is narrower on phones; the building dropdown respects available width. A request generation check prevents an older date response from replacing a newer selection.

Calendar research: Guesty documents a multi-calendar for reservations and availability, with mobile access and reservation details. This informed retaining the room timeline and making the month view an overview with day drill-down. Sources: https://help.guesty.com/hc/en-gb/articles/28012752150685-Navigating-the-Multi-Calendar and https://help.guesty.com/hc/en-gb/articles/9363972460189-Managing-your-calendar-in-the-Guesty-mobile-app . These sources informed the design; the app does not implement Guesty's full feature set.

Verification: 11 Flutter tests pass, covering comma formatting, decimal preservation, IME composition, caret handling, English/Vietnamese phone-width date pickers, changing language with a selected date, clearing optional dates, enlarged-text responsive fields, currency persistence and legacy defaults, and the actual calendar day/month screens at 360px in both languages. Static analysis reports no errors; existing warnings and lint findings remain. The original unrelated counter smoke test was replaced with application-model regressions. No live Firestore writes or physical-device QA were performed.

Additional issues found for follow-up:

- High priority: organization revenue charts and exports aggregate numeric amounts without grouping by currency. Mixed USD/VND reporting must use separate totals or an explicit exchange-rate policy. See organization_screen.dart, especially the revenue calculations and fixed VND spreadsheet format.
- High priority: booking_service.dart catches calendar query failures and returns empty results. A failed query can look like free inventory. Surface a failed/offline state with retry rather than displaying availability as confirmed.
- High priority: booking availability checks and booking creation are separate operations. The service itself documents the low-concurrency assumption. Enforce overlap prevention on the backend for simultaneous staff bookings.
- Payment PDF/export output and several display-only amount helpers still assume VND or use their own translation maps. These need a separate currency-aware reporting/export pass. Input currency persistence is implemented; reporting is not fully multi-currency.
- There are still legacy hardcoded display/error strings outside the updated form/calendar paths. Centralizing them and adding a translation-key parity check would prevent regressions.

Existing uncommitted user changes were preserved. This work was not committed or deployed.
