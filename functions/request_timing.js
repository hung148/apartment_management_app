'use strict';
// Aggregate timings only: never log request data, account IDs or error messages.
// early: the handler (a read) started together with the guard; handlerMs is
// then the wait left after the guard passed.
async function timeRequest({name,guard,handler,observe,early=false,clock=()=>performance.now()}){
 const start=clock();let guarded=null,outcome='error';
 try{
  let pending=null;
  if(early){pending=handler();pending.catch(()=>{});}
  await guard();guarded=clock();
  const result=await(pending??handler());outcome='ok';return result;
 }finally{
  const end=clock();
  try{observe({event:'app_request_timing',fn:name,outcome,...(early?{early:true}:{}),
   totalMs:Math.max(0,Math.round(end-start)),
   guardMs:Math.max(0,Math.round((guarded??end)-start)),
   handlerMs:guarded===null?null:Math.max(0,Math.round(end-guarded)),
  });}catch{/* Diagnostics must never change a business operation's result. */}
 }
}
module.exports={timeRequest};
