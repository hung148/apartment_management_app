'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {accountPolicy}=require('../account_policy');
const {fakeDb}=require('./fake_firestore');
const {createRequestGuard,createKeyedTurns}=require('../request_security');

test('rate limiter starts membership and bucket reads together without charging an outsider organization',async()=>{
 const db=fakeDb(),events=[];
 const transaction=db.runTransaction.bind(db);
 db.runTransaction=fn=>transaction(tx=>fn({...tx,get:async ref=>{
  events.push(['start',ref.path]);
  const result=await tx.get(ref);events.push(['finish',ref.path]);return result;
 }}));
 const guard=createRequestGuard({db,Timestamp:{fromMillis:v=>v},HttpsError:Error});
 await guard('readWorkspace',{auth:{uid:'user'},app:{appId:'app'},data:{organizationId:'other'}});
 assert.deepEqual(events.slice(0,3).map(e=>e[0]),['start','start','start']);
 assert.equal([...db.store.keys()].filter(k=>k.startsWith('requestLimits/')).length,1);
});

test('account policy starts independent reads together while retaining deletion denial',async()=>{
 const db=fakeDb({'accountDeletions/user':{status:'pending'}}),events=[];
 const tx={get:async ref=>{
  events.push('start');
  const value=await ref.get();
  events.push('finish');
  return value;
 }};
 const result=await accountPolicy(db,tx,'user');
 assert.equal(result.deleting,true);
 assert.equal(result.canCreate,false);
 assert.deepEqual(events.slice(0,4),['start','start','start','start'],
  'membership, created organizations, binding and deletion reads must not add four serial network waits');
});

test('policy reuses an organization snapshot across membership binding and invitation checks',async()=>{
 const db=fakeDb({
  'organizations/work':{accessVersion:2,createdBy:'boss'},
  'memberships/user_work':{ownerId:'user',organizationId:'work',role:'receptionist',status:'active'},
  'accountOrganizations/user':{organizationId:'work',state:'bound'},
  'teamInvitations/pending':{email:'user@example.com',organizationId:'work',status:'pending'},
 });
 let reads=0;
 const tx={get:async ref=>{
  if(ref.path==='organizations/work')reads++;
  return ref.get();
 }};
 const result=await accountPolicy(db,tx,'user','user@example.com');
 assert.equal(result.mode,'staff');
 assert.equal(result.canCreate,false);
 assert.deepEqual(result.organizationIds,['work']);
 assert.equal(reads,1,'same policy check must not reread the same organization three times');
 // Snapshot reuse must stop at the request boundary: revocation/merge is fresh.
 db.store.set('organizations/work',{accessVersion:2,createdBy:'boss',mergedInto:'destination'});
 const next=await accountPolicy(db,tx,'user','user@example.com');
 assert.deepEqual(next.organizationIds,[]);
 assert.equal(next.hasStaff,false);
 assert.equal(reads,2);
});

// Speed (2026-10-09): one account's simultaneous calls take turns at the
// rate-limit transaction instead of colliding (abort + ~1 s retry back-off).
test('one account\'s simultaneous calls never overlap at the limiter; other accounts do',async()=>{
 const db=fakeDb({'memberships/user_org':{ownerId:'user',organizationId:'org',accessVersion:2,status:'active',role:'owner'}});
 const transaction=db.runTransaction.bind(db);
 let open=0,most=0;
 db.runTransaction=(fn,options)=>{
  if(options?.readOnly)return transaction(fn,options);
  return transaction(async tx=>{open++;most=Math.max(most,open);try{await new Promise(r=>setTimeout(r,5));return await fn(tx);}finally{open--;}},options);
 };
 const guard=createRequestGuard({db,Timestamp:{fromMillis:v=>v},HttpsError:Error});
 const call=(uid,name)=>guard(name,{auth:{uid},app:{appId:'app'},data:{}});
 await Promise.all(['readTeam','readWorkspace','calendarView','organizationSettings'].map(n=>call('user',n)));
 assert.equal(most,1,'the same account must take turns');
 most=0;
 await Promise.all(['a','b','c'].map(uid=>call(uid,'readTeam')));
 assert.equal(most,3,'different accounts are not held up');
 const bucket=[...db.store.entries()].find(([k,v])=>k.startsWith('requestLimits/')&&v.tokens<120);
 assert(bucket,'charges are still written');
});

test('turns: opposite key orders cannot deadlock and a failure frees the turn',async()=>{
 const turns=createKeyedTurns(),order=[];
 const slow=(tag,ms)=>async()=>{order.push(tag+'+');await new Promise(r=>setTimeout(r,ms));order.push(tag+'-');};
 await Promise.all([turns(['a','b'],slow('x',5)),turns(['b','a'],slow('y',1))]);
 assert.deepEqual(order,['x+','x-','y+','y-']);
 await assert.rejects(turns(['a'],async()=>{throw Error('boom');}));
 assert.equal(await turns(['a'],async()=>'free'),'free');
});

test('the account policy check runs as a read-only transaction',async()=>{
 const db=fakeDb({
  'organizations/org':{accessVersion:2,createdBy:'user'},
  'memberships/user_org':{ownerId:'user',organizationId:'org',accessVersion:2,status:'active',role:'owner'},
 });
 const transaction=db.runTransaction.bind(db),options=[];
 db.runTransaction=(fn,o)=>{options.push(o?.readOnly===true);return transaction(fn,o);};
 const guard=createRequestGuard({db,Timestamp:{fromMillis:v=>v},HttpsError:Error});
 await guard('readTeam',{auth:{uid:'user'},app:{appId:'app'},data:{organizationId:'org'}});
 // They start together now (2026-10-10), so in either order.
 assert.deepEqual([...options].sort(),[false,true],'the limiter writes; the policy check only reads');
});

// 2026-10-10 (speed): calls that arrive together share one charge.
test('an account\'s simultaneous calls share one charge transaction with the same limits',async()=>{
 const db=fakeDb({'memberships/user_org':{ownerId:'user',organizationId:'org',accessVersion:2,status:'active',role:'owner'}});
 const transaction=db.runTransaction.bind(db);
 let charges=0;
 db.runTransaction=(fn,o)=>{if(!o?.readOnly)charges++;return transaction(async tx=>{await new Promise(r=>setTimeout(r,5));return fn(tx);},o);};
 const guard=createRequestGuard({db,Timestamp:{fromMillis:v=>v},HttpsError:Error,now:()=>1000000});
 const call=name=>guard(name,{auth:{uid:'user'},app:{appId:'app'},data:{}});
 await Promise.all(['readTeam','readWorkspace','calendarView','organizationSettings','listMyOrganizations'].map(call));
 assert.ok(charges<=2,`5 calls, ${charges} charge transactions`);
 const general=[...db.store.values()].find(v=>v.tokens!==undefined);
 assert.equal(general.tokens,115,'each call still takes one token');
});

test('in a shared charge each call is all-or-nothing and refused calls take nothing',async()=>{
 const db=fakeDb();
 const transaction=db.runTransaction.bind(db);
 db.runTransaction=(fn,o)=>transaction(async tx=>{await new Promise(r=>setTimeout(r,5));return fn(tx);},o);
 const guard=createRequestGuard({db,Timestamp:{fromMillis:v=>v},HttpsError:class extends Error{constructor(c,m){super(m);this.code=c;}},now:()=>1000000});
 // The costly bucket holds 4: of 6 calls at once, 4 pass and 2 are refused.
 const results=await Promise.allSettled([0,1,2,3,4,5].map(()=>guard('aiChat',{auth:{uid:'user'},app:{appId:'app'},data:{}})));
 assert.equal(results.filter(r=>r.status==='fulfilled').length,4);
 assert.ok(results.filter(r=>r.status==='rejected').every(r=>r.reason.code==='resource-exhausted'));
 const tokens=[...db.store.values()].map(v=>v.tokens).sort((a,b)=>a-b);
 // costly: 4 - 4 = 0; general: 120 - 4 (passed) - 2 (refused attempts charged) = 114.
 assert.deepEqual(tokens,[0,114]);
});

// 2026-10-10 (Tom): organization/account checks remembered for 15 s.
test('organization checks are remembered for 15 s, shared, and forgotten after a write',async()=>{
 const db=fakeDb({
  'organizations/org':{accessVersion:2,createdBy:'user'},
  'memberships/user_org':{ownerId:'user',organizationId:'org',accessVersion:2,status:'active',role:'owner'},
 });
 let reads=0,time=1000000;
 const doc=db.doc.bind(db);
 db.doc=path=>{const ref=doc(path);if(path==='organizations/org'){const get=ref.get.bind(ref);ref.get=()=>{reads++;return get();};}return ref;};
 const HttpsError=class extends Error{constructor(c,m){super(m);this.code=c;}};
 const guard=createRequestGuard({db,Timestamp:{fromMillis:v=>v},HttpsError,now:()=>time});
 const call=()=>guard('readTeam',{auth:{uid:'user'},app:{appId:'app'},data:{organizationId:'org'}});
 await Promise.all([call(),call(),call()]);
 assert.equal(reads,1,'calls at the same time share one read');
 time+=14000;await call();
 assert.equal(reads,1,'still remembered after 14 s');
 // A merge seen within 15 s at most.
 db.store.set('organizations/org',{accessVersion:2,createdBy:'user',mergedInto:'other'});
 time+=1000;
 await assert.rejects(call(),e=>e.message==='org_organization_merged');
 assert.equal(reads,2);
 // A write on this server copy forgets the organization at once.
 db.store.set('organizations/org',{accessVersion:2,createdBy:'user'});
 guard.forget('user','org');
 await call();
 assert.equal(reads,3);
});

test('a failed check is never remembered',async()=>{
 const db=fakeDb({'memberships/user_org':{ownerId:'user',organizationId:'org',accessVersion:2,status:'active',role:'owner'}});
 let fail=true;
 const doc=db.doc.bind(db);
 db.doc=path=>{const ref=doc(path);if(path==='organizations/org'){const get=ref.get.bind(ref);ref.get=()=>fail?Promise.reject(new Error('unavailable')):get();}return ref;};
 const guard=createRequestGuard({db,Timestamp:{fromMillis:v=>v},HttpsError:Error,now:()=>1000000});
 const call=()=>guard('readTeam',{auth:{uid:'user'},app:{appId:'app'},data:{organizationId:'org'}});
 await assert.rejects(call(),/unavailable/);
 fail=false;
 db.store.set('organizations/org',{accessVersion:2,createdBy:'user'});
 await call();
});
