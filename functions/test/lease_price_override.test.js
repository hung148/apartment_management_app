// Fix 5 (2026-10-09, Tom): a lease's amount per period can differ from rent × months when it is negotiated. It needs
// "Đổi giá" and a reason; the lease keeps the amount, the calculated one, the reason and who changed it.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createTenantLeasesHandler}=require('../tenant_leases');
const {createTenantContactsHandler}=require('../tenant_contacts');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const member=(uid,role,extra={})=>({ownerId:uid,organizationId:'org',accessVersion:2,role,status:'active',buildingScope:'all',buildingIds:[],...extra});
const seed=()=>({
  'organizations/org':{name:'Org',accessVersion:2,createdBy:'owner'},
  'memberships/owner_org':member('owner','owner',{displayName:'Chị Hà'}),
  'memberships/man_org':member('man','manager',{permissionOverrides:{overridePrices:false},email:'man@example.com'}),
  'buildings/b1':{organizationId:'org',name:'Tower',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},
  'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'201',rentalMode:'monthly',roomPrice:5000000},
});
const setup=()=>{const db=fakeDb(seed());const as=uid=>data=>createTenantLeasesHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid},data:{organizationId:'org',buildingId:'b1',roomId:'r1',...data}});return {db,owner:as('owner'),man:as('man')};};
const base=async call=>{const p=(await call({action:'prepare'})).record;return {action:'create',operationId:'op1',roomRevision:p.roomRevision,timeZone:p.timeZone,currency:p.currency,fullName:'Le Van Chinh',phoneNumber:'0909',moveInDate:p.today,contractEndDate:'2027-10-01',rentMinor:5000000,backdateReason:'',periodMonths:3};};

test('an own amount per period needs "Đổi giá" and a reason, and keeps the calculated amount and who',async()=>{
  const {db,owner,man}=setup();
  const cmd=await base(owner);
  // Without "Đổi giá", without a reason or with a blank one: refused, nothing saved.
  await assert.rejects(man({...cmd,periodAmountMinor:14000000,periodAmountReason:'Trả trước 3 tháng'}),e=>e.code==='permission-denied'&&e.message==='lease_price_authority');
  for(const reason of [undefined,'','   '])await assert.rejects(owner({...cmd,periodAmountMinor:14000000,...(reason===undefined?{}:{periodAmountReason:reason})}),e=>e.code==='permission-denied',String(reason));
  for(const reason of [5,'x'.repeat(1001)])await assert.rejects(owner({...cmd,periodAmountMinor:14000000,periodAmountReason:reason}),e=>e.code==='invalid-argument');
  assert.equal([...db.store.keys()].filter(k=>k.startsWith('tenants/')).length,0);
  const {tenantId}=await owner({...cmd,periodAmountMinor:14000000,periodAmountReason:'  Trả trước 3 tháng  '});
  const lease=db.store.get(`tenants/${tenantId}`);
  assert.equal(lease.periodRentMinor,14000000);assert.equal(lease.monthlyRentMinor,5000000);
  const {at,...o}=lease.periodRentOverride;
  assert.deepEqual(o,{totalMinor:14000000,calculatedTotalMinor:15000000,reason:'Trả trước 3 tháng',byId:'owner',byName:'Chị Hà'});
  assert.equal(typeof at.toMillis,'function');
  const read=(await createTenantContactsHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'b1',action:'read',tenantId}})).record;
  assert.deepEqual([read.periodRentMinor,read.periodRentOverride.totalMinor,read.periodRentOverride.calculatedTotalMinor,read.periodRentOverride.reason,read.periodRentOverride.byName],[14000000,14000000,15000000,'Trả trước 3 tháng','Chị Hà']);
  assert.equal(typeof read.periodRentOverride.at,'string');
});

test('rent × months needs no reason or "Đổi giá"; nothing is recorded as changed',async()=>{
  const {db,man}=setup();
  const cmd=await base(man);
  const same=await man({...cmd,periodAmountMinor:15000000});
  assert.equal(db.store.get(`tenants/${same.tenantId}`).periodRentOverride,undefined);
  assert.equal(db.store.get(`tenants/${same.tenantId}`).periodRentMinor,15000000);
});

test('without an own amount the lease is as before',async()=>{
  const {db,man}=setup();
  const {tenantId}=await man({...await base(man),periodAmountReason:'ignored'});
  const lease=db.store.get(`tenants/${tenantId}`);
  assert.equal(lease.periodRentMinor,15000000);assert.equal(lease.periodRentOverride,undefined);
});
