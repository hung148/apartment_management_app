// Speed (2026-10-09): a call that only reads starts alongside the request guard; its answer is
// held until the guard passes, so a refusal is still what the app gets. Writes wait for the guard.
const {test,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const {createCallableGroups}=require('../request_security');
const {timeRequest}=require('../request_timing');
const {sessionCheck}=require('../account_sessions');
const {fakeDb}=require('./fake_firestore');
class HttpsError extends Error{constructor(code,message){super(message);this.code=code;}}
beforeEach(()=>sessionCheck.clearForTests());
const request=(data,uid='user',authTime=5000)=>({auth:{uid,token:{auth_time:authTime}},app:{appId:'app'},data});
function setup({observe}={}){
 const db=fakeDb(),order=[];
 let time=1000000;
 const g=createCallableGroups({db,HttpsError,Timestamp:{fromMillis:v=>v},now:()=>time,onCall:(o,h)=>h,...(observe?{observe}:{})});
 // claimMyInvitations is charged to the small "lookup" bucket (12): easy to run out.
 g.register('claimMyInvitations',{readOnly:true},r=>{order.push(['read',r.auth.uid]);return {secret:'answer'};});
 g.register('invoices',{readOnly:d=>d?.action==='list'},r=>{order.push(['invoices',r.data.action]);return {ok:r.data.action};});
 g.register('readTeam',{readOnly:()=>{throw Error('broken');}},()=>{order.push(['team']);return {ok:true};});
 return {db,order,app:g.group('app'),g,advance:ms=>{time+=ms;}};
}

test('a read starts alongside the guard and returns its answer once the guard passed',async()=>{
 const {app,order}=setup();
 let guardDone=false;
 const pending=app(request({fn:'claimMyInvitations',data:{}}));
 // The read starts at once, before the guard's first storage round trip has finished.
 await Promise.resolve();await Promise.resolve();
 assert.deepEqual(order,[['read','user']]);
 assert.deepEqual(await pending.then(r=>{guardDone=true;return r;}),{secret:'answer'});
 assert.ok(guardDone);
});

test('a refused guard wins: the read\'s answer is never returned',async()=>{
 const {app,order}=setup();
 for(let i=0;i<12;i++)await app(request({fn:'claimMyInvitations',data:{}}));
 await assert.rejects(app(request({fn:'claimMyInvitations',data:{}})),e=>e.code==='resource-exhausted'&&e.message==='request_rate_limited');
 assert.equal(order.length,13,'the 13th read had started');
 // Refused by the rate limit: for a minute this account's reads wait for the guard again.
 await assert.rejects(app(request({fn:'claimMyInvitations',data:{}})),e=>e.message==='request_rate_limited');
 assert.equal(order.length,13,'no read started after the refusal');
 // Another account is not affected.
 assert.deepEqual(await app(request({fn:'claimMyInvitations',data:{}},'other')),{secret:'answer'});
 assert.equal(order.length,14);
});

test('a signed-out-everywhere session gets the refusal, not the data',async()=>{
 const {app,db,order}=setup();
 db.store.set('accountSessions/user',{validAfterSec:6000});
 await assert.rejects(app(request({fn:'claimMyInvitations',data:{}})),e=>e.code==='unauthenticated'&&e.message==='session_revoked');
 assert.equal(order.length,1);
});

test('only the actions marked as reads start early; writes and broken markers wait',async()=>{
 const {app,order,db}=setup();
 db.store.set('accountSessions/user',{validAfterSec:6000});
 // Refused by the guard: the write never ran, the list (a read) had started.
 await assert.rejects(app(request({fn:'invoices',data:{action:'create'}})),e=>e.message==='session_revoked');
 await assert.rejects(app(request({fn:'invoices',data:{action:'list'}})),e=>e.message==='session_revoked');
 await assert.rejects(app(request({fn:'readTeam',data:{}})),e=>e.message==='session_revoked');
 assert.deepEqual(order,[['invoices','list']]);
 sessionCheck.clearForTests();db.store.delete('accountSessions/user');
 assert.deepEqual(await app(request({fn:'invoices',data:{action:'create'}})),{ok:'create'});
 assert.deepEqual(await app(request({fn:'readTeam',data:{}})),{ok:true});
});

test('a bad readOnly marker is refused when the call is registered',()=>{
 const {g}=setup();
 assert.throws(()=>g.register('readWorkspace',{readOnly:'yes'},()=>1),/readOnly/);
});

test('a handler error is returned as before once the guard passed',async()=>{
 const db=fakeDb();
 const g=createCallableGroups({db,HttpsError,Timestamp:{fromMillis:v=>v},onCall:(o,h)=>h});
 g.register('calendarView',{readOnly:true},()=>{throw new HttpsError('permission-denied','no');});
 await assert.rejects(g.group('app')(request({fn:'calendarView',data:{}})),e=>e.code==='permission-denied');
});

test('timings mark early reads; handlerMs is the wait left after the guard',async()=>{
 const events=[];let t=0;
 const clock=()=>t;
 const out=await timeRequest({name:'calendarView',early:true,clock,observe:e=>events.push(e),
  handler:async()=>{t+=5;return 'data';},guard:async()=>{await new Promise(r=>setImmediate(r));t+=10;}});
 assert.equal(out,'data');
 assert.deepEqual([events[0].early,events[0].outcome,events[0].guardMs],[true,'ok',15]);
 // A refused guard: outcome error, the read's answer dropped.
 await assert.rejects(timeRequest({name:'calendarView',early:true,clock,observe:e=>events.push(e),
  handler:async()=>'data',guard:async()=>{throw new HttpsError('resource-exhausted','x');}}),e=>e.code==='resource-exhausted');
 assert.equal(events[1].outcome,'error');assert.equal(events[1].handlerMs,null);
 // Not early: no mark.
 await timeRequest({name:'x',clock,observe:e=>events.push(e),handler:async()=>1,guard:async()=>{}});
 assert.equal(events[2].early,undefined);
});
