// 2026-10-04 (Tom): someone added later to a lease gets CCCD and tạm trú too.
const {test}=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createTenantRoommatesHandler}=require('../tenant_roommates');
const at=d=>Ts.fromMillis(Date.parse(d+'T00:00:00+07:00'));

function setup(){
 Ts.clock=Date.parse('2026-10-03T05:00:00Z');
 const db=fakeDb({'organizations/o':{accessVersion:2},'buildings/b':{organizationId:'o',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},'rooms/r':{organizationId:'o',buildingId:'b',roomNumber:'101'},
  'memberships/owner_o':{ownerId:'owner',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all',buildingIds:[]},
  'tenants/t':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:true,status:'active',fullName:'Le Van Chinh',currency:'VND',moveInDate:at('2026-10-02'),moveInLocalDate:'2026-10-02',moveOutDate:null}});
 const call=data=>createTenantRoommatesHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid:'owner'},data:{organizationId:'o',buildingId:'b',mainTenantId:'t',...data}});
 return {db,call};
}

test('a roommate is added with CCCD and tạm trú; bad papers are refused',async()=>{
 const {db,call}=setup();
 const p=(await call({action:'prepare'})).record;
 const base={action:'create',operationId:'R1',mainRevision:p.mainRevision,roomRevision:p.roomRevision,timeZone:p.timeZone,fullName:'Pham Thi Dung',phoneNumber:'',moveInDate:'2026-10-03',backdateReason:''};
 for(const bad of [{nationalId:'1'.repeat(31)},{residenceRegistered:'yes'},{residenceDate:'2026-10-01'},{residenceRegistered:true,residenceDate:'bad'}])
  await assert.rejects(call({...base,operationId:'X',...bad}),e=>e.code==='invalid-argument',JSON.stringify(bad));
 const r=await call({...base,nationalId:' 079200002222 ',residenceRegistered:true,residenceDate:'2026-10-03'});
 const t=db.store.get(`tenants/${r.tenantId}`);
 assert.equal(t.nationalId,'079200002222');assert.equal(t.residenceRegistered,true);assert.equal(t.residenceRegisteredLocalDate,'2026-10-03');
 // Without papers it is stored as before.
 const plain=await call({...base,operationId:'R2',fullName:'Other'});
 assert.equal('nationalId' in db.store.get(`tenants/${plain.tenantId}`),false);
});
