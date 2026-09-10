# AI launch setup

## Approved plans

- Free: 5 messages and 1 successful import extraction per Firebase account per day, resetting at midnight UTC.
- AI Pro: $4.99/month launch price, 300 messages and 30 import extractions per monthly subscription billing period. No rollover. Pro allowance replaces the free allowance while subscribed.
- A successful extraction consumes one import even if the user dismisses the review. Provider failures refund the reserved allowance. Saving/retrying an existing draft consumes no additional allowance.
- One file up to 5 MB, up to 50 records per draft. Supported: PNG/JPEG/WebP, PDF, TXT/CSV/JSON, XLSX. Raw uploads are sent to Gemini in memory, not stored in Firestore. Draft records and request results are stored temporarily.

## 1. Replace the bundled Gemini key

The old `.env` was an application asset. It has been removed from the asset list and AI now calls Firebase functions. Treat the old Gemini key as exposed to anyone with an old application binary. Firebase application API keys in `firebase_options.dart` are separate client configuration, not the Gemini secret.

Create a NEW key at https://aistudio.google.com/api-keys in the intended Google Cloud project. Use a billing-enabled Gemini project appropriate for tenant data; review Google's data-use terms and privacy disclosures before production uploads. Restrict the key to the Generative Language API. Set it securely in your interactive project terminal:

```powershell
node functions/node_modules/firebase-tools/lib/bin/firebase.js functions:secrets:set GEMINI_API_KEY --project apartment-management-app-776b9
```

Paste it into the hidden prompt, never source code, chat or a build flag. After backend verification and distributing the updated app, revoke the old Gemini key in AI Studio. If abuse is suspected, revoke it immediately; old AI clients will stop working.

## 2. Apple setup (you already have Apple Developer)

1. Open App Store Connect, finish Paid Apps agreements, tax and banking details yourself.
2. The repository currently uses `com.tom.apartmentmanagement` on iOS and macOS. Confirm the App Store Connect listing uses this identifier and add macOS to the universal purchase listing if appropriate.
3. Add In-App Purchase capability in Xcode for both Runner targets on a Mac.
4. Create a subscription group named `AI Pro`, then an auto-renewable one-month product with product ID `ai_pro_monthly`.
5. Set the US base price to $4.99/month. Apple supplies localized prices. Add English/Vietnamese descriptions, review screenshot and required subscription disclosures.
6. Create sandbox testers, and test purchase, renewal, cancellation, expiry and restore on both iOS and macOS before submission.

## 3. RevenueCat setup

1. Create an account at https://app.revenuecat.com/ and a project for the app.
2. Add the Apple app and connect App Store Connect following RevenueCat's setup. Keep private Apple API keys in RevenueCat's secure dashboard, not this repository.
3. Import product `ai_pro_monthly`. Create entitlement **`ai_pro`** and attach the product.
4. Create offering **`default`**, add a Monthly package, attach the Apple monthly product and make the offering current.
5. Configure receipt restore/transfer policy deliberately. The app identifies customers with the signed-in Firebase UID; anonymous purchases are not used.
6. Copy the Apple PUBLIC SDK key for the Flutter build configuration. Public SDK keys are designed to be included in apps. A RevenueCat SECRET API key is server-only.
7. Create a server API key authorized to read subscribers via RevenueCat v1 API. Store it with the hidden Firebase prompt:

```powershell
node functions/node_modules/firebase-tools/lib/bin/firebase.js functions:secrets:set REVENUECAT_SECRET_KEY --project apartment-management-app-776b9
node functions/node_modules/firebase-tools/lib/bin/firebase.js functions:secrets:set REVENUECAT_WEBHOOK_AUTH --project apartment-management-app-776b9
```

For webhook auth, generate a long random value locally and include `Bearer ` before it. Put the exact same header value into the RevenueCat webhook Authorization setting. Set the webhook URL to:

`https://us-central1-apartment-management-app-776b9.cloudfunctions.net/revenueCatWebhook`

Webhook events only trigger a fresh server-side subscriber lookup; event payloads and client claims cannot directly grant access. Renewal/expiration/transfer handling derives access from RevenueCat's current entitlement. Configure Apple server notifications in RevenueCat. Sandbox purchases do not grant production quotas; use a separate staging Firebase project with `ALLOW_SANDBOX_BILLING=true` for tests.

## 4. Stripe and Windows

1. Create a Stripe account, complete business identity and banking setup yourself, and check availability in your business country.
2. In RevenueCat, connect Stripe as the gateway for RevenueCat Billing (or use the Stripe Billing integration).
3. Create the same $4.99/month offering and attach it to entitlement `ai_pro`.
4. Create a production Web Purchase Link and configure returning subscribers to skip duplicate purchases. Copy the base URL `https://pay.rev.cat/<token>`.
5. The Windows app appends the logged-in Firebase UID to this URL. After checkout, the user can refresh AI Pro status. Webhooks synchronize access across devices.
6. Configure customer subscription management and cancellation in the hosted billing portal/emails. Apple apps use Apple subscription management, not external checkout.

## 5. Public build configuration

Provide these with `--dart-define` (or a local `--dart-define-from-file` JSON file):

- `REVENUECAT_APPLE_PUBLIC_KEY`: RevenueCat Apple public SDK key.
- `REVENUECAT_CHECKOUT_URL`: production purchase-link base URL for Windows.
- `PRIVACY_POLICY_URL`: your published HTTPS privacy policy.
- `TERMS_URL`: your published HTTPS terms, including subscription terms.

Never put Gemini or RevenueCat secret keys in these flags. Purchase buttons remain unavailable until platform billing and legal URLs are configured. Apple prices are read from the store, not hardcoded to a dollar amount in the UI.

## 6. Deploy after secrets are configured

From the repository root:

```powershell
node functions/node_modules/firebase-tools/lib/bin/firebase.js deploy --project apartment-management-app-776b9 --only "functions:aiChat,functions:aiUsage,functions:aiImportPreview,functions:aiImportCommit,functions:aiSyncSubscription,functions:revenueCatWebhook,firestore:rules"
```

To launch free AI before billing accounts are ready, deploy only `aiChat`, `aiUsage`, `aiImportPreview`, `aiImportCommit` and rules after setting the Gemini secret. Subscriptions must remain unavailable until the store/provider setup and sandbox purchase tests are complete.

PowerShell command for the free-AI launch (this avoids prompting for RevenueCat secrets):

```powershell
node functions/node_modules/firebase-tools/lib/bin/firebase.js deploy --project apartment-management-app-776b9 --only "functions:aiChat,functions:aiUsage,functions:aiImportPreview,functions:aiImportCommit,firestore:rules" --force
```

Enable Firestore TTL policies on `expiresAt` for collection groups `aiDrafts`, `aiRequests`, and `aiUsage` in Google Cloud Firestore → Time-to-live. Drafts expire for saving after 24 hours; physical cleanup requires TTL. Billing-period quota counters expire after 32 days from their latest usage. Define appropriate retention in your privacy policy.

## Verification and release boundaries

Emulator checks cover simultaneous free limits, failed-request refunds, replay protection, paid-period quotas, blocked client entitlement writes, cross-organization denial, and atomic linked imports. Model outputs are treated as data, validated and shown for review. Import commit requires admin access and takes the same room lock as bookings when creating tenant occupancy.

This Windows workstation cannot validate StoreKit or sign iOS/macOS builds. Test those on a Mac and real/sandbox devices. Live Gemini calls require the replacement secret; live purchases require configured provider accounts/products. Do not submit the paywall as a working subscription before those checks pass.

Sources: https://firebase.google.com/docs/functions/config-env ; https://ai.google.dev/gemini-api/docs/api-key ; https://developer.apple.com/app-store/review/guidelines/ ; https://www.revenuecat.com/docs/getting-started/installation/flutter ; https://www.revenuecat.com/docs/web/web-billing/web-purchase-links .

## Implementation status

Core AI functions are deployed. `GEMINI_API_KEY` secret version 2 is attached to `aiChat` and the other AI functions. Windows uses the authenticated HTTPS callable fallback because the current FlutterFire `cloud_functions` package is not registered for Windows; iOS/macOS use the native callable client. RevenueCat configuration, Stripe setup, policy URLs, and Apple sandbox validation remain required before billing functions can be enabled. Existing calendar functions remain deployed. The old Gemini key has not been revoked automatically.

Validation: 10 Firestore emulator integration tests passed, 7 existing backend regression tests passed, and 18 Flutter tests (including the two new bilingual import tests) passed across the test runs. Full static analysis showed no errors before final formatting; existing unrelated warnings remain.

The debug app bundle also built successfully. Its asset manifest excludes `.env`; three stale generated `.env` assets were removed from the build directory. The local source `.env` was not displayed or transferred. Previously distributed binaries remain outside this cleanup and their old Gemini key must be revoked.
