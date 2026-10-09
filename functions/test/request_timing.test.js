'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {timeRequest}=require('../request_timing');
test('timing separates guard and handler without recording private results',async()=>{
 const ticks=[100,130,180],events=[];
 const result=await timeRequest({name:'invoices',clock:()=>ticks.shift(),
  guard:async()=>{},handler:async()=>({private:'tenant'}),observe:x=>events.push(x)});
 assert.deepEqual(result,{private:'tenant'});
 assert.deepEqual(events,[{event:'app_request_timing',fn:'invoices',outcome:'ok',totalMs:80,guardMs:30,handlerMs:50}]);
});
test('failed guard never calls handler and timings contain no error message',async()=>{
 const ticks=[10,25],events=[],error=Error('private reason');let called=false;
 await assert.rejects(timeRequest({name:'invoices',clock:()=>ticks.shift(),
  guard:async()=>{throw error;},handler:async()=>{called=true;},observe:x=>events.push(x)}),e=>e===error);
 assert.equal(called,false);
 assert.deepEqual(events,[{event:'app_request_timing',fn:'invoices',outcome:'error',totalMs:15,guardMs:15,handlerMs:null}]);
});
test('failed telemetry cannot turn a successful write into an apparent failure',async()=>{
 assert.equal(await timeRequest({name:'invoices',guard:async()=>{},handler:async()=>42,
  observe:()=>{throw Error('logging failed');}}),42);
});
