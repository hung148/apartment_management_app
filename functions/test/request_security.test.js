'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createRequestGuard,createSecureCallable}=require('../request_security');
class HttpsError extends Error{constructor(code,message){super(message);this.code=code;}}
function fixture(){
 let time=1000000;const records=new Map();
 const db={doc:path=>({path,get:async()=>({data:()=>records.get(path)})}),runTransaction:async run=>run({
  get:async ref=>({ref,data:()=>records.get(ref.path)}),set:(ref,data)=>records.set(ref.path,data),
 })};
 const deps={db,HttpsError,Timestamp:{fromMillis:v=>v},now:()=>time};
 return {records,deps,guard:createRequestGuard(deps),advance:ms=>time+=ms};
}
const request=(data={})=>({auth:{uid:'user'},app:{appId:'registered-app'},data});
test('missing Auth or App Check never reaches storage or the handler',async()=>{
 const f=fixture();let called=0,options;
 const register=createSecureCallable({ ...f.deps,onCall:(o,h)=>{options=o;return h;}});
 const handler=register('invoices',{enforceAppCheck:false},()=>called++);
 assert.equal(options.enforceAppCheck,true);
 for(const input of [{data:{}},{auth:{uid:'user'},data:{}}])await assert.rejects(handler(input),e=>e.code==='unauthenticated');
 assert.equal(called,0);assert.equal(f.records.size,0);
});
test('legacy calendar buckets derive organization from saved records, not forged top-level scope',async()=>{
 const f=fixture();
 f.records.set('memberships/user_org',{ownerId:'user',organizationId:'org',accessVersion:2,status:'active',role:'owner'});
 f.records.set('bookings/booking',{organizationId:'org'});
 await f.guard('mutateCalendarBooking',request({bookingId:'booking',action:'payment',organizationId:'foreign'}));
 assert.equal(f.records.size,4,'the actual organization must receive a debit');
});
test('lookup limits ignore forged clock, operation IDs and org IDs; server time alone replenishes',async()=>{
 const f=fixture();
 for(let i=0;i<12;i++)await f.guard('lookupTeamInvitation',request({invitationId:`guess${i}`,now:1,organizationId:`foreign${i}`}));
 await assert.rejects(f.guard('lookupTeamInvitation',request({now:9999999999999,operationId:'new'})),e=>e.code==='resource-exhausted');
 f.advance(10000);await f.guard('lookupTeamInvitation',request());
 f.advance(-86400000);await assert.rejects(f.guard('lookupTeamInvitation',request()),e=>e.code==='resource-exhausted');
 assert.equal(f.records.size,2,'outsiders cannot create organization buckets');
});
test('costly attempts share a budget across endpoints; malformed and denied attempts count',async()=>{
 const f=fixture();
 for(const name of ['aiChat','aiImportPreview','aiImportCommit','aiSyncSubscription'])await f.guard(name,request());
 await assert.rejects(f.guard('aiChat',request()),e=>e.code==='resource-exhausted');
 for(let i=0;i<115;i++)await assert.rejects(f.guard('invoices',request({text:'x'.repeat(131073)})),e=>e.code==='invalid-argument');
 await assert.rejects(f.guard('readWorkspace',request()),e=>e.code==='resource-exhausted');
});
test('organization budgets only include identity-matched active known members',async()=>{
 const f=fixture();
 f.records.set('memberships/user_org',{ownerId:'other',organizationId:'org',accessVersion:2,status:'active',role:'owner'});
 await f.guard('readWorkspace',request({organizationId:'org'}));assert.equal(f.records.size,2);
 f.records.set('memberships/user_org',{ownerId:'user',organizationId:'org',accessVersion:2,status:'active',role:'owner'});
 await f.guard('readWorkspace',request({organizationId:'org'}));assert.equal(f.records.size,3);
});
