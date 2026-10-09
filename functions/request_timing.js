'use strict';
// Aggregate timings only: never log request data, account IDs or error messages.
async function timeRequest({name,guard,handler,observe,clock=()=>performance.now()}){
 const start=clock();let guarded=null,outcome='error';
 try{
  await guard();guarded=clock();
  const result=await handler();outcome='ok';return result;
 }finally{
  const end=clock();
  try{observe({event:'app_request_timing',fn:name,outcome,
   totalMs:Math.max(0,Math.round(end-start)),
   guardMs:Math.max(0,Math.round((guarded??end)-start)),
   handlerMs:guarded===null?null:Math.max(0,Math.round(end-guarded)),
  });}catch{/* Diagnostics must never change a business operation's result. */}
 }
}
module.exports={timeRequest};
