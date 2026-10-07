'use strict';

/**
 * R2: after every sign-in the app asks the server to accept the pending
 * pre-approvals (and invitations) addressed to this account's verified email,
 * in every organization. Each one goes through the normal acceptInvitation
 * checks (inviter still allowed, role still exists, staff profile free), so
 * nothing here can give more than accepting by hand would.
 */
function createClaimInvitationsHandler({db, HttpsError, team}) {
  const fail = (code, message) => { throw new HttpsError(code, message); };
  return async request => {
    const uid = request.auth?.uid;
    if (!uid) fail('unauthenticated', 'team_sign_in_required');
    const token = request.auth.token ?? {};
    if (typeof token.email !== 'string' || !token.email) return {results: [], needsEmail: true};
    // Unverified addresses cannot claim anything (anyone can type any email).
    if (token.email_verified !== true) return {results: [], needsVerifiedEmail: true};
    const email = token.email.trim().toLowerCase();
    const pending = await db.collection('teamInvitations').where('email', '==', email).where('status', '==', 'pending').limit(20).get();
    const results = [];
    for (const doc of pending.docs) {
      const inv = doc.data();
      if (inv.expiresAt != null && !(inv.expiresAt.toMillis?.() > Date.now())) continue;
      if (typeof inv.organizationId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(inv.organizationId)) continue;
      const org = await db.collection('organizations').doc(inv.organizationId).get();
      const organizationName = org.exists ? (org.data().name ?? '') : '';
      try {
        await team({auth: request.auth, data: {organizationId: inv.organizationId,
          operationId: `claim_${doc.id}`.slice(0, 128), action: 'acceptInvitation', invitationId: doc.id}});
        results.push({organizationId: inv.organizationId, organizationName, status: 'joined'});
      } catch (error) {
        // Not joined (already a member, role removed, inviter lost rights, closed…).
        // The pre-approval stays pending so the owner can see and fix it.
        results.push({organizationId: inv.organizationId, organizationName, status: 'skipped',
          reason: typeof error?.message === 'string' ? error.message.slice(0, 80) : 'unknown'});
      }
    }
    return {results};
  };
}
module.exports = {createClaimInvitationsHandler};
