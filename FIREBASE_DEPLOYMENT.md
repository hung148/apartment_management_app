# Calendar backend rollout

Project: `apartment-management-app-776b9`.

Deployment completed on 2026-09-09 using `trinhdinhnguyenh@gmail.com` after switching away from the account that lacked service-account permissions.

- `mutateCalendarBooking` and `mutateCalendarTenant`: deployed successfully as Node 22 second-generation functions in `us-central1`.
- Second-generation request wrappers forward `request.data` and `request.auth`; regression tests cover this boundary.
- Both live endpoints returned HTTP 401 / UNAUTHENTICATED for signed-out smoke checks. No production test records were written.
- `firestore.rules`: compiled and released successfully after the functions were verified.
- Artifact Registry cleanup removes build images older than one day.

Staff must use the updated app; older clients cannot make protected direct writes. Authenticated end-to-end device testing remains outstanding.

`firestore.rules` is intentionally tracked. Access policies are not credentials. Keep service-account private keys and local environment secrets out of Git; `.gitignore` includes common Firebase private-key filenames.

## Deploy together

Use an authorized Firebase CLI login and the configured Node 22 runtime. From `functions`, run `npm ci`, `npm test`, and `npm run test:emulator`. The emulator configuration targets only `demo-apartment-calendar`.

From the repository root, deploy the two new callables first:

```powershell
functions/node_modules/.bin/firebase deploy --project apartment-management-app-776b9 --only functions:mutateCalendarBooking,functions:mutateCalendarTenant
```

Distribute the updated app to staff, then deploy the reviewed rules during a coordinated rollout:

```powershell
functions/node_modules/.bin/firebase deploy --project apartment-management-app-776b9 --only firestore:rules
```

Until the rules are deployed, old clients can still bypass server validation. After deployment, old clients cannot write bookings or create/change lease occupancy directly. Do not restore permissive booking rules as an app fallback.

## Access changes

- All booking writes and linked booking payments are server-owned. Ordinary invoices retain member access.
- Tenant creation and occupancy changes go through the callable and serialize against bookings on the same room.
- Collection reads require active organization membership. The previous global signed-in list permissions were removed.
- Self-promotion is blocked. Joining requires a valid invitation; owner organization/membership/invitation creation is one batch. Invitation codes cannot be listed.
- Existing memberships are not rewritten. Review existing admin memberships in the console because the previous rules allowed self-assigned roles.

## Remaining operational limits

Legacy deposits without a recorded collected amount are treated as uncollected; no payment history or exchange conversion is invented. Reconcile those records before refunds.

Bulk organization migration and deletion of protected booking history need a separate server-side administrative workflow. Organization deletion is stopped before starting a client cascade when booking history exists. The new rules reject moving documents across organizations.

The automated checks cover rules, booking concurrency, payment retries, lease conflicts, localization parity and phone-width widgets. Physical-device share/print behavior and a staging rollout still need verification. Compatible npm security updates removed high/critical findings; remaining moderate transitive dependency advisories need a separately tested SDK/tooling upgrade.
