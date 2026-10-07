'use strict';
const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs');
const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc}=require('firebase/firestore');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {createUtilityReadingsHandler}=require('../utility_readings');
const {createInvoiceHandler}=require('../invoices');
let env,app,db,readings,invoices;
before(async()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Emulator required');
 env=await initializeTestEnvironment({projectId:'demo-apartment-calendar',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});
 app=initializeApp({projectId:'demo-apartment-calendar'},'utility-tests');db=getFirestore(app);
 const deps={db,Timestamp:{now:()=>Timestamp.fromMillis(Date.parse('2026-10-02T12:00:00Z')),fromMillis:Timestamp.fromMillis},HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}};
 readings=createUtilityReadingsHandler(deps);invoices=createInvoiceHandler(deps);
});
after(async()=>{await env?.cleanup();if(app)await deleteApp(app);});
beforeEach(async()=>{
 await env.clearFirestore();
 await db.doc('organizations/o').set({accessVersion:2});
 await db.doc('memberships/u_o').set({ownerId:'u',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all',buildingIds:[]});
 await db.doc('buildings/b').set({organizationId:'o',currency:'VND',timeZone:'Asia/Ho_Chi_Minh'});
 await db.doc('rooms/r').set({organizationId:'o',buildingId:'b',roomNumber:'101'});
});
const call=d=>readings({auth:{uid:'u'},data:{organizationId:'o',buildingId:'b',roomId:'r',kind:'electricity',reason:'Measured',...d}});
test('simultaneous readings serialize and exact retries preserve one history row',async()=>{
 const request={action:'record',operationId:'baseline',revision:0,date:'2026-09-01',readingMilli:0};
 const result=await Promise.all([call(request),call(request)]);assert.equal(result[0].readingId,result[1].readingId);
 await call({action:'tariff',operationId:'price',revision:1,propertyRevision:0,tariffScope:'property',effectiveDate:'2026-09-01',tariff:{currency:'VND',bands:[{throughMilli:null,priceMinor:3500}]}});
 const results=await Promise.allSettled([call({action:'record',operationId:'a',revision:2,date:'2026-10-01',readingMilli:1000}),call({action:'record',operationId:'b',revision:2,date:'2026-10-01',readingMilli:2000})]);
 assert.equal(results.filter(x=>x.status==='fulfilled').length,1);assert.equal(results.find(x=>x.status==='rejected').reason.code,'aborted');
 const meter=(await db.collection('utilityMeters').get()).docs[0];assert.equal((await meter.ref.collection('readings').get()).size,2);
});
test('simultaneous invoice creation cannot bill one interval twice',async()=>{
 await call({action:'record',operationId:'baseline',revision:0,date:'2026-09-01',readingMilli:0});
 await call({action:'tariff',operationId:'price',revision:1,propertyRevision:0,tariffScope:'room',effectiveDate:'2026-09-01',tariff:{currency:'VND',bands:[{throughMilli:null,priceMinor:3500}]}});
 const reading=await call({action:'record',operationId:'read',revision:2,date:'2026-10-01',readingMilli:1000});
 await db.doc('tenants/t').set({organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:true,fullName:'Test tenant',currency:'VND',moveInDate:Timestamp.fromMillis(Date.parse('2026-08-01T00:00:00Z'))});
 const data={organizationId:'o',buildingId:'b',kind:'utility',tenantId:'t',roomId:'r',readingId:reading.readingId,chargeType:'electricity',startDate:'2026-09-01',endDate:'2026-10-01',dueDate:'2026-10-02',reason:'Meter bill',feesMinor:{internetFee:0,cableTVFee:0,hotWaterFee:0,lateFee:0,taxAmount:0}};
 const run=d=>invoices({auth:{uid:'u'},data:{...data,...d}}),quote=await run({action:'quote'});
 const results=await Promise.allSettled(['a','b'].map(operationId=>run({action:'create',operationId,quoteRevision:quote.record.quoteRevision})));
 assert.equal(results.filter(x=>x.status==='fulfilled').length,1);assert.equal((await db.collection('payments').get()).size,1);
});
test('direct client access to meter, price and reading documents is denied',async()=>{
 const client=env.authenticatedContext('u').firestore();
 for(const path of ['utilityMeters/x','utilityMeters/x/readings/y','utilityTariffs/x']){
  await assertFails(setDoc(doc(client,path),{organizationId:'o'}));await assertFails(getDoc(doc(client,path)));
 }
});
