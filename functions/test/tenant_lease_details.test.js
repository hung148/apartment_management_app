// B3 (2026-10-01): lease form details — CCCD and tạm trú per person,
// co-tenants in the same form, staff in charge, payment period, deposit.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createTenantLeasesHandler}=require('../tenant_leases');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const member=(uid,role)=>({ownerId:uid,organizationId:'org',accessVersion:2,role,status:'active',buildingScope:'all',buildingIds:[]});
const seed=()=>({
  'organizations/org':{name:'Org',accessVersion:2,createdBy:'owner',paymentAccounts:[{id:'vcb',label:'Vietcombank 1234'}]},
  'memberships/owner_org':member('owner','owner'),
  'buildings/b1':{organizationId:'org',name:'Tower',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},
  'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'201',rentalMode:'monthly',roomPrice:5000000},
  'staffProfiles/s1':{organizationId:'org',displayName:'Lan',employmentStatus:'active'},
  'staffProfiles/old':{organizationId:'org',displayName:'Old',employmentStatus:'inactive'},
});
const setup=()=>{const db=fakeDb(seed());return {db,call:data=>createTenantLeasesHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'b1',roomId:'r1',...data}})};};
const base=async call=>{const p=(await call({action:'prepare'})).record;return {action:'create',operationId:'op1',roomRevision:p.roomRevision,timeZone:p.timeZone,currency:p.currency,fullName:'Le Van Chinh',phoneNumber:'0909',moveInDate:p.today,contractEndDate:'2027-10-01',rentMinor:5000000,backdateReason:''};};

test('new lease stores selected currency without relabeling the room price or existing leases',async()=>{
 const {db,call}=setup();
 db.store.get('organizations/org').displayCurrency='USD';
 const prepared=(await call({action:'prepare'})).record;
 assert.equal(prepared.currency,'USD');
 assert.equal(prepared.monthlyRentMinor,null);
 assert.deepEqual(prepared.roomRent,{amountMinor:5000000,currency:'VND'});
 const command={...await base(call),rentMinor:20000,depositMinor:12345,periodMonths:3,
  coTenants:[{fullName:'Roommate'}],surcharges:[{label:'Water',amountMinor:250,basis:'person',frequency:'month',kind:'water'}]};
 const result=await call(command),lease=db.store.get(`tenants/${result.tenantId}`);
 assert.equal(lease.currency,'USD');assert.equal(lease.monthlyRent,200);
 assert.equal(lease.monthlyRentMinor,20000);assert.equal(lease.periodRentMinor,60000);
 assert.equal(lease.deposit,123.45);assert.equal(lease.surcharges[0].amountMinor,250);
 assert.equal(db.store.get(`tenants/${result.coTenantIds[0]}`).currency,'USD');
 assert.equal(db.store.get('rooms/r1').roomPrice,5000000);
 db.store.get('organizations/org').displayCurrency='VND';
 assert.deepEqual(await call(command),result,'committed retry retains original currency');
 assert.equal(db.store.get(`tenants/${result.tenantId}`).currency,'USD');
 await assert.rejects(call({...command,operationId:'new-intent'}),e=>e.code==='aborted');
});

test('prepare offers staff, accounts and the room monthly price',async()=>{
  const {call}=setup();const p=(await call({action:'prepare'})).record;
  assert.deepEqual(p.staff.map(s=>s.displayName),['Lan']);assert.deepEqual(p.accounts,[{id:'vcb',label:'Vietcombank 1234'}]);assert.equal(p.monthlyRentMinor,5000000);
});

test('a lease with co-tenants, papers, period and deposit creates every person at once',async()=>{
  const {db,call}=setup();
  const r=await call({...await base(call),nationalId:'079200001111',residenceRegistered:true,residenceDate:'2026-09-01',
    coTenants:[{fullName:'Pham Thi Dung',phoneNumber:'',nationalId:'079200002222',residenceRegistered:false}],
    staffInChargeId:'s1',periodMonths:3,dueDay:5,depositMinor:5000000,depositMethod:'bankTransfer',depositAccountId:'vcb',depositNote:'CK 01/10'});
  const main=db.store.get(`tenants/${r.tenantId}`),co=db.store.get(`tenants/${r.coTenantIds[0]}`);
  assert.equal(main.nationalId,'079200001111');assert.equal(main.residenceRegistered,true);assert.equal(main.residenceRegisteredLocalDate,'2026-09-01');
  assert.equal(main.paymentPeriodMonths,3);assert.equal(main.paymentDueDay,5);assert.equal(main.periodRentMinor,15000000);
  assert.equal(main.deposit,5000000);assert.equal(main.depositAccountLabel,'Vietcombank 1234');assert.equal(main.staffInChargeId,'s1');
  assert.equal(co.mainTenantId,r.tenantId);assert.equal(co.isMainTenant,false);assert.equal(co.nationalId,'079200002222');assert.equal(co.residenceRegistered,false);
  assert.equal(co.moveInLocalDate,main.moveInLocalDate);
  for(const [k,v] of db.store)if(k.startsWith('teamActivity/'))assert.doesNotMatch(JSON.stringify(v),/0792000/);
});

test('bad details are refused before anything is written',async()=>{
  const {db,call}=setup();const b=await base(call);
  for(const extra of [{residenceDate:'2026-09-01'},{periodMonths:13},{dueDay:0},{depositMethod:'card'},{depositAccountId:'vcb',depositMethod:'cash'},
    {coTenants:[{fullName:''}]},{coTenants:[{fullName:'A',passport:'x'}]},{nationalId:'x'.repeat(31)}])
    await assert.rejects(call({...b,...extra}),e=>e.code==='invalid-argument');
  await assert.rejects(call({...b,staffInChargeId:'old'}),e=>e.message==='booking_staff_invalid');
  await assert.rejects(call({...b,depositMethod:'bankTransfer',depositAccountId:'gone'}),e=>e.message==='booking_account_invalid');
  assert.equal([...db.store.keys()].filter(k=>k.startsWith('tenants/')).length,0);
});

test('an old app version without details stores the lease as before',async()=>{
  const {db,call}=setup();const r=await call(await base(call));const t=db.store.get(`tenants/${r.tenantId}`);
  assert.equal('paymentPeriodMonths' in t,false);assert.equal('deposit' in t,false);assert.equal(r.coTenantIds,undefined);
});
