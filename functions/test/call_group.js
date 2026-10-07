'use strict';
// Grouped functions (2026-10-06): tests that used to run one exported function
// per call name now run the call through its group, exactly as the app sends it.
const group=name=>name==='importSheet'?'heavy':'app';
const via=(api,name)=>({run:request=>api[group(name)].run({...request,data:{fn:name,data:request.data}})});
module.exports={via,group};
