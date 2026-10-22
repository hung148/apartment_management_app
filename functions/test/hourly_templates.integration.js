const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {initializeTestEnvironment}=require('@firebase/rules-unit-testing');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp,FieldValue}=require('firebase-admin/firestore');
const {createBookingWorkspaceHandler}=require('../booking_workspace');
const {createCalendarHandler}=require('../calendar');
let env,app,db,handler;
class HttpsError extends Error{constructor(code,message){super(message);this.code=code;}}
before(async()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Emulator required');
 env=await initializeTestEnvironment({projectId:'demo-apartment-calendar',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});
 app=initializeApp({projectId:'demo-apartment-calendar'});db=getFirestore();
 const calendar=createCalendarHandler({db,Timestamp,FieldValue,HttpsError});
 handler=createBookingWorkspaceHandler({db,Timestamp,HttpsError,calendar});
});
after(async()=>{await env?.cleanup();if(app)await deleteApp(app);});
beforeEach(async()=>{
 await env.clearFirestore();
 await db.doc('organizations/org').set({accessVersion:2});
 await db.doc('memberships/owner_org').set({organizationId:'org',ownerId:'owner',accessVersion:2,role:'owner',status:'active',buildingScope:'all'});
 await db.doc('buildings/b').set({organizationId:'org',name:'Test',currency:'VND',timeZone:'Asia/Ho_Chi_Minh'});
 await db.doc('rooms/r').set({organizationId:'org',buildingId:'b',currency:'VND',hourlyPrice:100000});
});
const call=data=>handler({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'b',...data}});
test('concurrent templates merge, exact retries deduplicate, booking survives deletion and extends last price',async()=>{
 const template={action:'hourTemplates',templateId:'t',name:'Standard',hourPricesMinor:[300000,200000,100000]};
 await Promise.all([call(template),call(template),call({...template,templateId:'other',name:'Other'})]);
 assert.equal((await call({action:'rooms'})).hourTemplates.length,2);
 const base={roomId:'r',startLocal:'2026-10-10 14:00',endLocal:'2026-10-10 18:00',pricingType:'hourly'};
 const q=await call({action:'quote',...base,hourPricesMinor:template.hourPricesMinor});
 const save={...base,action:'save',bookingId:'k',operationId:'save',guestName:'Test',guestPhone:'',notes:'',depositMinor:0,roomRevision:q.record.roomRevision,hourPricesMinor:template.hourPricesMinor,inputCurrency:'VND'};
 await Promise.all([call(save),call(save)]);
 assert.equal((await db.doc('bookings/k').get()).data().totalPrice,700000);
 await call({action:'hourTemplates',templateId:'t',remove:true});
 const read=await call({action:'read',bookingId:'k'});
 const next={...save,operationId:'extend',revision:read.record.revision,endLocal:'2026-10-10 19:30'};delete next.hourPricesMinor;
 const fresh=await call({...base,action:'quote',bookingId:'k',endLocal:next.endLocal});next.roomRevision=fresh.record.roomRevision;
 await call(next);
 assert.equal((await db.doc('bookings/k').get()).data().totalPrice,850000);
});
