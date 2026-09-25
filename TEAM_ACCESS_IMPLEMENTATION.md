# Team & access implementation

## Progress

- [x] Explicit role/permission foundation in Dart and Node.
- [x] Separate staff profile, with optional account linkage.
- [x] Pure migration proposal: legacy members require assignment; no database writes.
- [x] Backend team mutation handler, invitation/access-request flow and atomic audit events.
- [ ] Team read API and client integration.
- [ ] Integrate authorization across Firestore, callable functions and queries.
- [ ] Team directory and staff details, English/Vietnamese.
- [ ] Role-specific workspaces and restricted data views.
- [ ] Activity history screens and mutation coverage.
- [ ] Migration rehearsal, full regression and visual verification.
- [ ] Coordinated production cutover.

## Phase 1: model and policy testing

Run from the repository root, sequentially:

```powershell
flutter test test/team_access_test.dart --concurrency=1
node --test functions/test/team_access.test.js
```

Expected checks: all roles obey selected building scope; suspended/revoked users
have no access; unknown and legacy roles fail closed; receptionists cannot refund
or override prices by default; housekeepers cannot view booking/financial data;
administrators cannot change owners or other administrators; overrides cannot
grant team management or bypass building scope; staff identities survive without
an account. Migration proposals do not modify inputs, promote legacy members, or
overwrite existing v2 assignments.

These are policy unit tests, not proof of backend enforcement. The foundation is
not wired into existing screens, rules or callable functions yet. Existing live
access and member creation remain unchanged until the coordinated integration.
No migration or deployment has been performed.

Validation on 2026-09-25: full Flutter suite passed (78 tests, including 10 new
team-policy/staff tests). Existing calendar server tests plus new team-policy
tests passed (15 total). After tightening malformed-scope handling, the eight
server-policy tests passed again. No UI changed, no screenshots were needed for
this phase, and no live-account or Firestore-emulator verification was performed.

## Integration constraints

- Never activate only client-side restrictions and describe them as security.
- Firestore reads return whole documents: sensitive guest data requires separate
  projections/documents or server-mediated reads for restricted roles.
- Housekeeping role currently defines capabilities, not an implemented task module.
- Every operational server call must bind the membership to authenticated user,
  organization, and target building; role checks alone are insufficient.
- Owner-only operations and administrator peer restrictions need explicit checks
  beyond the manageTeam capability.
- A migration preview must be reviewed before removing legacy access; no silent
  privilege grants or automatic staff-account linking.
- UI checks must cover en/vi, narrow phones, desktop, landscape, 130%/200% text,
  realistic populated fixtures, layout exceptions and actual screenshot review.

## Phase 2: backend team mutations

`mutateTeam` is registered in the Functions entry point but has not been deployed.
It requires `organizations.accessVersion == 2` and an explicit active v2 membership.
Do not manually enable it in production: legacy rules, reads, and operational
callables still need the coordinated authorization migration.

Implemented actions:

- `saveStaff`: create/edit a profile without granting account access. Employment
  inactivity does not automatically suspend a linked account; use `setAccess`.
- `invite`: explicit role/scope, verified-email recipient binding on acceptance,
  seven-day expiry, existing unlinked active staff profile.
- `acceptInvitation`: link account/profile and activate approved access atomically.
  Existing memberships are never overwritten by an invitation. Inviter access and
  building existence are checked again at acceptance.
- `revokeInvitation`: close a pending invitation.
- `requestAccess`: valid join code creates a pending request, not a membership.
- `reviewRequest`: approve with an explicit role/scope and staff profile, or reject.
- `setAccess`: change another user's role/scope or suspend/revoke access, with a
  required reason. Self, owner and administrator-peer protections apply.

Each action requires an `operationId` retained by the caller across retries.
Exact retries return the previous result without duplicate records/events;
reuse with changed input is rejected. Privileged retries recheck actor access.
Role defaults as well as overrides cannot exceed the granting administrator's
permissions. Team administration currently requires all-building scope.

New `staffProfiles`, `teamInvitations`, `teamRequests`, `teamOperations` and
`teamActivity` collections remain inaccessible to direct clients under the
current rules. The future read API will return authorized views.

### How to test

From the project root:

```powershell
node --test functions/test/calendar.test.js functions/test/team_access.test.js functions/test/team.test.js
```

For real Firestore transactions and rules, from `functions`:

```powershell
node node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --config ../firebase.emulator.json --project demo-apartment-calendar --only firestore "node --test --test-concurrency=1 test/firestore.integration.js test/team.integration.js"
```

The integration tests require the emulator and refuse to run without it. The
demo project avoids production access. Fixtures are synthetic.

Expected scenarios include invitation recipient verification, expiry/revocation,
duplicate/concurrent acceptance, no access before request approval, rejection,
cross-organization references, forbidden privilege grants, protected roles,
access suspension, atomic audit records, and denied direct client writes/reads.

No new screens exist in this phase. Legacy shared-code member creation in the
existing app is not yet replaced; only the new handler uses approval requests.

Validation on 2026-09-25: 33 server unit/handler tests passed, including the
existing calendar tests. All 13 Firestore integration tests passed (10 existing,
3 new), with real transaction retries and direct-client denials. The emulator
was stopped afterward. Expected PERMISSION_DENIED output comes from negative
security tests. No Flutter files changed in phase 2, so the prior 78-test Flutter
result was not rerun; no UI or live-account verification was performed.
