const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createOrganizationSettingsHandler}=require('../organization_settings');
const {createPropertyDetailsHandler}=require('../property_details');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
function fixture(){const db=fakeDb({'organizations/org':{accessVersion:2},'memberships/u_org':{organizationId:'org',ownerId:'u',role:'owner',status:'active',accessVersion:2,buildingScope:'all'},'buildings/existing':{organizationId:'org',currency:'VND',exploitationCostMinor:123},'rooms/r':{organizationId:'org',currency:'VND',roomPrice:5000000},'payments/p':{organizationId:'org',currency:'VND',amount:5000000}});const api=createOrganizationSettingsHandler({db,Timestamp:Ts,HttpsError:CodeError});return {db,run:d=>api({auth:{uid:'u'},data:{organizationId:'org',...d}})};}
const change={action:'updateCurrency',operationId:'change',revision:0,currency:'USD'};
test('organization currency inherits safely and preserves all saved monetary records',async()=>{
 const {db,run}=fixture();assert.deepEqual(await run({action:'readCurrency'}),{currency:'VND',revision:0,canChange:true});
 const before=structuredClone([...db.store.entries()].filter(([k])=>!k.startsWith('organizations/')));
 const result=await run(change);assert.equal(result.currency,'USD');assert.deepEqual(await run(change),result);
 for(const [k,v] of before)assert.deepEqual(db.store.get(k),v);
 const property=createPropertyDetailsHandler({db,Timestamp:Ts,HttpsError:CodeError});const p=d=>property({auth:{uid:'u'},data:{organizationId:'org',buildingId:'new',...d}});
 assert.equal((await p({action:'prepareCreate'})).record.currency,'USD');
 const create={action:'create',operationId:'build',name:'New',address:'Address',timeZone:'UTC',currency:'VND'};
 await assert.rejects(p(create),e=>e.code==='aborted');
 await p({...create,currency:'USD'});assert.equal(db.store.get('buildings/new').currency,'USD');
 await run({...change,operationId:'second',revision:1,currency:'VND'});
 await p({...create,currency:'USD'}); // A committed old operation still retries safely.
 assert.equal(db.store.get('buildings/new').currency,'USD');
});
test('currency write requires dedicated grant, including on retry, while active staff can read',async()=>{
 for(const role of ['manager','administrator','receptionist','staff']){
  const {db,run}=fixture();db.store.get('memberships/u_org').role=role;
  assert.equal((await run({action:'readCurrency'})).canChange,false);
  await assert.rejects(run(change),e=>e.code==='permission-denied');
  db.store.get('memberships/u_org').roleGrants={changeOrganizationCurrency:'all'};
  await run(change);
  db.store.get('memberships/u_org').status='revoked';await assert.rejects(run(change),e=>e.code==='permission-denied');
 }
});
test('currency rejects stale edits, changed retries, invalid input and unavailable memberships',async()=>{
 const {run}=fixture();await run(change);
 await assert.rejects(run({...change,operationId:'other'}),e=>e.code==='aborted');
 await assert.rejects(run({...change,currency:'VND'}),e=>e.code==='already-exists');
 for(const patch of [{currency:'EUR'},{revision:-1},{revision:0.5},{unexpected:true}])await assert.rejects(run({...change,...patch}),e=>e.code==='invalid-argument');
 for(const patch of [{status:'suspended'},{status:'revoked'},{organizationId:'foreign'},{ownerId:'foreign'},{accessVersion:1},{role:'coOwner'}]){
  const {db,run}=fixture();Object.assign(db.store.get('memberships/u_org'),patch);await assert.rejects(run({action:'readCurrency'}),e=>e.code==='permission-denied');
 }
 for(const patch of [{closedAt:true},{mergedInto:'other'},{accessVersion:1}]){const {db,run}=fixture();Object.assign(db.store.get('organizations/org'),patch);await assert.rejects(run(change),e=>e.code==='permission-denied');}
});
