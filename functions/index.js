const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

const db = admin.firestore();

// Get current user's memberships
exports.getMyMemberships = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
  }

  const snapshot = await db.collection('memberships')
    .where('ownerId', '==', context.auth.uid)
    .get();

  return snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
});

// Get all members of an organization (admin only)
exports.getOrganizationMembers = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
  }

  const { orgId } = data;
  if (!orgId) {
    throw new functions.https.HttpsError('invalid-argument', 'orgId is required');
  }

  // Verify caller is admin
  const adminDoc = await db.collection('memberships')
    .doc(context.auth.uid + '_' + orgId)
    .get();

  if (!adminDoc.exists || adminDoc.data().role !== 'admin') {
    throw new functions.https.HttpsError('permission-denied', 'Must be org admin');
  }

  const snapshot = await db.collection('memberships')
    .where('organizationId', '==', orgId)
    .get();

  return snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
});