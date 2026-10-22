const {test}=require('node:test');
const assert=require('node:assert/strict');
const {bookingPrice}=require('../booking_quote');
const {createBookingWorkspaceHandler}=require('../booking_workspace');
const {createCalendarHandler}=require('../calendar');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const rates=[300000,200000,100000];
const member=(uid,role)=>({ownerId:uid,organizationId:'org',accessVersion:2,role,status:'active',buildingScope:'all',buildingIds:[]});
function setup(){const db=fakeDb({
 'organizations/org':{accessVersion:2,createdBy:'owner'},
 'memberships/owner_org':member('owner','owner'),
 'memberships/desk_org':member('desk','receptionist'),
 'buildings/b':{organizationId:'org',currency:'VND',timeZone:'Asia/Ho_Chi_Minh'},
 'rooms/r':{organizationId:'org',buildingId:'b',currency:'VND',hourlyPrice:100000}
});const calendar=createCalendarHandler({db,Timestamp:Ts,FieldValue:{increment:n=>n},HttpsError:CodeError});
const handler=createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError,calendar});
return {db,call:(data,uid='owner')=>handler({auth:{uid},data:{organizationId:'org',buildingId:'b',...data}})};}
const template={action:'hourTemplates',templateId:'t',name:'Standard',hourPricesMinor:rates};
const quote={action:'quote',roomId:'r',startLocal:'2026-10-10 14:00',endLocal:'2026-10-10 17:00',pricingType:'hourly',hourPricesMinor:rates};
test('successive hours add, final rate repeats, partial hours prorate, USD rounds once',()=>{
 for(const [hours,total] of [[.5,150000],[1,300000],[2,500000],[3,600000],[4,700000],[4.5,750000]])assert.equal(bookingPrice({currency:'VND'},0,hours*3600000,'hourly',{hourPricesMinor:rates}).totalMinor,total);
 assert.equal(bookingPrice({currency:'USD'},0,1.5*3600000,'hourly',{hourPricesMinor:[1001,501]}).totalMinor,1252);
 for(const list of [[],[0],[-1],[1.2],[1e12+1],Array(169).fill(1)])assert.throws(()=>bookingPrice({},0,3600000,'hourly',{hourPricesMinor:list}));
});
test('create, retry, choose without override, delete, and preserve historical booking',async()=>{
 const {call,db}=setup();await call(template);await call(template);
 assert.equal((await call({action:'rooms'})).hourTemplates.length,1);
 assert.equal((await call(quote,'desk')).record.totalMinor,600000);
 await call({...quote,action:'save',bookingId:'k',operationId:'save',guestName:'Guest',guestPhone:'',notes:'',depositMinor:0,roomRevision:'0:0'});
 assert.deepEqual(db.store.get('bookings/k').hourPrices,rates);
 await call({action:'hourTemplates',templateId:'t',remove:true});await call({action:'hourTemplates',templateId:'t',remove:true});
 assert.equal((await call({action:'rooms'})).hourTemplates.length,0);
 assert.equal((await call({...quote,bookingId:'k'},'desk')).record.totalMinor,600000);
 const old={...quote,bookingId:'k'};delete old.hourPricesMinor;
 assert.equal((await call(old,'desk')).record.totalMinor,600000);
 await assert.rejects(call(quote,'desk'),e=>e.code==='permission-denied');
});
test('template writes and arbitrary rates require permission; invalid and cross-org data denied',async()=>{
 const {call,db}=setup();await assert.rejects(call(template,'desk'),e=>e.code==='permission-denied');
 for(const patch of [{name:''},{hourPricesMinor:[]},{hourPricesMinor:[0]},{hourPricesMinor:[1.1]}])await assert.rejects(call({...template,...patch}),e=>e.code==='invalid-argument');
 await call(template);
 await assert.rejects(call({...template,name:'overwrite'}),e=>e.code==='already-exists');
 await assert.rejects(call({...quote,hourPricesMinor:[1]},'desk'),e=>e.code==='permission-denied');
 await assert.rejects(call({...quote,hourlyPriceMinor:100000}),e=>e.code==='invalid-argument');
 db.store.get('memberships/desk_org').status='suspended';await assert.rejects(call(quote,'desk'),e=>e.code==='permission-denied');
 db.store.get('buildings/b').organizationId='elsewhere';await assert.rejects(call(template),e=>e.code==='not-found');
});
test('templates remain property/currency scoped and bounded; old organizations are denied',async()=>{
 const {call,db}=setup();await call(template);
 db.store.get('rooms/r').currency='USD';
 await assert.rejects(call(quote,'desk'),e=>e.code==='permission-denied');
 db.store.get('rooms/r').currency='VND';
 db.store.set('buildings/other',{organizationId:'org',currency:'VND',timeZone:'Asia/Ho_Chi_Minh'});
 assert.deepEqual((await call({action:'rooms',buildingId:'other'})).hourTemplates,[]);
 for(let i=1;i<20;i++)await call({...template,templateId:'t'+i});
 await assert.rejects(call({...template,templateId:'overflow'}),e=>e.code==='failed-precondition');
 db.store.get('organizations/org').accessVersion=1;
 await assert.rejects(call({action:'rooms'}),e=>e.code==='permission-denied');
});
test('identical template retry ignores Firestore map field order',async()=>{
 const {call,db}=setup();await call(template);
 db.store.get('buildingHourTemplates/b').templates=[{currency:'VND',hourPricesMinor:rates,id:'t',name:'Standard'}];
 assert.equal((await call(template)).hourTemplates.length,1);
});
