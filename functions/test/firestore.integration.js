const {test, before, after, beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {initializeTestEnvironment, assertFails, assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,updateDoc,getDoc,getDocs,collection,query,where,writeBatch}=require('firebase/firestore');
const admin=require('firebase-admin');
const {createCalendarHandler}=require('../calendar');
let env, db, handler;
before(async()=>{
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Emulator required: never run against production');
  env=await initializeTestEnvironment({projectId:'demo-apartment-calendar',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});
  admin.initializeApp({projectId:'demo-apartment-calendar'}); db=admin.firestore();
  handler=createCalendarHandler({db,Timestamp:admin.firestore.Timestamp,FieldValue:admin.firestore.FieldValue,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
});
after(async()=>{await env?.cleanup();await Promise.all(admin.apps.map(a=>a.delete()));});
beforeEach(async()=>{
  await env.clearFirestore();
  await db.doc('organizations/org').set({createdBy:'owner'});
  await db.doc('memberships/owner_org').set({ownerId:'owner',organizationId:'org',role:'admin',status:'active'});
  await db.doc('memberships/staff_org').set({ownerId:'staff',organizationId:'org',role:'member',status:'active'});
  await db.doc('rooms/room').set({organizationId:'org',buildingId:'building',rentalMode:'both',currency:'USD'});
  await db.doc('invite_codes/SECRET').set({orgId:'org'});
});
test('clients cannot bypass functions or forge booking payment records',async()=>{
 const client=env.authenticatedContext('staff').firestore();
 await assertFails(setDoc(doc(client,'bookings/direct'),{organizationId:'org'}));
 await assertFails(setDoc(doc(client,'payments/booking_forged'),{organizationId:'org'}));
 await assertFails(setDoc(doc(client,'payments/other'),{organizationId:'org',bookingId:'forged'}));
 await assertFails(setDoc(doc(client,'tenants/direct'),{organizationId:'org',roomId:'room',status:'active'}));
 await assertFails(updateDoc(doc(client,'rooms/room'),{bookingRevision:42}));
 await assertSucceeds(setDoc(doc(client,'payments/invoice'),{organizationId:'org',amount:25}));
 await assertSucceeds(updateDoc(doc(client,'rooms/room'),{roomNumber:'101'}));
});
test('outsiders cannot read inventory or self-promote; valid invitation works',async()=>{
 const outsider=env.authenticatedContext('outsider').firestore();
 await assertFails(getDoc(doc(outsider,'rooms/room')));
 await assertFails(getDocs(collection(outsider,'rooms')));
 await assertFails(getDocs(collection(outsider,'invite_codes')));
 await assertSucceeds(getDoc(doc(outsider,'memberships/outsider_org')));
 const member={ownerId:'outsider',organizationId:'org',role:'admin',status:'active'};
 await assertFails(setDoc(doc(outsider,'memberships/outsider_org'),member));
 await assertFails(setDoc(doc(outsider,'memberships/outsider_org'),{...member,role:'member',inviteCode:'WRONG'}));
 await assertSucceeds(setDoc(doc(outsider,'memberships/outsider_org'),{...member,role:'member',inviteCode:'SECRET'}));
 await assertFails(updateDoc(doc(outsider,'memberships/outsider_org'),{role:'admin'}));
 await assertSucceeds(getDocs(query(collection(outsider,'rooms'),where('organizationId','==','org'))));
});
test('atomic organization creation and owner membership remains supported',async()=>{
 const client=env.authenticatedContext('newowner').firestore(),batch=writeBatch(client);
 batch.set(doc(client,'organizations/new'),{createdBy:'newowner'});
 batch.set(doc(client,'memberships/newowner_new'),{ownerId:'newowner',organizationId:'new',role:'admin',status:'active'});
 batch.set(doc(client,'invite_codes/NEW'),{orgId:'new'});
 await assertSucceeds(batch.commit());
});
test('real concurrent Firestore transactions accept only one overlapping reservation',async()=>{
 const booking={organizationId:'org',roomId:'room',guestName:'Guest',guestPhone:'',totalPrice:100,startTime:{__timestamp:Date.UTC(2026,8,9,10)},endTime:{__timestamp:Date.UTC(2026,8,9,12)}};
 const results=await Promise.allSettled(['one','two'].map(bookingId=>handler({action:'create',bookingId,booking},{auth:{uid:'staff'}})));
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
 assert.equal(results.find(r=>r.status==='rejected').reason.code,'already-exists');
 assert.equal((await db.collection('bookings').get()).size,1);
});

const {createAI}=require('../ai');
const {createImport}=require('../ai_import');
class AIError extends Error {constructor(code,message){super(message);this.code=code;}}
function aiFixture(generate=async()=>({candidates:[{content:{parts:[{text:'Verified response'}]}}]})){
 const ai=createAI({db,Timestamp:admin.firestore.Timestamp,HttpsError:AIError,generate});
 return {ai,imports:createImport({db,Timestamp:admin.firestore.Timestamp,FieldValue:admin.firestore.FieldValue,ai,generate})};
}
test('AI daily message limits are atomic across devices and replay does not double-charge',async()=>{
 const {ai}=aiFixture();const request=id=>({auth:{uid:'owner'},data:{requestId:id,message:'Help me prioritize'}});
 const results=await Promise.allSettled(Array.from({length:6},(_,i)=>ai.chat(request('message'+i))));
 assert.equal(results.filter(r=>r.status==='fulfilled').length,5);
 assert.equal(results.find(r=>r.status==='rejected').reason.code,'resource-exhausted');
 assert.equal((await ai.usage({auth:{uid:'owner'}})).remainingMessages,0);
 const completed=results.findIndex(r=>r.status==='fulfilled');
 assert.equal((await ai.chat(request('message'+completed))).text,'Verified response');
 assert.equal((await ai.usage({auth:{uid:'owner'}})).remainingMessages,0);
});
test('AI failures return quota and clients cannot forge usage or subscriptions',async()=>{
 const {ai}=aiFixture(async()=>{throw Error('provider failed');});
 await assert.rejects(ai.chat({auth:{uid:'owner'},data:{requestId:'failed',message:'hello'}}),/ai_unavailable/);
 assert.equal((await ai.usage({auth:{uid:'owner'}})).remainingMessages,5);
 const client=env.authenticatedContext('owner').firestore();
 for(const name of ['aiUsage','aiEntitlements','aiDrafts','aiRequests'])await assertFails(setDoc(doc(client,name+'/owner'),{status:'active',verified:true}));
});
test('Paid allowance is shared across the subscription billing period, not reset daily',async()=>{
 const start=Date.now()-86400000,end=Date.now()+86400000*29;
 await db.doc('aiEntitlements/owner').set({verified:true,status:'active',periodStart:admin.firestore.Timestamp.fromMillis(start),expiresAt:admin.firestore.Timestamp.fromMillis(end)});
 const {ai}=aiFixture();await ai.chat({auth:{uid:'owner'},data:{requestId:'paidmessage',message:'hello'}});
 const usage=await ai.usage({auth:{uid:'owner'}});assert.equal(usage.remainingMessages,299);assert.equal(usage.remainingImports,30);assert.equal(usage.resetAt,end);
});
test('Import previews consume one daily import and atomic save creates linked hierarchy once',async()=>{
 const records=[{key:'org',type:'organization',fields:{name:'New org'}},{key:'b',type:'building',organizationRef:'org',fields:{name:'Building',address:'Address',currency:'USD'}},{key:'r',type:'room',organizationRef:'org',buildingRef:'b',fields:{roomNumber:'101',roomType:'Studio',area:20}},{key:'t',type:'tenant',organizationRef:'org',buildingRef:'b',roomRef:'r',fields:{fullName:'Tenant',phoneNumber:'0123',moveInDate:'2026-09-01',monthlyRent:200}},{key:'p',type:'payment',organizationRef:'org',buildingRef:'b',roomRef:'r',tenantRef:'t',dateOffsets:{dueDate:-420},fields:{type:'rent',amount:200,dueDate:'2026-10-01',status:'pending'}}];
 const {ai,imports}=aiFixture(async()=>({candidates:[{content:{parts:[{text:JSON.stringify({records,warnings:[]})}]}}]}));
 const request={auth:{uid:'owner'},data:{requestId:'import1',text:'source data',language:'en'}};
 const preview=await imports.preview(request);assert.equal((await ai.usage(request)).remainingImports,0);
 await assert.rejects(imports.preview({...request,data:{...request.data,requestId:'import2'}}),/ai_import_limit/);
 assert.equal((await db.collection('tenants').get()).size,0);
 const saved=await imports.commit({auth:{uid:'owner'},data:{draftId:preview.draftId,records}});
 assert.equal(saved.created.length,5);assert.deepEqual(await imports.commit({auth:{uid:'owner'},data:{draftId:preview.draftId,records}}),saved);
 const payment=(await db.doc('payments/'+saved.created.find(r=>r.type==='payment').id).get()).data();assert.equal(payment.currency,'USD');assert.equal(payment.paidAmount,0);assert.equal(payment.tenantName,'Tenant');assert.equal(payment.dueDate.toDate().toISOString(),'2026-10-01T07:00:00.000Z');
});
test('Cross-organization import and unauthorized draft commits fail without partial records',async()=>{
 const records=[{key:'r',type:'room',organizationRef:'org',buildingRef:'foreign',fields:{roomNumber:'999',roomType:'Studio',area:20}}];
 await db.doc('buildings/foreign').set({organizationId:'elsewhere'});
 const {imports}=aiFixture(async()=>({candidates:[{content:{parts:[{text:JSON.stringify({records})}]}}]}));
 const draft=await imports.preview({auth:{uid:'owner'},data:{requestId:'cross',organizationId:'org',text:'source'}});
 await assert.rejects(imports.commit({auth:{uid:'staff'},data:{draftId:draft.draftId,records}}),/ai_access_denied/);
 await assert.rejects(imports.commit({auth:{uid:'owner'},data:{draftId:draft.draftId,records}}),/ai_access_denied/);
 assert.equal((await db.collection('rooms').get()).size,1);
});

test('Subscriptions use provider-verified state, reject sandbox access and expire correctly',async()=>{
 const {createSubscriptions}=require('../subscriptions');
 let value={subscriber:{entitlements:{ai_pro:{expires_date:new Date(Date.now()+86400000).toISOString(),purchase_date:new Date(Date.now()-1000).toISOString(),product_identifier:'ai_pro_monthly'}},subscriptions:{ai_pro_monthly:{is_sandbox:false}}}};
 const billing=createSubscriptions({db,Timestamp:admin.firestore.Timestamp,HttpsError:AIError,getKey:()=> 'test',getWebhookSecret:()=> 'secret',fetcher:async()=>({ok:true,json:async()=>value})});
 assert.equal((await billing.sync({auth:{uid:'owner'},data:{verified:true}})).active,true);
 assert.equal((await aiFixture().ai.usage({auth:{uid:'owner'}})).paid,true);
 value.subscriber.subscriptions.ai_pro_monthly.is_sandbox=true;
 assert.equal((await billing.sync({auth:{uid:'owner'}})).active,false);
 value={subscriber:{entitlements:{},subscriptions:{}}};
 assert.equal((await billing.sync({auth:{uid:'owner'}})).active,false);
 let status;const response={status:v=>{status=v;return response;},send:()=>{}};
 await billing.webhook({method:'POST',get:()=> 'wrong',body:{event:{app_user_id:'owner'}}},response);assert.equal(status,401);
});
