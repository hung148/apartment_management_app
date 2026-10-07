// B2 (2026-10-01): per-night pricing, surcharges, co-guests, staff in charge,
// platform/channel, CCCD masking and payment receiving accounts.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createBookingWorkspaceHandler}=require('../booking_workspace');
const {createCalendarHandler}=require('../calendar');
const {bookingPrice,nightCount}=require('../booking_quote');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const member=(uid,role)=>({ownerId:uid,organizationId:'org',accessVersion:2,role,status:'active',buildingScope:'all',buildingIds:[]});
const seed=()=>({
  'organizations/org':{name:'Org',accessVersion:2,createdBy:'owner',paymentAccounts:[{id:'vcb',label:'Vietcombank 1234'}]},
  'memberships/owner_org':member('owner','owner'),
  'memberships/desk_org':member('desk','receptionist'),
  'memberships/helper_org':{...member('helper','staff'),staffId:'s2'},
  'buildings/b1':{organizationId:'org',name:'Tower',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},
  'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'P602',rentalMode:'both',hourlyPrice:100000,dailyPrice:500000},
  'staffProfiles/s1':{organizationId:'org',displayName:'Lan',employmentStatus:'active'},
  'staffProfiles/s2':{organizationId:'org',displayName:'Minh',employmentStatus:'active'},
  'staffProfiles/old':{organizationId:'org',displayName:'Former',employmentStatus:'inactive'},
  'staffProfiles/other':{organizationId:'elsewhere',displayName:'Other',employmentStatus:'active'},
});
const setup=()=>{
  const db=fakeDb(seed());
  const calendar=createCalendarHandler({db,Timestamp:Ts,FieldValue:{increment:n=>n},HttpsError:CodeError});
  const call=(uid,data)=>createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError,calendar})({auth:{uid},data:{organizationId:'org',buildingId:'b1',...data}});
  return {db,calendar,call};
};
const stay={roomId:'r1',startLocal:'2026-10-10 14:00',endLocal:'2026-10-12 12:00',occurrence:'first',pricingType:'nightly'};
const save=(extra={})=>({action:'save',bookingId:'k1',operationId:'op1',roomRevision:'0:0',guestName:'Anh',guestPhone:'0901',notes:'',depositMinor:200000,...stay,...extra});

test('nights follow property-local dates, not 24-hour blocks',()=>{
  const z='Asia/Ho_Chi_Minh',at=s=>Date.parse(s);
  assert.equal(nightCount(at('2026-10-10T07:00:00Z'),at('2026-10-12T05:00:00Z'),z),2);
  assert.equal(nightCount(at('2026-10-10T16:30:00Z'),at('2026-10-10T18:00:00Z'),z),1);// 23:30 → 01:00 next day
  const r={dailyPrice:500000};
  assert.equal(bookingPrice(r,at('2026-10-10T07:00:00Z'),at('2026-10-12T05:00:00Z'),'nightly',{zone:z}).totalMinor,1000000);
  assert.equal(bookingPrice(r,at('2026-10-10T07:00:00Z'),at('2026-10-12T05:00:00Z'),'nightly',{zone:z,nightPricesMinor:[400000,700000]}).totalMinor,1100000);
  assert.throws(()=>bookingPrice(r,at('2026-10-10T07:00:00Z'),at('2026-10-12T05:00:00Z'),'nightly',{zone:z,nightPricesMinor:[400000]}),/booking_night_prices_invalid/);
  assert.throws(()=>bookingPrice(r,at('2026-10-10T01:00:00Z'),at('2026-10-10T05:00:00Z'),'nightly',{zone:z}),/booking_invalid_dates/);
});

test('quote adds surcharges to the nightly price; custom night prices need price authority',async()=>{
  const {call}=setup();
  const q=(await call('desk',{action:'quote',...stay,surcharges:[{label:'Extra bed',amountMinor:150000}]})).record;
  assert.deepEqual([q.nights,q.baseMinor,q.surchargesMinor,q.totalMinor,q.pricingType],[2,1000000,150000,1150000,'nightly']);
  await assert.rejects(call('desk',{action:'quote',...stay,nightPricesMinor:[1,2]}),e=>e.code==='permission-denied');
  const owner=(await call('owner',{action:'quote',...stay,nightPricesMinor:[450000,550000]})).record;
  assert.equal(owner.totalMinor,1000000);assert.deepEqual(owner.nightPricesMinor,[450000,550000]);
  await assert.rejects(call('desk',{action:'quote',...stay,surcharges:[{label:'',amountMinor:5}]}),e=>e.message==='booking_invalid_surcharge');
});

test('a receptionist saves a nightly booking with co-guests, staff and source, and sees CCCD masked',async()=>{
  const {db,call}=setup();
  await call('desk',save({guestIdNumber:'079200001234',guests:[{id:'g1',name:'Binh',idNumber:'079200005678'}],numberOfGuests:2,
    staffInChargeId:'s1',platform:'agoda',contactChannel:'zalo',depositNote:'Chuyển khoản 9/10',surcharges:[{label:'Extra bed',amountMinor:150000}]}));
  const stored=db.store.get('bookings/k1');
  assert.equal(stored.totalPrice,1150000);assert.equal(stored.pricingType,'nightly');assert.deepEqual(stored.nightPrices,[500000,500000]);
  assert.equal(stored.guests[0].idNumber,'079200005678');assert.equal(stored.staffInChargeId,'s1');assert.equal(stored.platform,'agoda');
  assert.deepEqual(stored.surcharges,[{label:'Extra bed',amount:150000}]);
  const seen=(await call('desk',{action:'read',bookingId:'k1'})).record;
  assert.equal(seen.guestIdNumber,'•••• 1234');assert.equal(seen.guests[0].idNumber,'•••• 5678');assert.equal(seen.canReadGuestIds,false);
  assert.equal(seen.staffName,'Lan');assert.equal(seen.contactChannel,'zalo');assert.equal(seen.depositNote,'Chuyển khoản 9/10');
  const full=(await call('owner',{action:'read',bookingId:'k1'})).record;
  assert.equal(full.guests[0].idNumber,'079200005678');assert.equal(full.canReadGuestIds,true);
  // No CCCD in activity history.
  for(const [k,v] of db.store)if(k.startsWith('teamActivity/'))assert.doesNotMatch(JSON.stringify(v),/0792000/);
});

test('editing without the CCCD numbers keeps them; left-out details and night prices are kept',async()=>{
  const {db,call}=setup();
  await call('owner',save({guestIdNumber:'079200001234',guests:[{id:'g1',name:'Binh',idNumber:'079200005678'}],nightPricesMinor:[450000,550000],surcharges:[{label:'Bed',amountMinor:100000}],platform:'airbnb'}));
  await call('desk',save({operationId:'op2',revision:'0:0',guestName:'Anh Tuan',guests:[{id:'g1',name:'Binh'},{id:'g2',name:'Chi'}]}));
  const b=db.store.get('bookings/k1');
  assert.equal(b.guestName,'Anh Tuan');assert.equal(b.guestIdNumber,'079200001234');
  assert.deepEqual(b.guests,[{id:'g1',name:'Binh',idNumber:'079200005678'},{id:'g2',name:'Chi',idNumber:null}]);
  assert.deepEqual(b.nightPrices,[450000,550000]);assert.equal(b.totalPrice,1100000);assert.equal(b.platform,'airbnb');
  // A changed stay re-prices at the room rate when the kept list no longer fits.
  await call('desk',save({operationId:'op3',revision:'0:0',endLocal:'2026-10-13 12:00'}));
  assert.deepEqual(db.store.get('bookings/k1').nightPrices,[500000,500000,500000]);assert.equal(db.store.get('bookings/k1').totalPrice,1600000);
});

test('staff in charge must be an active staff profile of this organization and gives "own" access',async()=>{
  const {db,call}=setup();
  for(const s of ['old','other','nobody'])await assert.rejects(call('owner',save({operationId:'x'+s,staffInChargeId:s})),e=>e.message==='booking_staff_invalid');
  await call('owner',save({staffInChargeId:'s2'}));
  // The helper's role manages only their own bookings: being in charge counts.
  await call('helper',save({operationId:'h1',revision:'0:0',notes:'Late arrival'}));
  assert.equal(db.store.get('bookings/k1').notes,'Late arrival');
});

test('the public calendar callable cannot write surcharges, night prices or invalid details',async()=>{
  const {db,calendar}=setup();
  const booking={organizationId:'org',roomId:'r1',guestName:'X',pricingType:'hourly',startTime:{__timestamp:Date.parse('2026-10-20T03:00:00Z')},endTime:{__timestamp:Date.parse('2026-10-20T05:00:00Z')}};
  await assert.rejects(calendar({action:'create',bookingId:'p1',serverPricing:true,booking:{...booking,surcharges:[{label:'a',amount:1}]}},{auth:{uid:'owner'}}),e=>e.message==='booking_invalid_request');
  await assert.rejects(calendar({action:'create',bookingId:'p2',serverPricing:true,booking:{...booking,platform:'myspace'}},{auth:{uid:'owner'}}),e=>e.message==='booking_invalid_request');
  // A quote inside the request is ignored: only the bookings workspace passes one, outside the request.
  await calendar({action:'create',bookingId:'p3',serverPricing:true,serverQuote:{total:1,pricingType:'hourly'},booking},{auth:{uid:'desk'}});
  assert.equal(db.store.get('bookings/p3').totalPrice,200000);
});

test('payments record the receiving account; unknown accounts are refused',async()=>{
  const {db,call}=setup();
  await call('owner',save());
  await assert.rejects(call('desk',{action:'command',bookingId:'k1',operationId:'p0',revision:'0:0',command:'deposit',amountMinor:100000,paymentMethod:'bankTransfer',reason:'Cọc',accountId:'nope'}),e=>e.message==='booking_account_invalid');
  await call('desk',{action:'command',bookingId:'k1',operationId:'p1',revision:'0:0',command:'deposit',amountMinor:100000,paymentMethod:'bankTransfer',reason:'Cọc',accountId:'vcb'});
  await call('desk',{action:'command',bookingId:'k1',operationId:'p2',revision:'0:0',command:'payment',amountMinor:300000,paymentMethod:'cash',reason:'Trả trước',accountId:'cash'});
  const payments=[...db.store].filter(([k])=>k.startsWith('payments/')).map(([,v])=>v);
  assert.deepEqual(payments.map(p=>[p.receivedAccountId,p.receivedAccountLabel]).sort(),[['cash',''],['vcb','Vietcombank 1234']]);
});

test('the booking form gets staff, accounts and the CCCD permission',async()=>{
  const {call}=setup();
  const desk=await call('desk',{action:'rooms'});
  assert.deepEqual(desk.staff.map(s=>s.displayName),['Lan','Minh']);
  assert.deepEqual(desk.accounts,[{id:'vcb',label:'Vietcombank 1234'}]);
  assert.equal(desk.canReadGuestIds,false);assert.equal((await call('owner',{action:'rooms'})).canReadGuestIds,true);
});

test('a booking priced per hour keeps its own hourly price; an edit without one keeps it',async()=>{
  const {db,call}=setup();
  const hourly={pricingType:'hourly',startLocal:'2026-10-10 14:00',endLocal:'2026-10-10 17:00'};
  await call('owner',save({...hourly,hourlyPriceMinor:80000}));
  const b=db.store.get('bookings/k1');
  assert.deepEqual([b.totalPrice,b.hourlyPrice,b.pricingType],[240000,80000,'hourly']);
  const read=await call('owner',{action:'read',bookingId:'k1'});
  // Longer stay, no hourly price sent (an older app or a person without "Đổi giá"): 80,000 still applies.
  await call('owner',save({...hourly,endLocal:'2026-10-10 18:00',operationId:'op2',revision:read.record.revision}));
  assert.deepEqual([db.store.get('bookings/k1').totalPrice,db.store.get('bookings/k1').hourlyPrice],[320000,80000]);
});
