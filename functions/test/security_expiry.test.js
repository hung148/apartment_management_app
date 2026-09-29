'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {createImport}=require('../ai_import');
test('an unsaved import expires at the exact server boundary regardless of client date',async t=>{
 const serverTime=1800000000000;t.mock.method(Date,'now',()=>serverTime);
 let writes=0;
 const records=[{key:'org',type:'organization',fields:{name:'Draft'}}];
 const db={doc:path=>({path}),runTransaction:async run=>run({
  get:async ref=>({exists:ref.path==='aiDrafts/draft',data:()=>({ownerId:'u',status:'review',expiresAt:{toMillis:()=>serverTime},records})}),
  create:()=>writes++,update:()=>writes++,
 })};
 const api=createImport({db,Timestamp:{now:()=>serverTime},ai:{uid:r=>r.auth.uid,fail:(code,message)=>{throw Object.assign(Error(message),{code});}}});
 for(const clientTime of ['2025-01-01','2030-01-01'])
  await assert.rejects(api.commit({auth:{uid:'u'},data:{draftId:'draft',records,clientTime}}),e=>e.message==='ai_import_expired');
 assert.equal(writes,0);
});
