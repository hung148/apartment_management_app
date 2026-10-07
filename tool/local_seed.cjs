'use strict';
// Local test accounts for the Firebase emulators started by tool\local.ps1.
// Talks ONLY to the emulators on this computer (demo project, no cloud data).
// Safe to run again: existing accounts are kept.
//
//   node tool/local_seed.cjs
//
// These are local test values, not real accounts or passwords. The owner
// creates the test organization, rooms and lease once through the app; the
// emulator data is then saved in .local-data/ and reloaded on every start.
const path = require('node:path');
const dep = require('node:module').createRequire(path.resolve('functions/package.json'));

const PROJECT = 'demo-canho360';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8180';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9199';
process.env.GCLOUD_PROJECT = PROJECT;

const ACCOUNTS = [
  { email: 'owner@canho.test', password: 'local-owner-123', name: 'Chu nha Local' },
  { email: 'staff@canho.test', password: 'local-staff-123', name: 'Nhan vien Local' },
  { email: 'staff2@canho.test', password: 'local-staff-456', name: 'Nhan vien Hai' },
];

async function main() {
  const { initializeApp } = dep('firebase-admin/app');
  const { getAuth } = dep('firebase-admin/auth');
  const { getFirestore, Timestamp } = dep('firebase-admin/firestore');
  const app = initializeApp({ projectId: PROJECT }, 'local-seed');
  if (!PROJECT.startsWith('demo-') || !process.env.FIRESTORE_EMULATOR_HOST.startsWith('127.0.0.1')) {
    throw Error('Refusing to run outside the local emulators');
  }
  const auth = getAuth(app), db = getFirestore(app);
  for (const a of ACCOUNTS) {
    let user;
    try {
      user = await auth.getUserByEmail(a.email);
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
      user = await auth.createUser({ email: a.email, password: a.password, displayName: a.name, emailVerified: true });
    }
    // Same shape the app writes when someone registers (Owner.toMap).
    const ref = db.doc(`owners/${user.uid}`);
    if (!(await ref.get()).exists) await ref.set({ email: a.email, name: a.name, createdAt: Timestamp.now() });
    console.log(`  ${a.email.padEnd(20)} ${a.password}`);
  }
  console.log('Local accounts ready (emulator only).');
}

main().catch(e => { console.error(e.message || e); process.exit(1); });
