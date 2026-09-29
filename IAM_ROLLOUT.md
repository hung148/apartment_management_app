# Restricted service-account rollout

## Staging deployment checkpoint — 2026-09-28

This checkpoint supersedes the initial creation notes below. The isolated staging
database, rules and composite indexes are deployed (all indexes READY). All 30
Node 22 functions are ACTIVE with the dedicated build account and the intended
business/AI/billing runtime accounts. Runtime accounts have Datastore User;
the build account has project Logs Writer, repository Artifact Registry Writer,
and source/upload bucket Object Viewer. No custom account was granted Editor.
No provider secrets or service-account keys were created. AI and RevenueCat
endpoints deliberately return unavailable in staging.

Live HTTP verification: 29 unauthenticated callable requests rejected; webhook
disabled. Authenticated integration checks passed for valid/missing/invalid App
Check, all seven roles, selected-property scope, suspension/revocation with an
existing token, rejected legacy member role and denied direct payment writes.
Temporary Auth user, fixture records and debug token were removed. These tests
used temporary App Check debug attestation; genuine browser attestation remains
a separate release gate, subsequently verified below.

Local validation: 64 backend unit tests and 238 sequential Flutter tests passed.
No existing-project IAM, function, rules or Hosting deployment was changed.

The staging web release is published at
https://apartment-management-staging.web.app with its own Firebase web app,
email/password Auth, Hosting-domain-only reCAPTCHA Enterprise registration and
APP_ENV=staging build. All three environment-selection test modes passed;
focused Dart analysis found no issues. The JavaScript release build succeeded
(the dependency's optional Wasm dry run reports existing image-package warnings).
Repeatable web commands and saved verification tooling are in tool/STAGING.md.

Genuine browser verification subsequently passed on the hosted release using a
temporary verified synthetic account: server logs recorded Auth=VALID and
App Check=VALID for listMyOrganizations, with HTTP 200. No debug token was used
in the browser. Enabled staging Firestore enforcement and read it back as
ENFORCED (2026-09-28 15:31 UTC). The browser dashboard loaded again after a
reload; authenticated direct reads of the test account's own profile with no
App Check or an invalid token both returned 403. Its rules otherwise allow that
account to read its own profile. This covers startup/sign-in and directory reads,
not all operational writes, offline recovery, or clock manipulation. Existing
project enforcement remains unchanged. Browser proof is saved locally at
.dart_tool/staging-browser-verified.png.

Cleanup completed: signed out the browser, removed its temporary Auth account
and owner profile, and deleted the local scripts containing its disposable
password. Final deployed-function/index/IAM verification completed at 15:36 UTC.

## Initial staging creation record

- Created Firebase project `apartment-management-staging` (number `933030543017`).
- Linked the explicitly approved **Firebase Payment** billing account; verified
  billing is enabled. Staging resource usage can incur charges.
- Added `.firebaserc` alias `staging`; the default remains the existing app project.
- Enabled IAM API and created `app-functions-runtime`, `app-ai-runtime`,
  `app-billing-runtime`, and `app-functions-build` in staging. No service-account
  keys were created and no role bindings were added in this checkpoint.
- No functions, data fixtures, database, application or Hosting release was
  deployed in staging. Existing-project IAM and data were not changed.
- Next: provision staging resources, apply reviewed resource-scoped permissions,
  configure explicit runtime/build identities, then deploy and verify staging.

Prepared 2026-09-28. No existing Editor binding may be removed as part of initial
account creation. Staging must use a separate Firebase project and synthetic data.

Environment correction: the user may intend the current project for development.
Earlier references to it as "production" were a precaution, not a verified
environment classification. Inspection confirms it is the sole configured live
backend in this checkout, with Hosting releases, Firestore and deployed functions.
No separate production configuration or environment designation was found. Confirm
which app actual users use before choosing a staging target or changing IAM.

## Current inspected state

- Only accessible Firebase project: `apartment-management-app-776b9`.
- Six deployed Node 22 functions share the default Compute service account for
  both build and runtime.
- Three Editor principals: default Compute, default App Engine, and the
  Google-managed Cloud Services agent (`PROJECT_NUMBER@cloudservices.gserviceaccount.com`).
  The latter is a managed service dependency, not an application runtime to replace
  blindly. Verify its resource dependencies and Google's service-agent guidance.
- The signed-in deployer can create service accounts and update project and
  service-account IAM. Capability is not evidence that a policy change is safe.
- Build resources in production: `gcf-artifacts` in `us-central1`, and the two
  `gcf-v2-sources-*` / `gcf-v2-uploads-*` buckets. Grants must target actual resource
  names in the chosen project, not copy production names into staging.

## Proposed identities and grants

| Identity | Purpose | Grants |
|---|---|---|
| `app-functions-runtime` | Business callables | Firestore data access (`roles/datastore.user`); no build, IAM, Auth administration or secret access |
| `app-ai-runtime` | AI chat and import preview | Firestore data access; Secret Accessor on `GEMINI_API_KEY` only |
| `app-billing-runtime` | Subscription sync and webhook | Firestore data access; Secret Accessor on the two declared RevenueCat secrets only |
| `app-functions-build` | Build function containers | Logs Writer on project; Artifact Registry Writer on the function repository; Storage Object Viewer on the function source buckets |

Use resource-level bindings for secrets, buckets and repository. Do not grant
project-wide Secret Accessor or Storage Admin. The selected Firestore role is
data-plane access, not database administration; Admin SDK tenant isolation remains
the responsibility of the reviewed callable authorization checks.

The deployer needs `iam.serviceAccounts.actAs` on the selected runtime/build
identities. Preserve the existing Cloud Functions and Cloud Build service-agent
roles; add targeted impersonation only if the documented deployment flow requires
it and verify the exact principal. No downloadable service-account keys.

## Execution gates

1. Select/create a staging Firebase project and link the user's chosen billing
   account. Configure Auth, Firestore, Hosting and App Check independently.
2. Create the four identities; save pre-change policies and etags. Add only the
   bindings above, preserving unrelated bindings and policy versions. Re-read
   policies to verify exact resources and principals. Never replace an entire
   policy using a stale copy.
3. Set runtime identity explicitly in function source/configuration. The installed
   Firebase SDK exposes `serviceAccount`; the installed CLI does not expose a
   corresponding documented Functions build-account setting in its deployment
   conversion. Resolve and verify a supported build-account deployment path in
   staging before claiming build/runtime separation. Do not silently deploy using
   the default Compute identity or patch vendored CLI code.
4. Deploy synthetic staging fixtures and run all role/scope, App Check, billing
   retry, timestamp, offline/reconnect and function/build permission checks.
   Disable paid AI/provider execution unless staging secrets are deliberately set.
5. Prepare the production cutover against fresh runtime/build/IAM inventories.
   Move workloads first. Remove Editor grants only after confirming there are no
   other dependent workloads and both deployment and runtime succeed. Investigate
   the Cloud Services agent separately; its removal is not an automatic step.
6. Verify old identities cannot access application data/secrets through residual
   inherited or resource-level bindings. Retain rollback records; rollback must
   not restore broad access merely to bypass an unexplained failure.

## Rollback before Editor removal

New idle accounts and additive resource grants can be removed after confirming
no workloads use them. During staging failures, retain diagnostic evidence and
repair the narrow missing permission; do not grant Editor as a shortcut. After
production traffic moves, rollback requires the previous reviewed workload and
identity configuration plus checks for its required permissions.

References: [Firebase runtime service accounts](https://firebase.google.com/docs/functions/manage-functions),
[function build identity permissions](https://docs.cloud.google.com/functions/docs/building),
[Cloud Functions IAM](https://docs.cloud.google.com/functions/docs/concepts/iam).

