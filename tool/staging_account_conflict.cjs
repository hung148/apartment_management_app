'use strict';
// READ-ONLY. Explains why a STAGING account is in "conflict" mode (owns
// organizations AND is staff somewhere / has a pending staff invitation).
// Mirrors functions/account_policy.js. Changes nothing. Run from the repo root:
//   node tool/staging_account_conflict.cjs you@example.com
const path=require('node:path'),base='../functions/node_modules/firebase-tools/lib/';
const project='apartment-management-staging';
const dep=require('node:module').createRequire(path.resolve('functions/package.json'));
const validId=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);

async function main(){
 const email=(process.argv[2]||'').trim().toLowerCase();
 if(!email.includes('@'))throw Error('Usage: node tool/staging_account_conflict.cjs you@example.com');
 await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
 const access=await require(base+'apiv2').getAccessToken();
 const {initializeApp,deleteApp}=dep('firebase-admin/app'),{getAuth}=dep('firebase-admin/auth');
 const {Firestore}=dep('@google-cloud/firestore');
 const gaxRequire=require('node:module').createRequire(dep.resolve('google-gax',{paths:[path.dirname(dep.resolve('@google-cloud/firestore'))]}));
 const {OAuth2Client}=gaxRequire('google-auth-library');
 const authClient=new OAuth2Client();authClient.setCredentials({access_token:access,expiry_date:Date.now()+50*60000});
 const db=new Firestore({projectId:project,authClient});
 const app=initializeApp({projectId:project,credential:{getAccessToken:async()=>({access_token:access,expires_in:1800})}},'staging-conflict');
 try{
  if(app.options.projectId!==project)throw Error('Wrong project');
  const user=await getAuth(app).getUserByEmail(email);
  const owned=[],staff=[],invites=[];
  const orgName=async id=>{const o=await db.doc('organizations/'+id).get();return o.exists?o.data():null;};
  for(const d of (await db.collection('organizations').where('createdBy','==',user.uid).get()).docs){
   const o=d.data();if(!o.ownerTransferredTo||o.ownerTransferredTo===user.uid)owned.push(`${d.id} "${o.name}"${o.closedAt?' (closed)':''}`);
  }
  for(const doc of (await db.collection('memberships').where('ownerId','==',user.uid).get()).docs){
   const m=doc.data();
   if(!validId(m.organizationId)||doc.id!==`${user.uid}_${m.organizationId}`)continue;
   if(m.status==='revoked'&&m.revokedReason!=='organizationClosed')continue;
   const o=await orgName(m.organizationId);if(!o)continue;
   const isOwner=['owner','coOwner'].includes(m.role)||(o.accessVersion!==2&&(o.ownerTransferredTo??o.createdBy)===user.uid);
   const line=`${m.organizationId} "${o.name}" role=${m.role??'none'} status=${m.status??'-'}${o.closedAt?' (closed)':''}`;
   if(isOwner){if(!owned.some(x=>x.startsWith(m.organizationId+' ')))owned.push(line);}else staff.push(line);
  }
  for(const doc of (await db.collection('teamInvitations').where('email','==',email).get()).docs){
   const inv=doc.data();
   if(inv.status!=='pending'||(inv.expiresAt!=null&&inv.expiresAt.toMillis()<=Date.now())||!validId(inv.organizationId))continue;
   const o=await orgName(inv.organizationId);if(!o||o.closedAt)continue;
   invites.push(`invitation ${doc.id} from ${inv.organizationId} "${o.name}" role=${inv.role??'-'} created=${inv.createdAt?.toDate?.().toISOString?.()??'-'}`);
  }
  console.log(JSON.stringify({email,uid:user.uid,
   mode:owned.length?(staff.length||invites.length?'conflict':'owner'):(staff.length||invites.length?'staff':'normal'),
   owns:owned,staffIn:staff,pendingInvitations:invites},null,2));
 }finally{await deleteApp(app);await db.terminate();}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
