'use strict';
// G8: move one legacy (v1) organization to version 2, with backup and undo.
// Run from the repository root with the Firebase CLI signed in.
//
//   node tool/migrate_v2.cjs plan --project staging|production --org ORG_ID
//       Read-only. Saves backup.json + plan.json under private-backups/migrate-v2/
//       and prints what would change and anything that blocks the move.
//   node tool/migrate_v2.cjs apply --plan FOLDER --confirm "ORGANIZATION NAME"
//       Applies that saved plan. Stops if any record changed since the plan.
//       The organization switches to v2 last, after everything else.
//   node tool/migrate_v2.cjs undo --plan FOLDER [--force]
//       Puts back the previous values of every field the plan changed
//       (organization first). Records made after the move stay.
//   node tool/migrate_v2.cjs rehearse --org PRODUCTION_ORG_ID --owner STAGING_EMAIL
//       Reads the production organization (read-only) and writes an ANONYMIZED
//       legacy copy into staging owned by STAGING_EMAIL: names, phones, emails,
//       addresses, notes and IDs are replaced; amounts, dates and structure stay.
//       Then rehearse plan/apply/undo on that copy with --project staging.
//   node tool/migrate_v2.cjs rehearse-delete
//       Removes every rehearsal copy from staging.
const fs=require('node:fs'),path=require('node:path'),{createHash,randomBytes}=require('node:crypto');
const PROJECTS={staging:'apartment-management-staging',production:'apartment-management-app-776b9'};
const base='../functions/node_modules/firebase-tools/lib/';
const ROOT=path.resolve(__dirname,'..');
const dep=require('node:module').createRequire(path.join(ROOT,'functions/package.json'));
const {collectOrganization}=require(path.join(ROOT,'functions/org_data.js'));
const {planMigration}=require(path.join(ROOT,'functions/migration_plan.js'));
const SKIP=['organizations','owners','purgedOrganizations'];
const arg=name=>{const i=process.argv.indexOf('--'+name);return i>0?process.argv[i+1]:null;};
const flag=name=>process.argv.includes('--'+name);
const out=v=>console.log(JSON.stringify(v,null,1));

async function connect(project){
 await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
 const access=await require(base+'apiv2').getAccessToken();
 const fsMod=dep('@google-cloud/firestore');
 // Same transport workaround as staging_seed_v2.cjs (CLI token, no key files).
 const gaxRequire=require('node:module').createRequire(dep.resolve('google-gax',{paths:[path.dirname(dep.resolve('@google-cloud/firestore'))]}));
 const {OAuth2Client}=gaxRequire('google-auth-library');
 const authClient=new OAuth2Client();authClient.setCredentials({access_token:access,expiry_date:Date.now()+50*60000});
 const db=new fsMod.Firestore({projectId:project,authClient});
 return {db,fsMod,access};
}

// JSON-safe Firestore values.
function codec(db,{Timestamp,GeoPoint,DocumentReference}){
 const enc=v=>{
  if(v instanceof Timestamp)return {__t:'ts',s:v.seconds,n:v.nanoseconds};
  if(v instanceof GeoPoint)return {__t:'geo',lat:v.latitude,lng:v.longitude};
  if(v instanceof DocumentReference)return {__t:'ref',p:v.path};
  if(v instanceof Uint8Array)return {__t:'bytes',b64:Buffer.from(v).toString('base64')};
  if(Array.isArray(v))return v.map(enc);
  if(v&&typeof v==='object')return Object.fromEntries(Object.entries(v).map(([k,x])=>[k,enc(x)]));
  return v;
 };
 const dec=v=>{
  if(Array.isArray(v))return v.map(dec);
  if(v&&typeof v==='object'){
   if(v.__t==='ts')return new Timestamp(v.s,v.n);
   if(v.__t==='geo')return new GeoPoint(v.lat,v.lng);
   if(v.__t==='ref')return db.doc(v.p);
   if(v.__t==='bytes')return Buffer.from(v.b64,'base64');
   return Object.fromEntries(Object.entries(v).map(([k,x])=>[k,dec(x)]));
  }
  return v;
 };
 const canon=v=>Array.isArray(v)?v.map(canon):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canon(v[k])])):v;
 const same=(a,b)=>JSON.stringify(canon(enc(a)))===JSON.stringify(canon(b));
 return {enc,dec,same};
}

// Every top-level record of the organization (plus one level of subcollections when asked).
async function readOrganization(db,orgId,{subcollections=false}={}){
 const org=await db.doc('organizations/'+orgId).get();
 if(!org.exists)throw Error(`Organization ${orgId} not found`);
 const collections=(await db.listCollections()).map(c=>c.id).filter(c=>!SKIP.includes(c));
 const crossLinked=[];
 const found=await collectOrganization(db,orgId,collections,{fields:['organizationId','orgId'],onCrossLink:doc=>crossLinked.push(doc.ref.path)});
 const docs=[{path:org.ref.path,data:org.data()}];
 for(const [,map] of found)for(const d of map.values()){
  docs.push({path:d.ref.path,data:d.data()});
  if(subcollections)for(const sub of await d.ref.listCollections())for(const s of (await sub.get()).docs)docs.push({path:s.ref.path,data:s.data()});
 }
 return {org,docs,crossLinked};
}
const snapshotFor=(orgId,docs)=>{
 const pick=c=>docs.filter(d=>d.path.split('/').length===2&&d.path.startsWith(c+'/')).map(d=>({id:d.path.split('/')[1],...d.data}));
 return {organization:{id:orgId,...docs.find(d=>d.path==='organizations/'+orgId).data},
  memberships:pick('memberships'),buildings:pick('buildings'),rooms:pick('rooms'),tenants:pick('tenants'),bookings:pick('bookings'),payments:pick('payments')};
};
const stamp=()=>new Date().toISOString().replace(/[:.]/g,'-');

async function plan(){
 const project=PROJECTS[arg('project')],orgId=arg('org');
 if(!project||!/^[A-Za-z0-9_-]{1,128}$/.test(orgId??''))throw Error('Usage: plan --project staging|production --org ORG_ID');
 const {db,fsMod}=await connect(project);
 try{
  const {enc}=codec(db,fsMod);
  const {docs,crossLinked}=await readOrganization(db,orgId,{subcollections:true});
  const result=planMigration(snapshotFor(orgId,docs));
  for(const p of crossLinked)result.blockers.push({reason:'crossLinkedRecord',path:p});
  const dir=path.resolve('private-backups','migrate-v2',arg('project'),`${orgId}-${stamp()}`);
  fs.mkdirSync(dir,{recursive:true});
  fs.writeFileSync(path.join(dir,'backup.json'),JSON.stringify({project,organizationId:orgId,takenAt:new Date().toISOString(),docs:docs.map(d=>({path:d.path,data:enc(d.data)}))}),{flag:'wx'});
  fs.writeFileSync(path.join(dir,'plan.json'),JSON.stringify({project,...result,changes:result.changes.map(c=>({...c,set:enc(c.set),previous:enc(c.previous)}))},null,1),{flag:'wx'});
  out({organization:result.organizationName,organizationId:orgId,project,summary:result.summary,
   blockers:result.blockers,warnings:result.warnings,folder:dir,
   next:result.blockers.length?'Fix the blockers, then plan again.':`node tool/migrate_v2.cjs apply --plan "${dir}" --confirm "${result.organizationName}"`});
 }finally{await db.terminate();}
}

const loadPlan=()=>{
 const dir=arg('plan');
 if(!dir)throw Error('Pass --plan FOLDER (printed by the plan command)');
 const p=JSON.parse(fs.readFileSync(path.join(dir,'plan.json'),'utf8'));
 if(!fs.existsSync(path.join(dir,'backup.json')))throw Error('backup.json is missing next to plan.json; plan again');
 if(!Object.values(PROJECTS).includes(p.project))throw Error('Unknown project in plan');
 return {dir,p};
};

// Each step re-reads its records and stops if anything changed since the plan.
// A field already at its new value counts as done, so a stopped run can be re-run.
async function applyChanges(db,p,{dec,same},log=()=>{}){
 const last=p.changes.at(-1);
 if(last?.path!==`organizations/${p.organizationId}`)throw Error('Plan must end with the organization switch');
 const step=async changes=>db.runTransaction(async tx=>{
  const snaps=await Promise.all(changes.map(c=>tx.get(db.doc(c.path))));
  const drift=[];
  changes.forEach((c,i)=>{
   const cur=snaps[i].data();
   if(!cur){drift.push(`${c.path}: missing`);return;}
   for(const k of Object.keys(c.set)){
    const done=same(cur[k],c.set[k]);
    const before=c.missing.includes(k)?cur[k]===undefined:same(cur[k],c.previous[k]);
    if(!done&&!before)drift.push(`${c.path}.${k}`);
   }
  });
  if(drift.length)throw Error('Changed since the plan, nothing written in this step. Plan again.\n'+drift.join('\n'));
  changes.forEach(c=>tx.update(db.doc(c.path),dec(c.set)));
 });
 const body=p.changes.slice(0,-1);
 for(let i=0;i<body.length;i+=100){await step(body.slice(i,i+100));log(`records ${Math.min(i+100,body.length)}/${body.length}`);}
 await step([last]);
 return p.changes.length;
}

// Organization first, so nobody keeps using it as v2 while the rest goes back.
// Fields changed after the move are left alone (reported) unless force.
async function undoChanges(db,p,{dec,same},deleteField,force=false){
 const changes=[...p.changes].reverse(),drift=[];
 for(let i=0;i<changes.length;i+=100){
  const part=changes.slice(i,i+100);
  await db.runTransaction(async tx=>{
   const snaps=await Promise.all(part.map(c=>tx.get(db.doc(c.path))));
   const writes=[];
   part.forEach((c,j)=>{
    const cur=snaps[j].data();
    if(!cur){drift.push(`${c.path}: missing (skipped)`);return;}
    const patch={};
    for(const k of Object.keys(c.set)){
     if(!same(cur[k],c.set[k])){drift.push(`${c.path}.${k}: changed after the move`);if(!force)continue;}
     patch[k]=c.missing.includes(k)?deleteField():dec(c.previous[k]);
    }
    if(Object.keys(patch).length)writes.push([db.doc(c.path),patch]);
   });
   writes.forEach(([ref,patch])=>tx.update(ref,patch));
  });
 }
 return drift;
}

async function apply(){
 const {dir,p}=loadPlan();
 if(p.blockers.length)throw Error('This plan has blockers; fix them and plan again');
 if(arg('confirm')!==p.organizationName)throw Error(`Type the organization name exactly: --confirm "${p.organizationName}"`);
 if(fs.existsSync(path.join(dir,'applied.json')))throw Error('This plan was already applied (applied.json). Use undo, or plan again.');
 const {db,fsMod}=await connect(p.project);
 try{
  const n=await applyChanges(db,p,codec(db,fsMod),m=>console.error(m));
  fs.writeFileSync(path.join(dir,'applied.json'),JSON.stringify({appliedAt:new Date().toISOString(),changes:n}),{flag:'wx'});
  out({applied:n,organization:p.organizationName,undo:`node tool/migrate_v2.cjs undo --plan "${dir}"`});
 }finally{await db.terminate();}
}

async function undo(){
 const {dir,p}=loadPlan();
 const {db,fsMod}=await connect(p.project);
 try{
  const drift=await undoChanges(db,p,codec(db,fsMod),()=>fsMod.FieldValue.delete(),flag('force'));
  if(fs.existsSync(path.join(dir,'applied.json')))fs.renameSync(path.join(dir,'applied.json'),path.join(dir,`undone-${stamp()}.json`));
  out({undone:p.changes.length,organization:p.organizationName,keptBecauseChangedLater:flag('force')?[]:drift,
   note:drift.length&&!flag('force')?'Fields changed after the move were left as they are. Re-run with --force to put them back anyway.':undefined});
 }finally{await db.terminate();}
}

// ---------- Rehearsal (production -> anonymized staging copy) ----------
// Strings kept as they are; everything else that is text gets a placeholder.
const KEEP=new Set(['status','type','role','currency','rentalMode','timeZone','pricingType','roomNumber','roomType',
 'buildingScope','employmentStatus','code','color','action','kind','accessVersion','paymentMethod','method','period',
 'billingCycle','gender','floor','unit','category','priority','source','language']);
function anonymizer(idMap){
 let n=0;
 const mapString=s=>{
  if(idMap.has(s))return idMap.get(s);
  const i=s.indexOf('_');
  if(i>0&&idMap.has(s.slice(0,i))&&idMap.has(s.slice(i+1)))return idMap.get(s.slice(0,i))+'_'+idMap.get(s.slice(i+1));
  return null;
 };
 const text=(key,s)=>{
  n++;
  if(/mail/i.test(key)&&s.includes('@'))return `rehearsal+${n}@example.invalid`;
  if(/phone/i.test(key))return '0900'+String(n).padStart(6,'0');
  if(/^https?:\/\//.test(s))return '';
  return `${key} ${n}`;
 };
 const walk=(v,key='')=>{
  if(typeof v==='string')return mapString(v)??(KEEP.has(key)?v:text(key,v));
  if(Array.isArray(v))return v.map(x=>walk(x,key));
  if(v&&typeof v==='object'&&v.constructor===Object)return Object.fromEntries(Object.entries(v).map(([k,x])=>[mapString(k)??k,walk(x,k)]));
  return v; // numbers, booleans, null, timestamps
 };
 return {walk,mapString};
}

// Pure: new IDs for every record, the organization and every account. The
// real owner becomes ownerUid; other people become placeholder IDs.
function anonymizedCopy(docs,orgId,ownerUid,salt){
 const org=docs.find(d=>d.path==='organizations/'+orgId).data;
 const newId=s=>'rh'+createHash('sha256').update(salt+s).digest('hex').slice(0,18);
 const idMap=new Map();
 for(const d of docs)for(const part of d.path.split('/').filter((_,i)=>i%2===1))if(!idMap.has(part)&&!part.includes('_'))idMap.set(part,newId(part));
 const accounts=new Set([org.createdBy]);
 for(const d of docs)for(const k of ['ownerId','accountId','createdBy','invitedBy','userId','actorId','updatedBy','closedBy','acceptedBy','reviewedBy'])if(typeof d.data[k]==='string')accounts.add(d.data[k]);
 for(const a of accounts)if(a)idMap.set(a,a===org.createdBy?ownerUid:newId(a));
 const {walk,mapString}=anonymizer(idMap);
 const newOrg=idMap.get(orgId);
 const copies=docs.map(d=>({path:d.path.split('/').map((s,i)=>i%2?mapString(s)??newId(s):s).join('/'),data:walk(d.data)}));
 const top=copies.find(c=>c.path==='organizations/'+newOrg);
 Object.assign(top.data,{name:`Rehearsal ${new Date().toISOString().slice(0,10)} (${docs.length} records)`,rehearsal:true});
 delete top.data.accessVersion;
 return {newOrg,copies};
}

async function rehearse(){
 const orgId=arg('org'),ownerEmail=arg('owner');
 if(!/^[A-Za-z0-9_-]{1,128}$/.test(orgId??'')||!ownerEmail)throw Error('Usage: rehearse --org PRODUCTION_ORG_ID --owner STAGING_EMAIL');
 const prod=await connect(PROJECTS.production);
 let docs,org;
 try{({docs,org}=await readOrganization(prod.db,orgId,{subcollections:true}));}finally{await prod.db.terminate();}
 if(org.data().accessVersion===2)throw Error('That organization is already version 2');
 const stg=await connect(PROJECTS.staging);
 const {initializeApp,deleteApp}=dep('firebase-admin/app'),{getAuth}=dep('firebase-admin/auth');
 const app=initializeApp({projectId:PROJECTS.staging,credential:{getAccessToken:async()=>({access_token:stg.access,expires_in:1800})}},'rehearse');
 try{
  const owner=await getAuth(app).getUserByEmail(ownerEmail).catch(()=>{throw Error(`${ownerEmail} is not registered in staging`);});
  const {newOrg,copies}=anonymizedCopy(docs,orgId,owner.uid,randomBytes(8).toString('hex'));
  if((await stg.db.doc('organizations/'+newOrg).get()).exists)throw Error('Target exists; run again');
  const writer=stg.db.bulkWriter();
  for(const c of copies)writer.create(stg.db.doc(c.path),c.data);
  await writer.close();
  const counts={};for(const c of copies){const k=c.path.split('/').length===2?c.path.split('/')[0]:c.path.split('/')[2];counts[k]=(counts[k]??0)+1;}
  out({stagingOrganizationId:newOrg,owner:ownerEmail,counts,
   next:[`node tool/migrate_v2.cjs plan --project staging --org ${newOrg}`,'then apply / test in the staging app / undo / apply again',
    'node tool/migrate_v2.cjs rehearse-delete   (when done)']});
 }finally{await deleteApp(app);await stg.db.terminate();}
}

async function rehearseDelete(){
 const {db}=await connect(PROJECTS.staging);
 try{
  const orgs=(await db.collection('organizations').where('rehearsal','==',true).get()).docs;
  const collections=(await db.listCollections()).map(c=>c.id).filter(c=>!SKIP.includes(c));
  const writer=db.bulkWriter(),counts={};
  for(const o of orgs){
   const found=await collectOrganization(db,o.id,collections,{fields:['organizationId','orgId'],onCrossLink:doc=>{throw Error('Unexpected cross-organization record: '+doc.ref.path);}});
   for(const [c,map] of found)for(const d of map.values()){await db.recursiveDelete(d.ref,writer);counts[c]=(counts[c]??0)+1;}
   await db.recursiveDelete(o.ref,writer);
  }
  await writer.close();
  out({deletedOrganizations:orgs.map(o=>o.id),counts});
 }finally{await db.terminate();}
}

module.exports={codec,readOrganization,snapshotFor,applyChanges,undoChanges,anonymizedCopy};
if(require.main===module){
 const commands={plan,apply,undo,rehearse,'rehearse-delete':rehearseDelete};
 const cmd=commands[process.argv[2]];
 if(!cmd){console.error('Usage: node tool/migrate_v2.cjs plan|apply|undo|rehearse|rehearse-delete (see the top of this file)');process.exitCode=1;}
 else cmd().catch(e=>{console.error(e.message);process.exitCode=1;});
}
