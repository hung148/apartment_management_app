# Firebase Hosting

Production URL: https://apartment-management-app-776b9.web.app

The Firebase project is `apartment-management-app-776b9`. No custom domain is required.

Build and publish from the repository root:

```powershell
flutter test test/web_startup_test.dart --platform chrome --concurrency=1
flutter build web --release
firebase deploy --only hosting --project apartment-management-app-776b9
```

Run Flutter tests and builds sequentially. The Hosting configuration serves only
`build/web`, with an `index.html` fallback for browser routes. Deploying with
`--only hosting` leaves Firestore rules and Cloud Functions unchanged.

If the global Firebase command is unavailable, use `npx firebase-tools` in its
place. On this machine the npm launcher may need its direct path:

```powershell
& 'C:/Program Files/nodejs/node.exe' 'C:/Program Files/nodejs/node_modules/npm/bin/npx-cli.js' --yes firebase-tools deploy --only hosting --project apartment-management-app-776b9
```

For a local release preview, run `firebase emulators:start --only hosting` after
building and open http://127.0.0.1:5000. This emulates Hosting only; the app still
uses the configured Firebase authentication and backend services.

## Initial release validation

- The release build completed successfully.
- The existing VM regression suite passed (50 tests, sequential execution).
- A local browser smoke check reproduced a blank-page failure from native window
  initialization on Windows browsers. The corrected release reached the login
  screen without observed console errors.
- `test/web_startup_test.dart` preserves the Windows-browser startup regression
  scenario. The Chrome test harness stalled during loading on this machine, so
  its assertions were not verified by the automated runner.
- Signed-in workflows and browser export/download features were not exercised.
- Firebase Hosting deployment succeeded. The public HTTPS URL was visually
  checked through the splash screen to the login screen, with no console errors
  observed during that startup check.
