const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createCalendarHandler,createTenantHandler}=require('../calendar');
class Stamp {constructor(value){this.value=value;} toMillis(){return this.value;} static fromMillis(v){return new Stamp(v);} static now(){return new Stamp(Date.now());}}
class ErrorCode extends Error {constructor(code,message){super(message);this.code=code;}}
class Ref {constructor(db,path){this.db=db;this.path=path;this.id=path.split('/').pop();}}
class Query {constructor(db,name,filters=[]){this.db=db;this.name=name;this.filters=filters;} doc(id){return new Ref(this.db,`${this.name}/${id}`);} where(k,op,v){assert.equal(op,'==');return new Query(this.db,this.name,[...this.filters,[k,v]]);}}
class DB {
 constructor(seed){this.rows=new Map(Object.entries(seed));this.tail=Promise.resolve();this.roomWrites=0;}
 collection(name){return new Query(this,name);}
 runTransaction(fn){
  const operation=this.tail.then(async()=>{
   const next=new Map([...this.rows].map(([k,v])=>[k,{...v}]));let wrote=false,locks=0;
   const snap=ref=>({ref,id:ref.id,exists:next.has(ref.path),data:()=>({...next.get(ref.path)})});
   const tx={get:async target=>{assert.equal(wrote,false,'All reads must precede writes');
     if(target instanceof Ref)return snap(target);
     return {docs:[...next].filter(([key,v])=>key.startsWith(target.name+'/') && target.filters.every(([k,value])=>v[k]===value)).map(([key])=>snap(new Ref(this,key)))};},
    update:(ref,patch)=>{wrote=true;assert(next.has(ref.path));if(ref.path.startsWith('rooms/'))locks++;next.set(ref.path,{...next.get(ref.path),...patch});},
    set:(ref,value)=>{wrote=true;next.set(ref.path,value);},
    create:(ref,value)=>{wrote=true;assert(!next.has(ref.path));next.set(ref.path,value);},
    delete:ref=>{wrote=true;next.delete(ref.path);}};
   const result=await fn(tx);this.rows=next;this.roomWrites+=locks;return result;
  });this.tail=operation.catch(()=>{});return operation;
 }
}
const context={auth:{uid:'owner'}};
function fixture(){
 const db=new DB({'organizations/org':{createdBy:'owner'},'rooms/room':{organizationId:'org',buildingId:'building',rentalMode:'both',currency:'USD',cleaningBufferMinutes:30}});
 const deps={db,Timestamp:Stamp,FieldValue:{increment:n=>n},HttpsError:ErrorCode};
 return {db,booking:createCalendarHandler(deps),tenant:createTenantHandler(deps)};
}
const request=(id,start=10000000,end=20000000)=>({action:'create',bookingId:id,booking:{organizationId:'org',roomId:'room',guestName:'Guest',guestPhone:'',startTime:{__timestamp:start},endTime:{__timestamp:end},totalPrice:100,depositAmount:20}});
test('Simultaneous overlapping booking requests serialize on the room and only one commits',async()=>{
 const {db,booking}=fixture();const results=await Promise.allSettled([booking(request('a'),context),booking(request('b'),context)]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
 assert.equal(results.find(r=>r.status==='rejected').reason.message,'booking_conflict');
 assert.equal([...db.rows.keys()].filter(k=>k.startsWith('bookings/')).length,1);assert.equal(db.roomWrites,1);
});
test('Cleaning buffer blocks adjacent bookings and edits retain original data on conflict',async()=>{
 const {db,booking}=fixture();await booking(request('a'),context);
 await assert.rejects(booking(request('b',20000000,22000000),context),/booking_conflict/);
 await booking(request('b',24000000,30000000),context);
 await assert.rejects(booking({action:'edit',bookingId:'b',changes:{startTime:{__timestamp:19000000}}},context),/booking_conflict/);
 assert.equal(db.rows.get('bookings/b').startTime.toMillis(),24000000);
});
test('Active leases block bookings and reservations block a new lease',async()=>{
 const {booking,tenant}=fixture();await booking(request('a'),context);
 await assert.rejects(tenant({create:true,tenantId:'t',tenant:{organizationId:'org',roomId:'room',status:'active',fullName:'Tenant',moveInDate:{__timestamp:11000000}}},context),/booking_conflict/);
 await booking({action:'status',bookingId:'a',status:'cancelled'},context);
 await tenant({create:true,tenantId:'t',tenant:{organizationId:'org',roomId:'room',status:'active',fullName:'Tenant',moveInDate:{__timestamp:11000000}}},context);
 await assert.rejects(booking(request('b'),context),/booking_conflict/);
});
test('Payment retries and checkout retries never duplicate revenue',async()=>{
 const {db,booking}=fixture();await booking(request('a'),context);
 const pay={action:'payment',bookingId:'a',amount:25.50,paymentMethod:'cash',operationId:'op'};
 await booking(pay,context);await booking(pay,context);
 assert.equal(db.rows.get('bookings/a').paidAmount,25.5);
 await booking({action:'status',bookingId:'a',status:'checkedIn'},context);
 await booking({action:'checkout',bookingId:'a',paymentMethod:'cash'},context);
 await booking({action:'checkout',bookingId:'a',paymentMethod:'cash'},context);
 const payments=[...db.rows].filter(([k])=>k.startsWith('payments/')).map(([,v])=>v);
 assert.equal(payments.length,2);assert.equal(payments.reduce((sum,p)=>sum+p.paidAmount,0),100);
 assert(payments.every(p=>p.currency==='USD'));
});
test('Deposit collection and partial refund validate collected funds',async()=>{
 const {db,booking}=fixture();await booking(request('a'),context);
 await assert.rejects(booking({action:'refund',bookingId:'a',operationId:'bad',amount:1,paymentMethod:'cash'},context),/booking_refund_exceeds_deposit/);
 await booking({action:'deposit',bookingId:'a',operationId:'deposit',amount:20,paymentMethod:'cash'},context);
 await booking({action:'refund',bookingId:'a',operationId:'refund',amount:5,paymentMethod:'cash'},context);
 assert.equal(db.rows.get('bookings/a').depositRefundedAmount,5);assert.equal(db.rows.get('bookings/a').depositRefunded,false);
 await assert.rejects(booking({action:'refund',bookingId:'a',operationId:'excess',amount:16,paymentMethod:'cash'},context),/booking_refund_exceeds_deposit/);
});
test('Rejects unauthorized users, invalid amounts, and illegal status changes',async()=>{
 const {booking}=fixture();await assert.rejects(booking(request('a'),{auth:{uid:'stranger'}}),/booking_access_denied/);
 await assert.rejects(booking(request('a'),{}),/booking_sign_in_required/);
 await booking(request('a'),context);
 await assert.rejects(booking({action:'payment',bookingId:'a',operationId:'op',amount:100.01,paymentMethod:'cash'},context),/booking_overpayment/);
 await assert.rejects(booking({action:'checkout',bookingId:'a',paymentMethod:'cash'},context),/booking_invalid_transition/);
 await assert.rejects(booking({action:'edit',bookingId:'a',changes:{totalPrice:1.234}},context),/booking_invalid_request/);
});

test('Deployed callable wrappers forward second-generation request data and authentication', async () => {
 const exported = require('../index');
 for (const name of ['mutateCalendarBooking','mutateCalendarTenant']) {
   await assert.rejects(exported[name].run({data:{}}), error => error.code === 'unauthenticated');
   await assert.rejects(exported[name].run({data:{},auth:{uid:'owner'}}), error => error.code === 'invalid-argument');
 }
});
