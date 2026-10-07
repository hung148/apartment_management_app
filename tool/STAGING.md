# Staging verification

Run from the repository root. These tools target only
`apartment-management-staging` and use the signed-in Firebase CLI account.
Install the locked functions dependencies first. Never copy live tenant data or
provider secrets into this environment.

## Web release

Everything below (analyze, test, functions, web build, hosting) in one command,
stopping at the first failure:

```powershell
powershell -ExecutionPolicy Bypass -File tool\staging_all.ps1
```

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
# One command (prepare, deploy 3 at a time + poll until done, finish, verify;
# resumes if interrupted; add --replace to abandon an unfinished release):
node tool/staging_release.cjs all

# Or step by step:
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

## v2 migration rehearsal (G8)

`tool/migrate_v2.cjs` moves one legacy organization to version 2. Every step
except `rehearse` works on the project named in `--project`; `rehearse` reads
production (read-only) and writes an **anonymized** copy into staging, so no
live names, phones, emails, addresses or notes reach staging (amounts, dates
and structure stay so the move can be tested). Backups and plans are written
under `private-backups/migrate-v2/` (git-ignored).

```powershell
node tool/migrate_v2.cjs rehearse --org PRODUCTION_ORG_ID --owner your-staging@gmail.com
node tool/migrate_v2.cjs plan --project staging --org REHEARSAL_ORG_ID
node tool/migrate_v2.cjs apply --plan "FOLDER" --confirm "ORGANIZATION NAME"
# test in the staging app, then:
node tool/migrate_v2.cjs undo --plan "FOLDER"     # rollback rehearsal
node tool/migrate_v2.cjs rehearse-delete           # remove rehearsal copies
```

What the plan changes: owner → `owner`, admin → `administrator`, everyone else
waits for a role (`assignmentRequired`), non-active people `suspended`;
properties without a time zone/currency get `Asia/Ho_Chi_Minh`/`VND`; rooms
without a rental mode get `both` (short-stay prices or bookings) or `monthly`;
old tenants/bookings/payments get `organizationId`/`buildingId` from their
room; the organization gets `accessVersion: 2` last. `apply` stops if any of
those fields changed after the plan; `undo` restores the previous values and
leaves fields that were changed after the move unless `--force`.
