# Exclusive owner / staff accounts — implementation checklist

Status: implementation underway; staging verification pending. Authorized to deliver this stage, then AI/subscription removal, then the remaining client roadmap. See DELIVERY_QUEUE.md.

## Latest direction — implementation authorized
Tom wants BOTH co-ownership and explicitly approved staff sharing between separate companies.
The agreement implementation now adds a stable company identity and explicit cross-company sharing. The earlier single-owner baseline below remains historical context. Staging verification must finish before proceeding to the next stage.

Proposed model:
- Company identity must be a stable company/group ID, independent of any owner's account.
- Co-ownership is a company-level relationship, separate from an ordinary staff role.
- Tom chose configurable co-owner authority by agreement, like Vai trò và phân quyền;
  do not hard-code all co-owners as full access or reserve all sensitive actions for
  a primary owner. Expose an explicit list covering operational permissions,
  finances, staff/roles, cross-company sharing, co-owner management, ownership
  transfer and organization deletion.
- Implemented agreement workflow (awaiting live verification): invited co-owner reviews the
  exact permission agreement; acceptance activates it. Permission changes cannot
  silently expand the editor's own authority. Sensitive actions may offer joint
  approval instead of a simple toggle. Define change-consent/quorum, last-owner
  recovery and disagreements before implementing destructive workflows.
- Separate companies share a specific staff account only through an explicit agreement
  approved by both sides. Each organization still controls role, property scope and status.
- Sharing approval must not reveal either company's tenants, finances or staff directory.
- Revoking a share ends only access dependent on that share; preserve home-company access
  and historical records. Define expiry, pending invites, departure, ownership changes,
  concurrent approval/revocation and account recovery before implementation.
- Existing mixed owner/staff accounts require an explicit migration/recovery decision.
  Co-ownership cannot simply reuse the staff role: that would conflict with current
  owner/staff account separation, role hierarchy, account deletion and hand-over rules.

## Current implementation (earlier approved scope)

## Required situations
- Signed-out callers refused; Google and password sign-in use the same account policy.
- Account owns a v1/v2 organization: staff invitation/add/email correction/request acceptance/access activation refused. Closed organizations remain ownership until purged. No automatic deletion.
- Active, waiting, or suspended staff cannot create organizations. Revoked memberships do not block normal use; another workplace still does. Deleted organizations ignored.
- Pending unexpired staff invitations reserve a verified email for staff; expiry/revocation releases it. Email changes and invitation acceptance recheck ownership.
- Existing mixed accounts: show conflict, no new ownership or staff activation; keep owner recovery controls, no silent data deletion.
- One staff email belongs to one employer (current owner UID). Other-owner invitations/activation are refused, including suspended/waiting staff and pending invitations. A second organization under the same owner requires the owner or a delegate with `assignAdditionalWorkplace` in both organizations. Only the owner can grant/assign a role containing this permission; no non-owner template receives it by default. Team-management authority remains required for the destination operation.
- One accessible workplace opens directly; several explicitly approved organizations show a workplace chooser; no accessible workplace shows waiting/suspended information, refresh/settings/sign-out remain reachable.
- Server repeats checks regardless of hidden buttons; direct legacy organization creation denied. Normal legacy creation moves to callable.
- Concurrent creation/invitation/acceptance/reactivation use shared UID/email transaction locks; retries keep operation identity; interrupted loading fails closed and offers retry.
- Ownership transfer checks other workplaces; restore rechecks staff status. Legacy ownership recognized by current creator/transfer and membership.
- All touched fields: memberships role/status/org/user/email, organization creator/transfer/closed state, pending invitation email/status/expiry. Historical staff profiles and login accounts retained.
- English/Vietnamese, populated long workplace names, empty/loading/error/conflict, narrow phone/desktop/landscape, 100%/130%/200% text; screenshots with actual fonts; no Flutter layout exceptions/clipping/unreachable controls.

## Verification
- Server unit suite: 176 passed, including delegated permission, same/different owner, inactive approver, owner-only delegation, withdrawn approval before acceptance, account creation, legacy callable creation, and replay tests.
- Emulator suite: 13 passed earlier in this task, covering real concurrent invite/create races and direct-write rules. Delegation-specific tests use the fake Firestore transaction harness.
- Account-entry targeted Flutter suite: 51 passed before the final permission addition. Final full sequential Flutter suite: 313 passed.
- Permission row: 18 locale/viewport/text-scale checks passed, then rerun successfully with the editable role and on/off interaction assertions. Actual-font screenshots inspected: Vietnamese 360px at 200%, English desktop at 100%. No clipping in the reviewed row; remaining combinations have automated exception/reachability coverage only.
- Targeted analyzer: no errors or warnings; six informational style lints remain in the seven checked files.
- Live staging requires Tom's deploy; nothing from this policy task has been deployed. Google sign-in/end-to-end callable behavior remains unverified live. Old tenant CCCD/check-in/English-mobile checks remain open separately.
- Existing legacy mixed-employer data requires review; no automatic migration or deletion. Current authorization is rechecked, so withdrawing delegation can block an additional workplace until the owner reapproves it.

## Next authorized stage: AI/subscription removal (not yet started)
- Considering removal of AI chat and paid subscriptions because of cost, then task-specific local intelligence such as classification. Tom authorized removing the software features after the agreement stage passes live checks. Preserve historical billing records; assess any external billing obligations separately. Define initial tasks and target devices before selecting local models; deterministic rules may suffice for some tasks.

### AI removal work, after scope is approved
1. Inventory AI chat entry points, callable exports (`aiChat` and import helpers), quotas/secrets, subscription screens, entitlement checks, and stored purchase/history records.
2. Separate paid-plan restrictions from useful operational features; define what existing customers retain and how historical receipts remain accessible.
3. Remove UI and server entry points together, verify app startup/navigation and unrestricted core workflows, then retire provider secrets/jobs only after deployment. Do not cancel real subscriptions or delete records as part of planning.
4. List candidate small tasks (classification, suggested categories, duplicate detection). Start with deterministic rules where appropriate; benchmark local models only after specifying devices, Vietnamese/English examples, accuracy, memory, offline behavior, and user correction flows.
5. Keep this plan separate from staff access delivery. No AI model choice or cost claim has been validated yet.
