// Housekeeping tasks (cleaning): planned window and real work time (2026-10-05).
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createHousekeepingHandler}=require('../housekeeping');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const seed=()=>({
 'organizations/org':{accessVersion:2,createdBy:'owner'},
 'memberships/owner_org':{ownerId:'owner',organizationId:'org',accessVersion:2,role:'owner',status:'active',buildingScope:'all',buildingIds:[]},
 'memberships/maid_org':{ownerId:'maid',organizationId:'org',accessVersion:2,role:'housekeeper',status:'active',buildingScope:'all',buildingIds:[]},
 'buildings/b1':{organizationId:'org',name:'Toa A',timeZone:'Asia/Ho_Chi_Minh'},
 'rooms/r101':{organizationId:'org',buildingId:'b1',roomNumber:'101'},
});
const call=(db,data,uid='owner')=>createHousekeepingHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid},data:{organizationId:'org',...data}});
const assign=extra=>({action:'assign',operationId:'op1',taskId:'t1',buildingId:'b1',roomId:'r101',assigneeId:'maid',title:'Don phong',...extra});
const code=async(p,c)=>assert.equal((await p.then(()=>null,e=>e)).code,c);

test('a planned window is kept; start and done times are recorded',async()=>{
 const db=fakeDb(seed());
 Ts.clock=Date.parse('2026-10-03T05:00:00Z');
 await call(db,assign({plannedStart:'2026-10-03 13:00',plannedEnd:'2026-10-03 14:00'}));
 let t=db.store.get('housekeepingTasks/t1');
 assert.deepEqual([t.status,t.plannedStart,t.plannedEnd],['assigned','2026-10-03 13:00','2026-10-03 14:00']);
 Ts.clock=Date.parse('2026-10-03T06:10:00Z');
 await call(db,{action:'status',operationId:'op2',taskId:'t1',status:'inProgress'},'maid');
 t=db.store.get('housekeepingTasks/t1');
 assert.equal(t.startedAt.toMillis(),Date.parse('2026-10-03T06:10:00Z'));assert.equal(t.startedBy,'maid');
 Ts.clock=Date.parse('2026-10-03T06:50:00Z');
 await call(db,{action:'status',operationId:'op3',taskId:'t1',status:'completed'},'maid');
 t=db.store.get('housekeepingTasks/t1');
 assert.equal(t.completedAt.toMillis(),Date.parse('2026-10-03T06:50:00Z'));
});

test('without a plan it still works; a bad or half window is refused',async()=>{
 const db=fakeDb(seed());
 await call(db,assign({}));
 assert.equal(db.store.get('housekeepingTasks/t1').plannedStart,undefined);
 for(const bad of [{plannedStart:'2026-10-03 13:00'},{plannedStart:'2026-10-03 14:00',plannedEnd:'2026-10-03 13:00'},{plannedStart:'2026-10-03 13:00',plannedEnd:'2026-10-03 13:00'},{plannedStart:'13:00',plannedEnd:'14:00'},{plannedStart:'2026-13-03 13:00',plannedEnd:'2026-13-03 14:00'}]){
  await code(call(fakeDb(seed()),assign(bad)),'invalid-argument');
 }
});
