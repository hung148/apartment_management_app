const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const {callableNames,retiredCallable,retiredWebhook}=require('../retired_ai');
test('retired AI calls reject every identity and old draft without external work',()=>{
 class ErrorWithCode extends Error{constructor(code,message){super(message);this.code=code;}}
 for(const name of callableNames)for(const uid of [null,'owner','coOwner','staff','revoked'])for(let retry=0;retry<2;retry++){
  const request={data:{draftId:'historical',records:[{type:'organization'}]},auth:uid?{uid}:null};
  assert.throws(()=>retiredCallable(ErrorWithCode)(request),e=>e.code==='failed-precondition'&&e.message==='feature_retired',name);
 }
 let status,body;retiredWebhook({}, {status(value){status=value;return this;},json(value){body=value;}});
 assert.equal(status,410);assert.deepEqual(body,{error:'feature_retired'});
});
test('deployed entrypoint has no AI providers or billing secrets',()=>{
 const source=fs.readFileSync(path.join(__dirname,'../index.js'),'utf8');
 assert.doesNotMatch(source,/GEMINI_API_KEY|REVENUECAT_|generativelanguage|createSubscriptions|createAI|createImport/);
 assert.match(source,/retired_ai/);
});
