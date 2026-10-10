'use strict';
const {test,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const {createSessionsHandler,sessionCheck}=require('../account_sessions');
const {createRequestGuard}=require('../request_security');
class HttpsError extends Error{constructor(code,message){super(message);this.code=code;}}
// Sign out everywhere (2026-10-06).
function store(){
 const records=new Map();let reads=0;
 const db={doc:path=>({path,get:async()=>{reads++;return {data:()=>records.get(path)};},set:async v=>records.set(path,v)}),
  runTransaction:async run=>run({get:async ref=>({ref,data:()=>records.get(ref.path)}),set:(ref,data)=>records.set(ref.path,data)})};
 return {db,records,reads:()=>reads};
}
const request=(authTime,data={})=>({auth:{uid:'user',token:{auth_time:authTime}},app:{appId:'app'},data});
beforeEach(()=>sessionCheck.clearForTests());

test('signing out everywhere revokes the sign-ins and records Firebase\'s cut-off',async()=>{
 const s=store(),revoked=[];
 const handler=createSessionsHandler({db:s.db,HttpsError,getAuth:()=>({
  revokeRefreshTokens:async uid=>revoked.push(uid),
  getUser:async()=>({tokensValidAfterTime:'Fri, 09 Oct 2026 10:00:05 GMT'}),
 })});
 await assert.rejects(handler(request(1,{})),e=>e.code==='invalid-argument');
 assert.deepEqual(revoked,[]);
 assert.deepEqual(await handler(request(1,{action:'signOutEverywhere'})),{status:'signedOutEverywhere'});
 assert.deepEqual(revoked,['user']);
 assert.deepEqual(s.records.get('accountSessions/user'),{validAfterSec:Date.UTC(2026,9,9,10,0,5)/1000});
});

test('the guard refuses sign-ins from before the cut-off, and only those',async()=>{
 const s=store();
 const guard=createRequestGuard({db:s.db,HttpsError,Timestamp:{fromMillis:v=>v}});
 await guard('invoices',request(500));                     // no cut-off yet
 sessionCheck.clearForTests();
 s.records.set('accountSessions/user',{validAfterSec:1000});
 await assert.rejects(guard('invoices',request(999)),e=>e.code==='unauthenticated'&&e.message==='session_revoked');
 await assert.rejects(guard('invoices',request(undefined)),e=>e.message==='session_revoked');
 await guard('invoices',request(1000));                    // signed in again since
 await guard('invoices',request(1500));
});

test('concurrent requests share one read; re-read after 30 s',async()=>{
 const s=store();s.records.set('accountSessions/user',{validAfterSec:1000});
 const results=await Promise.all([0,1,2,3].map(()=>sessionCheck.revoked(s.db,'user',2000,10000)));
 assert.deepEqual(results,[false,false,false,false]);
 assert.equal(s.reads(),1);
 await sessionCheck.revoked(s.db,'user',2000,20000);
 assert.equal(s.reads(),1);
 s.records.set('accountSessions/user',{validAfterSec:3000});
 assert.equal(await sessionCheck.revoked(s.db,'user',2000,40001),true);
 assert.equal(s.reads(),2);
});

test('a failed read fails closed and is retried next time',async()=>{
 let fail=true,reads=0;
 const db={doc:()=>({get:async()=>{reads++;if(fail)throw Error('down');return {data:()=>undefined};}})};
 await assert.rejects(sessionCheck.revoked(db,'user',5,0));
 fail=false;
 assert.equal(await sessionCheck.revoked(db,'user',5,1),false);
 assert.equal(reads,2);
});
