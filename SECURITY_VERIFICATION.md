# Security hardening evidence — 2026-09-27

## Staging update — 2026-09-28

The separate `apartment-management-staging` project now has all 30 functions
ACTIVE under dedicated runtime/build identities, deployed rules and READY
indexes. Fourteen live authenticated acceptance cases passed, covering App Check
rejection/acceptance, seven role/property combinations, suspension, revocation,
legacy-role denial and direct financial-write denial. Temporary debug attestation
was used and removed; this is not evidence of genuine browser attestation.
All 238 sequential Flutter tests and 64 backend unit tests passed. Existing app
project permissions and deployments remain unchanged. Firestore App Check
enforcement, browser clock/offline recovery, provider sandbox checks and existing
Editor-role retirement remain release gates. See [IAM rollout](IAM_ROLLOUT.md).

Subsequent live browser check: hosted staging sign-in and directory request
succeeded with server-recorded Auth=VALID/App Check=VALID, without debug
attestation. Enabled **staging only** Firestore App Check enforcement; reloaded
browser dashboard succeeded, and authenticated own-profile REST reads with
missing/invalid App Check returned 403. This completes the staging attestation
smoke check, not clock/offline/operational-write verification or existing-project
cutover. Staging web build and focused Dart analysis passed.

## Prior local-only checkpoint

Status: local hardening implemented; **production security is not signed off**.
No application, function, rules or Hosting deployment was performed. With the
user's explicit authorization, reCAPTCHA Enterprise was enabled and a SCORE key
was created and registered for the existing Firebase web app. Registration was
read back successfully. Firestore App Check remains UNENFORCED pending cutover.

## Implemented

- Every exported callable uses `createSecureCallable`, with App Check enforcement,
  authenticated identity, bounded payloads and persistent server-clock token
  buckets. Inner handlers still perform live role/property checks. The billing
  webhook retains its separate shared-secret/provider verification boundary.
- General allowance: burst 120 and refill 120/minute per account; 1,200 and
  1,200/minute per organization. Invitation lookup/invite/request/accept shares
  burst 12 and refill 6/minute per account, 120 and 60/minute per organization.
  AI chat/import/subscription sync shares burst 4 and refill 2/minute per account,
  20 and 10/minute per organization. All count against the general account budget.
  Invalid and forbidden attempts count. An outsider cannot debit an organization's
  shared bucket merely by supplying its ID. Limits supplement business quotas.
- Buckets use fixed hashed IDs, not caller time or operation IDs; concurrent
  debits are transactional. Direct reads/writes are denied by Firestore rules.
  Storage failure fails closed. No raw payloads, emails or tokens are stored in
  rate records. `expiresAt` is available for optional TTL cleanup; no TTL policy
  was configured. Per-account/per-organization document count is bounded.
- Requests are limited to 128 KiB, except import preview (8 MiB, retaining the
  existing 5 MiB decoded-file checks). Existing field allowlists remain in force.
- Flutter initializes App Check before Auth, Firestore or Functions use. Web
  requires the public site key; mobile uses Play Integrity/App Attest with Device
  Check fallback. No embedded debug token or release bypass was added.
- Unsaved AI drafts now expire at `serverTime >= expiresAt`, fixing the reproduced
  exact-boundary acceptance defect. Provider error bodies are no longer logged.
- Firebase Admin/Functions upgraded to patched releases; old Admin namespace
  imports migrated to modular APIs. Unused `firebase-functions-test` removed.
  Narrow CLI-only dependency overrides patch `qs`, `gaxios`'s UUID and Pub/Sub's
  OpenTelemetry core; CLI/emulator loading and regression tests verified them.
- Hosting source adds nosniff, strict-origin referrer policy and a limited CSP
  (`object-src`, `base-uri`, `frame-ancestors`). This is not a complete script CSP.
  Deployment excludes local maintenance/scanning scripts and tests. Additional
  local secret/signing file patterns are ignored by Git.

## Automated evidence

- 237 Flutter tests passed sequentially (`--concurrency=1`), including existing
  uncertain-request recovery, permission loss, role navigation and operation IDs.
- 62 backend unit tests passed, including missing App Check/Auth, caller clock
  injection, abuse buckets, payload limits and exact import expiry. Security
  wiring and private error-body logging regressions failed before their fixes.
- 84 Firestore emulator tests passed after the final dependency/expiry changes.
  Coverage includes all seven workspace role projections, selected/no-property
  scope, suspended/revoked access, cross-property/organization IDs, legacy v2
  bypass attempts, direct financial/audit writes, invitation recipient/revocation,
  transactional concurrent money operations and operation replay.
- New emulator cases fix backend invitation time at exact expiry while providing
  independently computed client dates +/-366 days; acceptance fails without new
  membership/audit. A queued collection after revocation is rejected. Sixteen
  simultaneous lookups allow exactly twelve; rate-record read/update/delete
  attempts are denied. Backend time was not changed by the client simulation.
- `npm audit`: zero known advisories in the final dependency tree. OSV batch
  lookup: no findings for 156 hosted packages in `pubspec.lock`. This is a point-in-
  time advisory check, not a guarantee about future or undisclosed vulnerabilities.
- Heuristic secret scan: 398 working files, 1,396 reachable historical blobs and
  315 freshly built web artifact files; no supported-pattern matches. Eight large
  legacy installer binaries over 20 MiB were explicitly skipped. It does not detect all
  custom credentials or inspect remote builds, ignored local files, Secret Manager
  values, deleted/unreachable Git objects, or signed mobile/desktop artifacts.
- Focused App Check analysis: no issues. Repository-wide `flutter analyze` has
  336 existing warnings/info findings (no errors); it is **not** a clean full
  analysis result. Tests ran on local Node 24; deployment runtime remains Node 22.
- The production JavaScript web build succeeded from `lib/main.dart` using the
  registered App Check key. Its optional Wasm dry run reported the existing
  `image` package's numeric-type compatibility warnings; Wasm is not verified.

Raw local logs are in `.dart_tool/security-*` (ignored, not release artifacts).
No UI layout changes or new screenshot inspection were part of this security
task. Earlier operational visual inspection does not establish live security.

## Clock matrix disposition

| Checklist cases | Local evidence | Remaining acceptance |
|---|---|---|
| C01, C04, C12 | Server payment/actor/time assertions, field injection and protected-write denial | Repeat via deployed callable/SDK with real accounts |
| C02, C03 | Exact server expiry, forged past/future client dates, stale/revoked invitation | Real page left open and direct HTTP acceptance |
| C05, C06, C07 | Server property-date/backdate policy, proration, DST gaps/repeated times and operating schedules | Browser clock/timezone matrix, legacy display/overdue/report behavior |
| C08 | Backend AI quotas, verified entitlement tests, exact draft expiry | Provider sandbox/expiry behavior in staging |
| C09, C14 | Revoked queued mutation rejected; Flutter uncertain/retry tests | Real offline/reconnect and network interruption |
| C10, C11 | Concurrent collections/refunds/bookings; exact operation retries and changed-payload rejection | Two real devices and cross-device UI feedback |
| C13 | V2 legacy report/export routes remain outside approved replacement scope | Inspect PDFs/export labels before enabling those paths |

## Live configuration and release blockers

1. Registered key domains are exactly:
   `apartment-management-app-776b9.web.app` and
   `apartment-management-app-776b9.firebaseapp.com`. No localhost, wildcard,
   preview-channel or custom domains were added. `config/app_check.web.json`
   contains a **public site key**, not a server secret. For localhost testing use
   a separately registered development/debug setup, never ship a debug token.
2. Register and verify mobile attestation before mobile release. Windows/Linux
   connected startup is deliberately unavailable until a supported production
   attestation strategy exists; disconnected preview remains available.
3. Verify real web token issuance on an allowed Hosting domain, valid-token
   callable success, missing/invalid-token rejection, token refresh and outages.
   Then deploy the App Check client and secured functions in a coordinated window.
   Old clients cannot call the newly enforced endpoints without App Check.
   Enable Firestore enforcement only after verified traffic is confirmed.
4. Read-only project IAM review succeeded: **three service accounts have the broad
   Editor role**; two human owners; no public (`allUsers`/`allAuthenticatedUsers`)
   binding in the project policy. No roles were removed. Map runtime/build/admin
   dependencies and deploy a least-privilege runtime identity before removing
   broad grants. The six currently deployed Node 22 functions use the default
   Compute account for both build and runtime. Split those responsibilities at
   cutover: application runtime needs scoped database/declared-secret access,
   whereas builds need their own build/artifact permissions. Do not simply remove
   Editor from the shared identity and break the existing build/runtime. Secret
   Manager lists three secrets; values were not read and resource-level secret
   IAM was not inspected. The deployed inventory does not yet contain the new
   Team/operational endpoints.
5. Existing legacy organizations still use legacy policies until separately
   reviewed migration. This work proves v2 denial paths; it does not turn every
   legacy organization into v2 or certify old payment/timestamp paths as safe.
6. Complete deployed index, staging account/browser, SDK/HTTP, monitoring, Auth
   recovery/session, backup/restore and rollback checks in the release checklist.
   Rate limits cannot prevent all distributed account creation or provider-level
   traffic; monitor denials, costs and legitimate-use contention during rollout.
   Read-only Auth metadata confirms email sign-in and three authorized domains:
   localhost and the two Firebase Hosting domains. Recovery, MFA, OAuth provider
   settings, session revocation and domain cleanup remain live acceptance work.

## Repeatable commands

From the repository root:

```powershell
flutter test --concurrency=1
flutter analyze lib/services/app_check_service.dart
flutter build web --release -t lib/main.dart --dart-define-from-file=config/app_check.web.json
node functions/security_scan.js
node functions/security_pub_audit.js
```

From `functions`:

```powershell
npm.cmd test
npm.cmd audit
npm.cmd run test:team:emulator
```

For a disconnected UI preview only:
`flutter run -d chrome -t lib/team_preview.dart`.
It does not exercise App Check, Firestore rules, real clocks or server rate limits.

Implementation references: [Firebase callable enforcement](https://firebase.google.com/docs/app-check/cloud-functions),
[Flutter App Check](https://firebase.google.com/docs/app-check/flutter/default-providers),
[reCAPTCHA key creation](https://docs.cloud.google.com/recaptcha/docs/reference/rest/v1/projects.keys/create).
