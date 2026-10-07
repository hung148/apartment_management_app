// The tenant page shows lease details with names, never internal IDs, and
// masks CCCD numbers without "Xem số CCCD" (2026-10-01).
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createTenantContactsHandler}=require('../tenant_contacts');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const member=(uid,role)=>({ownerId:uid,organizationId:'org',accessVersion:2,role,status:'active',buildingScope:'all',buildingIds:[]});
const seed=()=>({
  'organizations/org':{accessVersion:2},
  'memberships/owner_org':member('owner','owner'),
  'memberships/mgr_org':member('mgr','manager'),
  'buildings/b1':{organizationId:'org'},
  'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'101'},
  'staffProfiles/s1':{organizationId:'org',displayName:'Lan'},
  'tenants/main':{organizationId:'org',buildingId:'b1',roomId:'r1',fullName:'Le Van Chinh',isMainTenant:true,status:'active',nationalId:'079200003333',
    residenceRegistered:true,residenceRegisteredLocalDate:'2026-10-01',paymentPeriodMonths:3,paymentDueDay:5,periodRentMinor:15000000,
    depositMinor:5000000,depositMethod:'bankTransfer',depositAccountLabel:'VCB',staffInChargeId:'s1',moveInLocalDate:'2026-10-02',monthlyRentMinor:5000000},
  'tenants/co':{organizationId:'org',buildingId:'b1',roomId:'r1',fullName:'Pham Thi Dung',isMainTenant:false,mainTenantId:'main',status:'active',nationalId:'079200004444'},
});
const call=(db,uid,data)=>createTenantContactsHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid},data:{organizationId:'org',buildingId:'b1',...data}});
test('list names the main tenant and staff; owners see full CCCD',async()=>{
  const db=fakeDb(seed());const r=await call(db,'owner',{action:'list'});const by=Object.fromEntries(r.records.map(x=>[x.id,x]));
  assert.equal(by.co.mainTenantName,'Le Van Chinh');assert.equal(by.main.staffName,'Lan');assert.equal(by.main.nationalId,'079200003333');
  assert.equal(by.main.paymentPeriodMonths,3);assert.equal(by.main.depositAccountLabel,'VCB');
});
test('without the CCCD permission numbers are masked, also on the tenant page',async()=>{
  const db=fakeDb(seed());const r=await call(db,'mgr',{action:'read',tenantId:'co'});
  assert.equal(r.record.nationalId,'•••• 4444');assert.equal(r.record.mainTenantName,'Le Van Chinh');assert.equal(r.record.roomNumber,'101');assert.equal(r.record.canReadIds,false);
});
