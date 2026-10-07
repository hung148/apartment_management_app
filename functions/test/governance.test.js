const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createGovernanceHandler}=require('../governance');
for(const action of ['list','propose','approve','decline','revokeShare','execute'])test('retired governance '+action+' cannot expose or alter historical authority',async()=>{
 const db=fakeDb({'organizations/a':{createdBy:'owner',accessVersion:2},'ownershipAgreements/old':{status:'approved',kind:'coOwner',organizationId:'a'},'staffShares/old':{status:'active',organizationId:'b'},'memberships/partner_a':{role:'coOwner',status:'active'}}),before=JSON.stringify([...db.store]);
 const g=createGovernanceHandler({db,Timestamp:Ts,HttpsError:CodeError});
 for(const uid of ['owner','partner','staff','outsider'])await assert.rejects(g({auth:{uid},data:{action,organizationId:'a',agreementId:'old',operationId:'old'}}),e=>e.code==='failed-precondition'&&e.message==='organization_governance_retired');
 assert.equal(JSON.stringify([...db.store]),before);
});
test('retired route still requires sign-in',async()=>{
 const g=createGovernanceHandler({db:fakeDb(),Timestamp:Ts,HttpsError:CodeError});
 await assert.rejects(g({data:{action:'list'}}),e=>e.code==='unauthenticated');
});
