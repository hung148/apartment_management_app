'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createDeletedRecordsHandler}=require('../deleted_records');
function fixture(){
 const db=fakeDb({'organizations/org':{createdBy:'owner',accessVersion:2},'memberships/owner_org':{ownerId:'owner',organizationId:'org',role:'owner',status:'active',accessVersion:2,buildingScope:'all'},
  'buildings/a':{organizationId:'org'},'rooms/r':{organizationId:'org',buildingId:'a',roomNumber:'101'},
  'bookings/b':{organizationId:'org',buildingId:'a',roomId:'r',guestName:'Guest',status:'cancelled',paidAmount:0,startTime:Ts.fromMillis(1000),endTime:Ts.fromMillis(2000)},
  'memberships/worker_org':{ownerId:'worker',organizationId:'org',accessVersion:2,role:'custom',roleGrants:{deleteBookings:'managed'},status:'active',buildingScope:'selected',buildingIds:['a']}});
 const handler=createDeletedRecordsHandler({db,Timestamp:Ts,HttpsError:CodeError});
 return {db,call:(data,uid='worker')=>handler({auth:{uid},data:{organizationId:'org',...data}})};
}
test('combined booking permission deletes and restores but grants no room access; exact retry is safe',async()=>{
 const {db,call}=fixture();const d={action:'delete',type:'bookings',recordId:'b',operationId:'delete1'};
 await call(d);assert.equal(db.store.has('bookings/b'),false);await call(d);
 const list=await call({action:'list'});assert.equal(list.records.length,1);
 const r={action:'restore',deletedRecordId:list.records[0].id,operationId:'restore1'};
 await call(r);await call(r);assert.equal(db.store.get('bookings/b').guestName,'Guest');
 assert.equal((await call({action:'list'})).records.length,0);
 await assert.rejects(call({action:'delete',type:'rooms',recordId:'r',buildingId:'a',revision:'1:0',operationId:'room'}),/room_permission-denied/);
});
test('money links and foreign property scope refuse before deletion',async()=>{
 for(const patch of [{paidAmount:1},{buildingId:'foreign'},{status:'confirmed'}]){
  const {db,call}=fixture();Object.assign(db.store.get('bookings/b'),patch);const before=JSON.stringify([...db.store]);
  await assert.rejects(call({action:'delete',type:'bookings',recordId:'b',operationId:'blocked'}));assert.equal(JSON.stringify([...db.store]),before);
 }
});
test('restore refuses missing parent, collision and expired retention',async()=>{
 for(const kind of ['parent','collision','expired']){
  const {db,call}=fixture();await call({action:'delete',type:'bookings',recordId:'b',operationId:'delete1'});
  const row=(await call({action:'list'})).records[0];
  if(kind==='parent')db.store.delete('rooms/r');
  if(kind==='collision')db.store.set('bookings/b',{organizationId:'org'});
  if(kind==='expired')db.store.get('deletedRecords/'+row.id).purgeAfter=Ts.fromMillis(0);
  const before=JSON.stringify([...db.store]);await assert.rejects(call({action:'restore',deletedRecordId:row.id,operationId:'restore1'}));assert.equal(JSON.stringify([...db.store]),before);
 }
});

test('retention purge removes the snapshot and leaves only a minimal ledger',async()=>{
 const {db,call}=fixture();await call({action:'delete',type:'bookings',recordId:'b',operationId:'delete1'});
 const row=(await call({action:'list'})).records[0];db.store.get('deletedRecords/'+row.id).purgeAfter=Ts.fromMillis(0);
 await require('../deleted_records').purgeDeletedRecords({db,Timestamp:Ts});
 const ledger=db.store.get('deletedRecords/'+row.id);assert.equal(ledger.status,'purged');assert.equal(ledger.data,undefined);
 await assert.rejects(call({action:'restore',deletedRecordId:row.id,operationId:'late'}),/org_restore_expired/);
});

test('revoked membership cannot list or restore retained records',async()=>{
 const {db,call}=fixture();await call({action:'delete',type:'bookings',recordId:'b',operationId:'delete1'});
 const row=(await call({action:'list'})).records[0];db.store.get('memberships/worker_org').status='revoked';
 await assert.rejects(call({action:'list'}),/record_recovery_denied/);
 await assert.rejects(call({action:'restore',deletedRecordId:row.id,operationId:'restore'}),/record_recovery_denied/);
});

test('room snapshot preserves settings and needs its original parent; restore does not grant other record permissions',async()=>{
 const {db,call}=fixture();db.store.delete('bookings/b');
 db.store.get('rooms/r').nightlyPrice=750000;
 const room=await db.doc('rooms/r').get();
 await call({action:'delete',type:'rooms',recordId:'r',buildingId:'a',revision:`${room.updateTime.seconds}:${room.updateTime.nanoseconds}`,operationId:'roomDelete'},'owner');
 const row=(await call({action:'list'},'owner')).records[0];
 assert.equal((await call({action:'list'})).records.length,0);
 await call({action:'restore',deletedRecordId:row.id,operationId:'roomRestore'},'owner');
 assert.equal(db.store.get('rooms/r').nightlyPrice,750000);
});

test('nested history is retained and restored at its original path',async()=>{
 const {db,call}=fixture();db.store.set('bookings/b/history/entry',{organizationId:'org',action:'cancel',note:'Keep history'});
 await call({action:'delete',type:'bookings',recordId:'b',operationId:'nested'});
 assert.equal(db.store.has('bookings/b/history/entry'),false);
 const row=(await call({action:'list'})).records[0];await call({action:'restore',deletedRecordId:row.id,operationId:'nestedRestore'});
 assert.equal(db.store.get('bookings/b/history/entry').note,'Keep history');
});

test('ended stay restoration refuses conflicting occupancy; cancelled stays remain cancelled',async()=>{
 const {db,call}=fixture();db.store.get('bookings/b').status='checkedOut';
 await call({action:'delete',type:'bookings',recordId:'b',operationId:'ended'});
 const row=(await call({action:'list'})).records[0];
 db.store.set('bookings/conflict',{organizationId:'org',buildingId:'a',roomId:'r',status:'checkedOut',startTime:Ts.fromMillis(1500),endTime:Ts.fromMillis(2500)});
 await assert.rejects(call({action:'restore',deletedRecordId:row.id,operationId:'conflict'}),/record_recovery_overlap/);
 assert.equal(db.store.has('bookings/b'),false);
});

test('closed problem and unlinked staff profile recover without widening access',async()=>{
 for(const [type,data] of [['technicalProblems',{buildingId:'a',roomId:'r',status:'fixed',title:'Problem',photos:[]}],['staffProfiles',{displayName:'Former worker',accountId:null,code:'S99'}]]){
  const {db,call}=fixture();db.store.set(`${type}/sample`,{organizationId:'org',...data});
  await call({action:'delete',type,recordId:'sample',operationId:'delete'},'owner');
  const row=(await call({action:'list'},'owner')).records.find(r=>r.type===type);
  await call({action:'restore',deletedRecordId:row.id,operationId:'restore'},'owner');
  assert.equal(db.store.get(`${type}/sample`).organizationId,'org');
  assert.equal(db.store.has('memberships/sample_org'),false);
 }
});

test('staff recovery refuses a reused staff code',async()=>{
 const {db,call}=fixture();db.store.set('staffProfiles/old',{organizationId:'org',code:'S99',displayName:'Former',accountId:null});
 await call({action:'delete',type:'staffProfiles',recordId:'old',operationId:'delete'},'owner');
 const row=(await call({action:'list'},'owner')).records[0];
 db.store.set('staffProfiles/new',{organizationId:'org',code:'S99',displayName:'New'});
 await assert.rejects(call({action:'restore',deletedRecordId:row.id,operationId:'restore'},'owner'),/record_recovery_collision/);
 assert.equal(db.store.has('staffProfiles/old'),false);
});
