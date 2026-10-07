# One account, one organization — proposed implementation and migration plan

Date: 2026-10-06. Status: implementation authorized by Tom; local validation in progress. Production data remains unchanged.

## 1. Recommendation and scope

Make each login belong to at most one organization. Keep organizations as the security and data boundary, with many accounts, buildings and rooms inside each organization. Open the account's workspace directly after sign-in; remove the organization-list dashboard from normal navigation.

This is a change to account cardinality, not a reason to remove `organizationId` from operational data or use the owner's UID as the organization ID. Staff still need to work on the same organization's records. Keeping existing IDs avoids rewriting bookings, leases, invoices, photos and history, and keeps ownership transfer possible.

Confirmed staff policy (Tom, 2026-10-06): staff accounts belong to one organization and cannot create organizations. Remove approved additional workplaces and cross-organization staff-sharing exceptions.

Confirmed ownership policy (Tom, 2026-10-06): remove co-ownership. Each open organization has exactly one owner account, and that owner account owns only that organization. Other participating accounts are staff with explicit role permissions. Remove co-owner invitations, negotiated ownership-control agreements and joint-approval workflows from the finished product. Preserve their historical records and resolve existing authority explicitly during migration.

Planning assumptions and remaining choices:

- The limit applies to owner and staff accounts alike. Historical co-owner accounts must be resolved before strict cutover.
- Each organization has one owner; co-ownership is removed (confirmed).
- Multiple buildings remain supported. Their picker and property-scoped permissions remain.
- Cross-organization staff sharing and additional-workplace delegation end (confirmed).
- A newly registered account may have zero organizations. Creating an empty organization automatically would conflict with staff onboarding.
- Existing multi-organization accounts require an explicit resolution plan; the system must not pick the first record or delete another organization.

The owner-only limit alternative is rejected: staff are also limited to one organization. Co-ownership removal includes a migration of existing co-owners and joint approvals; never silently convert negotiated owner authority into a staff role. Custom staff roles remain, but ownership, ownership transfer and organization closure are owner authority under the proposed replacement policy.

## 2. What the current repository actually does

Read first: HANDOFF.md, AGENTS.md; then CLIENT_ROADMAP.md, STAFF_ACCOUNT_POLICY.md and tool/STAGING.md. Newer handoff entries supersede historical notes about the VM, deployment and earlier staff policy.

| Area | Current evidence | Consequence |
|---|---|---|
| Account policy | `functions/account_policy.js` distinguishes normal/owner/staff/conflict, scans memberships, creator records and pending invitations; uses UID/email transaction locks | Reducing the creation limit alone is insufficient |
| Creation | `functions/organization_settings.js` accepts create/createLegacy and currently allows up to 20 active owner memberships | Both creation routes need the same single-organization rule |
| Entry | `lib/services/account_entry_service.dart` claims invitations, then pages through listMyOrganizations | Startup must resolve a single organization and actionable states |
| Invitations | `functions/team_claim.js` currently attempts every eligible pending invite, up to 20 | Strict mode must not let query order choose an employer |
| Dashboard | `lib/screens/dashboard/dashboard_screen.dart` and its parts host organization cards, profile/settings, Drive, agreements, create/edit/leave/close/copy/restore | Move retained actions before retiring dashboard navigation |
| Workspace | `lib/screens/team/org_shell.dart`, `org_location.dart`, `role_workspace.dart` already provide organization navigation and URL restoration | Reuse the existing workspace rather than replace daily operations |
| Governance | `functions/governance.js` and `governance_access.js` support co-owners, sensitive controls, joint approvals and staff sharing | Replace with single-owner authority; retire co-owner/joint-approval/sharing activation paths after migration |
| Restore | `organization_settings.js` restores close-revoked memberships in batches | Every restored account must be checked, not only the owner initiating restore |
| Deletion/transfer | `functions/account_deletion.js` plans across memberships and transfers/closes organizations | Deletion needs the same locks and cardinality checks, including interrupted work |
| Drive | `functions/drive.js` prefers an organization connection, then active owners' account connections | Keep existing token/folder references; choose a clear owner-change policy |
| Rules | `firestore.rules` refuses direct organization creation, but retains legacy membership/data update/delete routes | Legacy writes can make a binding stale unless coordinated with migration/rules |
| Device copy | `lib/services/read_cache.dart` caches reads per account/request; handoff describes workspace/calendar copies | An old cached workspace must not become current authorization |
| Copy | Current organization copy covers a defined subset, omits staff/team/activity/assignments/operation ledgers | It is not a complete organization merger |
| Release | Handoff records grouped app/heavy functions in Singapore and older production clients using US endpoints | Preserve published routes and coordinate client/backend/rules rollout |

This is source review, not a live inventory. Production/staging account counts, conflicts and current release state have not been queried. The working tree already has substantial changes; implementation must preserve them and establish a reviewed baseline first.

## 3. Exact account rules to implement

Use **at most one bound organization**, including accounts temporarily unable to work there. A binding is lifecycle identity; membership is current authorization.

| State | Occupies the account's organization slot? | Entry behavior |
|---|---|---|
| No membership/binding | No | Create organization or accept a valid invitation; profile/sign-out available |
| Active owner/staff | Yes | Open workspace with current permissions |
| Historical co-owner awaiting migration | Requires explicit resolution | Preserve agreed transition access until controlled cutover; no silent promotion/demotion |
| Waiting for role / assignmentRequired | Yes | Explain waiting; refresh, contact organization, authorized leave |
| Suspended member | Yes | Explain suspension; no workspace data or mutation; suspension cannot be bypassed by creating elsewhere |
| Explicitly revoked / left | No, once detach transaction completes | Access-ended page; may later join/create elsewhere |
| Pending invitation | No active binding | Invitation selection/acceptance; never silently replace a binding |
| Closed organization in retention | Yes by default | Closed/recovery state; preserve restoration without conflicting attachments |
| Purged organization | No after verified release | No-organization state; keep minimal audit evidence |
| Migration conflict | No normal operational entry until resolved | Explain conflict and resolution; no arbitrary automatic selection |
| Account deletion in progress | Block new attachment | Resume deletion or show a recoverable error |

Closed-organization reservation is a proposed conservative policy. If Tom wants immediate reuse after closure, restoration must skip/reinvite accounts now bound elsewhere and explicitly report them. It cannot bulk-reactivate everyone as it currently does. Recovery UI must not promise the old team will return unchanged.

Pending invites should not reserve a login indefinitely. If there is exactly one valid staff pre-approval and no binding, preserve automatic claim if desired. With multiple target organizations, require selection; once selected, leave other invitations declined/conflicted according to an explicit policy. Check inviter authority, email verification, expiry, role and free staff profile at acceptance.

Changing employer means detach from the old organization, then accept the new one; not a workspace switch. Owners must transfer authority or close according to existing governance first. Staff leave must be explicitly defined for suspended and waiting accounts. An unavailable network is never evidence that the slot is free.

## 4. Data and server design

Add a server-owned binding collection, proposed `accountOrganizations/{uid}`:

- `organizationId`, lifecycle `state`, `revision`, `boundAt`, `updatedAt`, and a minimal last transition/operation reference.
- Record the source of a transition for audit (create, invite, ownership transfer, restore, migration). Do not copy role grants into the binding as a second permission authority.
- Keep memberships with existing `${uid}_${organizationId}` IDs, `ownerId` fields, roles, grants, building scope and history. The existing `ownerId` naming means member-account UID in these records; do not rename it across the code in this release.
- Keep organization IDs, creator history and transfer metadata. `createdBy` is history, not proof that the creator still owns the organization.
- Keep existing UID/email account-policy locks, or replace them only after proving all transition paths share an equivalent serialization mechanism.
- Deny all client writes to bindings. Prefer callable entry projections rather than direct binding reads.

Create central transaction helpers: resolve binding; assert target is available; attach; detach with expected revision; reconcile known historical inconsistencies. All Firestore reads must precede writes in a transaction. Single-document checks serialize concurrent empty-account attaches; locks coordinate pre-sign-in email invitations and UID transitions. Email lookup is advisory until verified authenticated UID acceptance.

Every operational server request must verify authenticated UID, binding matches request organization, valid membership/status, organization lifecycle/version and current permission/scope. Keep building/record restrictions and sensitive-field projections. A binding does not grant access on its own. Apply this in shared authorization paths and audit any handler that bypasses them, including Drive and organization settings. Reject forged organization IDs even when a stale membership still exists.

Use operation IDs and request fingerprints for mutations. A retry of a completed attachment returns its previous result and never reattaches an account that subsequently left. New transitions check current binding revision; detach cannot clear a newer binding. Record transitions and business changes atomically where possible. Multi-batch close/restore/deletion must use explicit progress and resumable operation records rather than pretending an entire organization fits one transaction.

Introduce an entry result, proposed `resolveMyOrganization`, with explicit state, one authorized organization summary or invitation summaries, permitted next actions and policy revision. Return no private organization bank/tenant details at entry. Keep listMyOrganizations and old callable shapes for published clients until retirement is approved; they must obey server policy rather than provide a bypass. Avoid renaming/moving existing grouped callable routes.

## 5. Every transition that must change

| Transition | Required behavior |
|---|---|
| Create/createLegacy | Atomically assert no binding and create org + owner membership + binding + audit + operation result; reject a second organization regardless of role |
| Invite/pre-approve | Same-organization updates remain possible; explain incompatible known binding; final acceptance always rechecks UID and email |
| Claim/accept invitation | Attach only one target; two simultaneous accepts have one winner; retries are harmless |
| Access request / approve / direct staff assignment | Audit all team.js actions that create or reactivate memberships; bind in the same transaction |
| Role edit | Preserve the same binding; current scopes remain; do not accidentally detach waiting/unsupported-role accounts |
| Suspend/reactivate | Suspension retains binding; reactivation verifies it still targets the organization |
| Revoke/leave | Revoke membership and release binding consistently; preserve history and staff attribution |
| Co-owner agreements | Refuse new proposals and old pending activations for cut-over organizations; migrate existing co-owners explicitly; retain history without allowing authority to reactivate |
| Transfer ownership | Controlled handover replaces the single owner atomically; recipient belongs to this organization or enters through a controlled attachment, never displacing another binding. Agree whether the former owner becomes staff or leaves. No interim two-owner or ownerless open organization; recipient consent and retry safety are required |
| Staff share/additional workplace | Reject new proposals AND activation of old pending proposals; prevent stale clients from reviving shares |
| Close | Mark inaccessible first; preserve proposed retention bindings; revoke operational access resumably |
| Restore | Check each account binding and membership history; respect prior independent revocations; lock against purge and simultaneous attachment |
| Purge | Release only bindings still referencing the purged organization; never clear a newer organization; include new collections in lifecycle inventory |
| Account deletion | Prevent concurrent join/create; resume safely; clean binding and account Drive credentials under an explicit provider-retention policy |
| Email change / provider linking | UID remains identity; synchronize invitation/member email safely; verified email cannot silently move an account |
| v1-to-v2 migration | Preserve binding; recognize current ownership and missing/legacy memberships; block ambiguous cases for review |
| Organization copy/import/admin tools | Remove cross-org copy from normal product UI under strict policy; maintenance tooling must never mint extra account access |

## 6. UI and dashboard replacement

Normal flow: sign in -> resolve account -> open its workspace. First-time owner: no-organization entry -> create -> calendar. Invited staff: accept/pre-approval -> workspace or waiting screen. A restricted role without calendar access opens its first authorized section rather than an empty calendar.

Reuse OrgShell/RoleWorkspace. Keep organization name and role-aware sections, Calendar and Staff management direction from the handoff, other authorized operational pages, and the building picker. One organization can still represent several properties.

Before removing dashboard entry, relocate:

| Existing action | Proposed destination |
|---|---|
| Name/phone/email/password, language/theme, sign out, account deletion and any remaining account/device preferences | Account menu reachable from workspace and all blocked/entry states |
| Organization name/contact/address/tax/bank details | Organization Settings, permission-gated |
| Payment receiving accounts | Existing organization payment-account page |
| Google Drive | Settings -> Integrations, retaining owner-account connection semantics in the first release |
| Co-owner agreements/invites and joint approvals | Remove operational entry points; preserve historical evidence through restricted audit/recovery access if needed |
| Ownership transfer | Owner-only organization lifecycle action with recipient consent; keep separate from co-ownership |
| Close/restore | Organization lifecycle/recovery page, accessible even when normal workspace is closed |
| Staff leave | Account/organization membership action with consequences explained |
| Create | Only no-organization onboarding; hidden/disabled when bound and server refused regardless |
| Join | Verified invitations/access requests; no general organization switcher |
| Organization copy/migrate menu | Retire from everyday navigation; migration is separately controlled |
| Organization cards and choose-workplace list | Remove for resolved strict-policy accounts |

Retain deep links `/org/...` initially. Resolve access before displaying saved organization data; matching links restore section/property/record. Wrong-organization links show an access message and a route to the user's own workspace, without leaking the other name or data. Browser Back must move through pages and exit naturally; no dashboard bounce or auto-open loop. Handle notification links, refresh, sign-out, account switching and app restoration.

Retain cache keys scoped by account AND organization. Entry may use saved state for shell appearance only, with a visible checking state. Unknown/conflict/revoked accounts cannot obtain working controls from cached role grants. Clear inaccessible organization data and listeners; prevent a late result from the previous login populating the new login. Offline reads, if retained, must be clearly stale and mutations remain server-checked. Define the cached-data exposure policy explicitly: offline revocation cannot be detected instantly.

Preserve current loading speed work: avoid reintroducing serial claim/list/settings/team/building calls. Combine entry information where practical, but measure before/after rather than claim that removing the dashboard alone solves cold starts.

## 7. Google Drive decision

First release: move the connection screen, preserve `driveAccounts/{uid}`, `driveConnections/{org}`, existing provider precedence, folder IDs and photo references. Do not copy OAuth tokens into a new schema or move external files merely because navigation changed.

Document which connection is being used and who can reconnect/disconnect. Before removing co-owner fallback, audit organizations whose photos/imports depend on a co-owner's Drive; arrange continued file access or an explicit replacement connection. Test single-owner transfer, historical co-owner connection migration, old organization connection needing reconnect, revoked consent, interrupted upload and account deletion. Existing files live in the original person's Drive; transferring app ownership does not transfer Google file ownership. A replacement owner may need reconnect/migration steps. Google Sheet import uses the same connection path and belongs in this inventory.

If an organization-owned connection is desired later, treat it as its own provider migration, with explicit credential authority and file-access continuity. Do not mix it into the account-cardinality migration by default.

## 8. Existing-data migration

### 8.1 Read-only audit before implementing destructive decisions

Build a dry-run report separately for local, staging and production when authorized. Do not copy real tenant data or credentials into staging. Report aggregate counts and minimal account/org references needed for restricted review:

- Active, waiting, suspended, revoked and close-revoked memberships per UID; owner/co-owner/staff combinations.
- Creator records versus current ownership, transferred organizations, orphaned memberships and missing organizations.
- Multiple pending staff and co-owner invites, shares, delegated workplaces, requests, expired and partial operations.
- Closed/restoring/purging organizations and retention deadlines.
- v1/v2 counts, unsupported versions, missing organization fields and cross-linked children.
- Accounts with zero, one or multiple candidate organizations; ownership stranded by a proposed detachment.
- Drive connection ownership and file/folder dependency references, never tokens.

### 8.2 Resolution classes

1. Exactly one unambiguous organization: prepare automatic binding backfill with evidence.
2. No organization: prepare no-organization entry; do not create one.
3. Several organizations representing one real business: optional merge project, after data/security approval.
4. Several separate businesses: choose one for this login; transfer the other organizations to eligible separate logins. Different email addresses may be needed; do not clone a Firebase UID or silently move a whole team.
5. Shared staff: choose a home organization, revoke destination access consistently and replace pending shares/invites; acknowledge loss of the sharing feature.
6. Every organization with co-owners: explicitly select its one retained owner, using current ownership and agreements as evidence rather than assuming createdBy is correct. For each former co-owner, approve a scoped staff role or detach/transfer as appropriate; resolve their single-organization binding. Preserve original grants/controls in restricted migration history, never grant an unrestricted manager role by default. Cancel/supersede pending agreements and joint approvals without executing them. Check Drive dependency and last-owner recovery before cutover.
7. Suspended/closed/partial/deleting records: resolve lifecycle first; do not treat hidden directory entries as absence.
8. Orphaned or contradictory records: manual recovery report; never infer authority solely from createdBy.

### 8.3 Merging is optional and substantially harder

Do not use the current copy-and-close feature as a full merger. Its COPY/SUB lists omit team, staff, activity, housekeeping assignments and operation ledgers. A merger must separately enumerate every collection/subcollection and remap references, including room/building/tenant/booking IDs, occupancy, utility scopes/readings, tariffs, fees, invoice/payment links, staff attribution, photos, Sheet imports, audit history and deduplication ledgers.

Names are not IDs. Handle duplicate room/property names, role IDs, staff identities, payment accounts and tariff conflicts. Reconcile occupancy/calendar overlaps and billed readings before enabling writes. Preserve financial history, totals and original actors; combining organizations must not broaden employees' property/record visibility by accident. Never recompute historical negotiated prices or paid invoices as migration work.

Default path should be binding existing organizations without moving operating data. Merge only where a reviewed real-business reason exists.

### 8.4 Applying backfill

Version the migration manifest and record expected source revisions. Snapshot/back up affected records through an approved process; restrict access and exclude secrets from human-readable reports. Rehearse with synthetic copies in emulators. Use bounded, resumable transactions and a journal; recheck revisions before each apply. Freeze conflicting account transitions during each account's cutover, not the whole application indefinitely. Avoid a large one-shot transaction.

After apply, verify binding-to-membership consistency, single-organization cardinality, valid owners and scopes, record/reference counts, financial totals and unchanged operational IDs. Unresolved accounts stay visibly unresolved. Record a before/after diff and a rollback manifest. Never schedule source organization purge simply to hide an unresolved conflict.

## 9. Work packages and dependencies

### Phase A — Decisions and inventory

Staff restriction, removal of multi-workplace exceptions and removal of co-ownership are confirmed. Agree closed-slot reservation; staff leave and subsequent account eligibility; ownership handover/former-owner status; invitation selection; multi-org and existing co-owner resolutions; and whether any businesses actually need merging. Create the read-only audit and collection/transition inventory. Review the existing dirty working tree and baseline failures. Deliver an approved policy table and migration manifest proposal. No rollout before these decisions.

### Phase B — Invariant and server compatibility

Add binding model/helpers and lifecycle integration behind a server-controlled policy mode. Add behavioral tests before implementation for newly required rules. Update every attach/detach path above and shared authorization, rules, purge/deletion and maintenance tools. Support existing callable routes. Shadow-audit legacy accounts without silently restricting them until rollout policy is agreed. New strict-policy accounts must never bypass the limit through old clients.

Exit: fake-Firestore tests plus Auth/Firestore/Functions emulator tests prove cardinality, authorization and concurrency; existing server regression passes; no client navigation change yet.

### Phase C — Entry and retained settings

Implement explicit entry states and relocate account/Drive/governance/lifecycle actions. Update TeamService, entry/settings/deletion services, preview stores and fixtures together. Open the existing workspace directly for strict accounts. Preserve legacy/conflict recovery paths until those accounts migrate. Update English/Vietnamese wording and stable keys.

Exit: realistic widget flows and inspected actual-font screenshots pass; all previously dashboard-only actions remain reachable for the correct roles.

### Phase D — Migration rehearsal and staging

Seed realistic synthetic conflicts and historical v1/v2 records, rehearse backfill/rollback and interrupted recovery locally. Resolve staging accounts via reviewed manifests. Run the full Flutter suite sequentially (`--concurrency=1`), server and relevant emulator/rules suites; then one batched staging deploy. Verify real Google sign-in, email verification, Drive, App Check and hosting plus final normal/restricted-owner/staff flows. Preserve Singapore app/heavy routing and the no-always-running-instances decision.

Exit: scenario evidence, migration reconciliation and recovery pass. Record remaining gaps honestly; staging completion is not production authorization.

### Phase E — Production preparation and rollout

Read-only production audit, approved per-account resolutions, safe backup/rehearsal, release compatibility inventory and explicit deploy/migration authorization. Production v1-to-v2 work remains a coordinated prerequisite for any legacy paths the strict model cannot safely cover. Do not combine a blind production data conversion with this UX rollout.

Deploy backward-compatible backend/rules readiness; backfill resolved accounts; publish client changes; enable enforcement in reviewed cohorts. Old clients may retain familiar entry UI temporarily, but server attachment checks already apply to strict accounts. Maintain required US production endpoints until published app versions no longer need them. Monitor cardinality violations, invite failures, access denials, restore/deletion failures and startup latency without logging personal/secret data.

Exit: actual live checks and Tom's acceptance. Update HANDOFF/roadmap with verified completion and remaining gaps.

### Phase F — Retire old architecture

Only after migration and old-client support criteria are satisfied: remove normal dashboard organization lists, additional-workplace UI/grants, sharing flows, obsolete copy controls and unused compatibility paths. Keep financial/audit history and useful regression tests. File and deployed-endpoint deletion require Tom's instruction under HANDOFF. Treat code retirement separately from data destruction.

## 10. Validation matrix — required situations

This is the required coverage checklist, not a claim that every combination has
been verified. The delivery evidence below records completed checks and remaining
gaps separately.

| Scenario group | Cases | Evidence required |
|---|---|---|
| Roles | One owner, manager, receptionist, housekeeper, accountant, investor, custom grants, managed/own record scopes, unsupported role; historical co-owner migration with limited controls | Server projection/authorization tests, role-aware widget entry; migration must preserve or explicitly withdraw historical authority |
| Access loss | Suspended/revoked/removed role, organization close, foreign org ID, missing binding/member/org, malformed version, account deletion | Emulator/rules tests; stale cache/live refresh behavior |
| Onboarding | New owner, one/multiple invites, expired/revoked invite, unverified/missing email, inviter loses rights, occupied staff profile | Unit + emulator + widget flows; real Google/email on staging |
| Concurrency | Create/create, create/join, join/join, transfer/join, transfer/transfer, stale co-owner agreement activation/cutover, restore/join, revoke/reactivate, detach/new attach, purge/restore, delete/join, email change/accept | Actual emulator concurrent requests; one valid winner; exactly one owner; journal/retry assertions |
| Retries | Double taps, timeout after commit, reused operation ID with changed payload, interruption between close/restore/delete batches, replay after later leave | Unit + emulator assertions; repeatable progress and no reattachment |
| Legacy | v1 only, v2 only, mixed membership, transferred creator, missing membership, child missing org ID, dangling/cross-linked records | Migration fixtures, deny-bypass rules tests, reconciliation |
| Lifecycle | Sole owner cannot leave without handover/closure, historical co-owner recovery/migration, transfer to same-org staff with recipient consent, close/reopen, retained slot, expired retention, partial purge, historical staff bound elsewhere | Governance/settings/deletion/purge tests and local flows |
| Business records | Long/short stays, lease roommates, deposits/refunds, period/utility invoices, service fees, problems/photos, housekeeping, rates, staff attribution, imports, statistics and money | Unchanged-ID assertions, totals/reference reconciliation, representative full flows |
| Entry/navigation | Root, deep link, reload, record no longer exists, unauthorized section, Back, account switch, sign out, notification link, late async response | Entry/router/workspace widget tests and emulator app |
| Cache/network | Empty cache, valid stale cache, revoked cached role, offline first load, network timeout, recovered network, failed binding lookup | Cache tests + UI assertions; no free-slot inference on failure |
| UI content | No buildings/rooms, populated buildings, long org/property/tenant names, waiting/error/retry, forms preserve typed data, blocked actions remain reachable | Actual-font rendered screenshots and manual inspection |
| Calendar shell | Empty/occupied rooms, long-stay badges, hourly prices, long labels and overlaps; loading/error; embedded and standalone | Existing calendar regression plus representative inspected renders when shell/shared layout changes |
| Responsive | English/Vietnamese, narrow phone, landscape, desktop, 100/130/200% text; relevant light/dark themes | No layout exceptions AND inspect clipping, controls, movement and reachability |
| Providers | Google sign-in, real email, App Check, Drive reconnect/fallback/upload, Sheet import and real hosting reload | Staging only for provider behavior; synthetic backend tests do not prove browser attestation |
| Old clients | Legacy call shapes, old create/claim/share attempts, production US routes, grouped app route | Compatibility tests and release inventory, then authorized live checks |

Target existing suites in account_policy, organization_settings, governance, team, account_deletion, organization_purge, drive, team_access/read, request_security and firestore integration; Flutter account_entry, team_organization_entry, role_workspace, ownership_agreements, problem_photos, read_cache and settings/deletion/navigation. Add genuine concurrency and migration reconciliation coverage rather than replace them with implementation-string checks. For any discovered bug, reproduce and keep a failing regression before fixing.

Run tests/build/screenshots sequentially on this machine. Run full regressions for
this cross-cutting change. Distinguish automated results, rendered visual
inspection, local full-flow verification and staging provider checks in delivery
reports.

## 11. Rollback and acceptance

Rollback must address backend, client and data separately. Keep old client routes and original operational IDs. Binding backfill should be additive until accepted; preserve revoked/history evidence and migration journals. Disable new strict onboarding if a defect is found, without granting a second organization or bypassing current authorization. A client rollback cannot safely restore multi-org behavior after membership resolution without reviewing the data manifest.

For unresolved lifecycle corruption, block the affected account with an actionable recovery state; do not automatically restore broad permissions. Before undoing a migration, stop affected writes, compare current revisions and preserve post-cutover activity. Do not blindly replay a backup over bookings/payments created afterward. Organization merges and external Drive moves have more difficult rollback, which is another reason to keep them separate.

Completion means: each strict account has at most one valid binding; all attachment routes enforce it transactionally; normal login opens the correct authorized workspace; retained settings/recovery actions are reachable; migration reconciles without losing history or widening scopes; old client compatibility is documented; the required local and provider checks have evidence; remaining gaps are explicit; Tom accepts the finished behavior.

## 12. Suggested first implementation slice

After the product choices are confirmed, start with the read-only inventory and server binding tests/helpers. Prove create-versus-invite concurrency locally before changing dashboard navigation. Then add direct entry and move retained dashboard actions. This sequence makes the simplified UI rest on an enforced account rule and avoids a large data rewrite at the start.

## 13. Confirmed merge dialog and implementation changes

Tom confirmed that staging organizations should merge together. Production records
stay in place until their owner responds to a merge dialog. The dialog asks for a
unified name and lets the owner select each organization for merging or deletion.
All are selected initially; at least one must remain selected. Deletion requires
an additional explicit checkbox and names the excluded organizations in the list.
Excluded organizations close immediately and enter the existing 30-day purge
retention. They cannot be restored from the ordinary merge dialog. There is no
automatic production merge or deletion.

The instant merge is a single Firestore transaction. It rechecks every original
organization, sole ownership, memberships, account deletion state and policy
locks. A repeated operation returns its original result; changed choices/name
cannot reuse the operation. A stale organization list requires reviewing again.
The retained organization keeps its ID and settings; its name changes. A single
existing organization Drive connection determines the retained ID, otherwise the
first sorted selected ID is retained. Original organization details remain in
archived source documents. Operating record IDs, property IDs and parent history
paths stay intact except histories beneath organization-keyed utility meters,
which are copied to their new meter path with the same reading IDs. Organization
references change to the retained ID. Scoped fees, utility meter/tariff and
custom-role keys are rebuilt without deleting original evidence. Utility billed
intervals, invoice links and Drive photo references remain intact.

Staff retain their original property lists. Explicit all-property grants become
managed-property grants. Organization-wide management/export/import/Drive/activity
permissions are withdrawn until the owner assigns them deliberately. Duplicate
active memberships for the same staff account require access review rather than
combining grants. Custom roles receive separate stable IDs so colliding role names
do not overwrite their definitions. Pending invitations are revoked and must be
reissued by the owner. Mixed v1/v2 merges, several retained Drive connections,
cross-linked records, historical co-owners and oversized transactions require
review; refusal occurs before any write. An instant merge is capped below
Firestore's transaction limits (450 planned writes including room for locks,
7 MiB payload); larger accounts require a reviewed maintenance migration.

Ownership handover is separate from co-ownership: nominate an active staff member,
offer expires after seven days, nominee explicitly accepts, and one transaction
switches ownership, revokes the former owner's membership and releases their
account binding. Cancel/retry/expiry/access loss are rechecked on the server.

Additional verification situations: keep all, delete some, keep only one, select
none; empty/invalid/long unified name; preview failure; pending submission and
double taps; lost response followed by exact retry; changed source list; staff
scope widening; custom-role/keyed-fee collisions; old deep links and invitation
codes; legacy children without organizationId; nested histories; connected Drive;
purge removes only excluded data; closure/restore cannot revive merged sources;
handover wrong recipient/expiry/revocation/deletion/races; local EN/VI phone,
landscape, desktop, 100/130/200% text, populated dialog and actual-font inspection.

## 14. Verification and rollout evidence (2026-10-06)

Implementation is authorized; production data and deployment remain unchanged.
Read-only inventory found four production owner accounts with multiple legacy
organizations, and no historical co-owners or live sharing agreements. The new
client offers the merge/delete dialog to those owners when released. Selecting
legacy organizations that contain staff requires migration review: legacy
permissions cover the whole organization and cannot safely carry into a larger
merged organization. Mixed versions and oversized accounts also need a reviewed
maintenance migration. No automatic production merge/deletion is scheduled.

The staging owner's three organizations passed a read-only rehearsal: 153 records,
164 planned writes, no deletion choices. The retained Test v2 organization keeps
its existing Drive connection. Separate synthetic seed organizations belong to
another owner and are not included in that user's merge authorization.

Completed local coverage includes actual Firestore emulator transactions/rules
(99 passing integration tests), create/invite races, forged binding writes,
foreign organizations, retired co-ownership, owner-only legacy deletion and
archived source denial. Server unit coverage includes merge retry identity,
unchanged operating IDs, utility-meter rekeying and nested reading/billing
history, scoped fee keys, custom roles, staff scope narrowing, explicit deletion
confirmation, retained-target purge safety, empty/stale selection and refusal
before writes. Handover tests cover recipient consent, retries, cancellation,
expiry, revoked participants and a recipient already bound elsewhere.

Flutter checks cover direct entry versus conflict/recovery states, preview errors,
lost-response retries, disabled controls during submission, merge/delete choices,
owner nomination and nominee acceptance, and populated workspaces in English and
Vietnamese at phone/landscape/desktop sizes and 100/130/200% text. A reproduced
landscape keyboard overflow was fixed by scrolling the whole dialog, including
its actions; the retained regression checks both name and action reachability.
Rendered Roboto screenshots were inspected for the desktop merge/delete dialog
and the narrow Vietnamese dialog at 200% text. Scrollable content is intentional
at large text sizes; deletion confirmation and the red combined action remain
reachable. Final full-suite and staging results will be appended after completion.

Final local runs: full Flutter suite 619/619; the isolated final label fix and
dialog scenarios 22/22; full server unit suite 332/332. Dart analysis completed
with zero errors and 420 warning/info items. The web release build succeeded.
Staging backend release `2026-10-07t00-47-01-811z`, Firestore rules and hosting
were published. Backend inventory verified four active endpoints and two denied
unauthenticated/App Check probes.

The genuine signed-in staging browser displayed the new dialog. With a nonempty
name and an unchecked organization, submission remained disabled without the
separate deletion confirmation. All three were then reselected and merged into
Staging Unified without deleting any. Direct workspace entry opened the retained
Test v2 ID; all four properties appeared in its picker. The account audit now
shows one active owner membership and one binding. Hash comparison matched all
146 captured business/history records at their expected retained/rekeyed paths,
excluding intentional organization/meter/role references; amounts, dates, other
fields and nested history data were included. The existing organization Drive
connection remains present, and an existing Drive problem photo rendered in the
merged workspace without reconnecting. Another owner's synthetic seed fixtures remain
unmerged. A deletion's eventual real-cloud purge was not executed in this check;
the retention/purge behavior is covered locally.

Coverage limits: these checks do not establish every permutation in section 10.
The complete local Auth/functions/browser stack flow, real email/Google sign-in,
all old-client versions, all calendar content/theme combinations and a reviewed
large/mixed/legacy-staff production migration are not verified by these results.
The existing account-deletion ownership transfer remains its historical immediate
transfer flow; the new standalone ownership handover requires recipient consent.
