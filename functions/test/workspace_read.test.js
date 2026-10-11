// readWorkspace shows room numbers and property-local booking times (2026-10-01).
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createWorkspaceHandler}=require('../workspace');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const db=()=>fakeDb({
  'organizations/org':{accessVersion:2,createdBy:'owner'},
  'memberships/owner_org':{ownerId:'owner',organizationId:'org',accessVersion:2,role:'owner',status:'active',buildingScope:'all',buildingIds:[]},
  'buildings/b1':{organizationId:'org',name:'Tower',timeZone:'Asia/Ho_Chi_Minh'},
  'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'P602'},
  'bookings/k1':{organizationId:'org',buildingId:'b1',roomId:'r1',guestName:'Khach',status:'pending',
    startTime:new Ts(Date.parse('2026-09-27T21:00:00Z')),endTime:new Ts(Date.parse('2026-09-28T02:00:00Z'))},
  'payments/p1':{organizationId:'org',buildingId:'b1',roomId:'r1',type:'rent',status:'pending',amount:5,paidAmount:0,currency:'VND'},
});
const call=(store,data)=>createWorkspaceHandler({db:store,HttpsError:CodeError})({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'b1',...data}});

test('bookings list carries the room number and property-local times',async()=>{
  const {records:[b]}=await call(db(),{view:'bookings'});
  assert.equal(b.roomNumber,'P602');
  assert.deepEqual([b.startLocal,b.endLocal,b.timeZone],['2026-09-28 04:00','2026-09-28 09:00','Asia/Ho_Chi_Minh']);
  const {records:[p]}=await call(db(),{view:'financial'});
  assert.equal(p.roomNumber,'P602');
});

test('task list names the assigned person',async()=>{
  const store=db();
  store.store.set('memberships/maid_org',{ownerId:'maid',organizationId:'org',accessVersion:2,role:'housekeeper',status:'active',buildingScope:'all',buildingIds:[],displayName:'Chị Lan'});
  store.store.set('housekeepingTasks/t1',{organizationId:'org',buildingId:'b1',roomId:'r1',title:'Dọn phòng',status:'open',assigneeId:'maid',createdAt:new Ts(1)});
  store.store.set('housekeepingTasks/t2',{organizationId:'org',buildingId:'b1',roomId:'r1',title:'Gone',status:'open',assigneeId:'left',createdAt:new Ts(2)});
  const {records}=await call(store,{view:'tasks'});
  const by=Object.fromEntries(records.map(r=>[r.id,r]));
  assert.deepEqual([by.t1.assigneeName,by.t1.roomNumber],['Chị Lan','P602']);
  assert.equal(by.t2.assigneeName,'');
});

test('task list shows the real work time in the property time zone',async()=>{
  const store=db();
  store.store.set('housekeepingTasks/t1',{organizationId:'org',buildingId:'b1',roomId:'r1',title:'Don',status:'completed',assigneeId:'owner',
    startedAt:new Ts(Date.parse('2026-10-06T02:45:00Z')),completedAt:new Ts(Date.parse('2026-10-06T03:20:00Z')),createdAt:new Ts(1)});
  store.store.set('housekeepingTasks/t2',{organizationId:'org',buildingId:'b1',roomId:'r1',title:'New',status:'assigned',assigneeId:'owner',createdAt:new Ts(2)});
  const {records}=await call(store,{view:'tasks'});
  const by=Object.fromEntries(records.map(r=>[r.id,r]));
  assert.deepEqual([by.t1.startedLocal,by.t1.completedLocal],['2026-10-06 09:45','2026-10-06 10:20']);
  assert.deepEqual([by.t2.startedLocal,by.t2.completedLocal],[undefined,undefined]);
  assert.equal(by.t1.startedAt,undefined);
});

// 2026-10-11 (Tom): cleaning tasks newest first, page after page.
test('task list is newest first across pages',async()=>{
  const store=db();
  for(let i=1;i<=30;i++)store.store.set(`housekeepingTasks/t${String(i).padStart(2,'0')}`,{organizationId:'org',buildingId:'b1',roomId:'r1',title:'Don',status:'completed',assigneeId:'owner',
    createdAt:new Ts(Date.parse('2026-01-01T00:00:00Z')+i*86400000)});
  const first=await call(store,{view:'tasks',limit:20});
  assert.deepEqual(first.records.slice(0,3).map(r=>r.id),['t30','t29','t28']);
  assert.equal(first.nextCursor,'t11');
  const second=await call(store,{view:'tasks',limit:20,cursor:first.nextCursor});
  assert.deepEqual(second.records.map(r=>r.id),['t10','t09','t08','t07','t06','t05','t04','t03','t02','t01']);
  assert.equal(second.nextCursor,null);
  // Another organization's task is never a cursor.
  store.store.set('housekeepingTasks/x',{organizationId:'other',buildingId:'b1',createdAt:new Ts(5)});
  await assert.rejects(call(store,{view:'tasks',cursor:'x'}),e=>e.code==='invalid-argument');
});
