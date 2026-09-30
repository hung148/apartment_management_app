# Staging verification

Run from the repository root. These tools target only
`apartment-management-staging` and use the signed-in Firebase CLI account.
Install the locked functions dependencies first. Never copy live tenant data or
provider secrets into this environment.

## Web release

```powershell
flutter test --concurrency=1
flutter build web --release --output=build/staging-web --dart-define-from-file=config/app_check.staging.json
node functions/node_modules/firebase-tools/lib/bin/firebase.js deploy --only hosting --config firebase.staging.json --project apartment-management-staging
```

The default Firebase alias and normal build/web directory remain separate.
Staging supports web only. An unknown APP_ENV fails closed.

## Backend evidence

`node tool/staging_verify.cjs` reads deployed function identities, probes the
unauthenticated boundary and reads index/IAM state. It writes a local report to
`.dart_tool/staging-verification.json`; it does not repair cloud permissions.

`node tool/staging_live_test.cjs` creates temporary synthetic Auth/Firestore
fixtures and an App Check debug token, exercises the callable authorization
boundary, then deletes its fixtures and token. It requires the public web SDK
configuration in `.dart_tool/staging-web-config.json` (Firebase web app getConfig
response). Do not use this as genuine browser attestation evidence.

`deploy_staging.cjs` preserves the initial REST rollout procedure because the
installed Firebase CLI does not forward an explicit build service account. It
requires the prepared `.dart_tool/staging-functions.zip`, endpoint metadata and
deployment journal. It resumes that exact rollout, **not a fresh source release**.
Do not reuse its old source object to publish changed code. A future backend
release must prepare a fresh source bundle with package.main=staging_index.js,
export fresh endpoint metadata, and use a fresh deployment journal after saving
the prior one. Review the journal and source hash before deployment. `--poll`
reads outstanding deployment operations. Initial deployments are batched by three.

Provider endpoints deliberately return unavailable. Staging Firestore enforcement
is enabled following genuine browser verification. The existing project's
enforcement and Editor retirement still require the remaining verification in
IAM_ROLLOUT.md. No service-account private keys are needed.

## Fresh backend release (current procedure)

`deploy_staging.cjs` only replays the first rollout. For changed code use
`staging_release.cjs`, which bundles the current `functions` source with
`main=staging_index.js`, reads identities/memory/triggers from the staging
entrypoint, and keeps a journal under `.dart_tool/staging-release/<id>/`.

```powershell
node tool/staging_release.cjs prepare
node tool/staging_release.cjs deploy     # starts 3; repeat after polling
node tool/staging_release.cjs poll       # repeat until running is 0
node tool/staging_release.cjs finish     # invoker access + Cloud Scheduler job
node tool/staging_verify.cjs
```

Callables get public transport (Auth/App Check inside are the boundary).
Scheduled functions stay private: only their runtime identity may invoke them,
through a Cloud Scheduler job with an OIDC token. `finish` enables the Cloud
Scheduler API in staging if needed; if job creation fails right after enabling,
wait a minute and run `finish` again (it is idempotent).

## Synthetic v2 organizations for manual tests

`staging_seed_v2.cjs create --owner EMAIL --viewer EMAIL` creates
`stagingSeedSource` (with one property, room, two tenants and an invoice) and
`stagingSeedTarget`, owned by the first account; the second account is a Viewer
in the source. Both accounts must be registered in the staging web app first.
`status` shows state and counts, `expire` makes a closed test organization due
for purge, `node tool/staging_release.cjs run-purge` runs the schedule once, and
`delete` removes everything the tool created.
