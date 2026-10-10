// C1–C3 calendar read (CALENDAR.md): bars, payment dots, privacy, windows.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createCalendarViewHandler,bookingPay,leasePay}=require('../calendar_view');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const at=s=>new Ts(Date.parse(s));
const owner={ownerId:'owner',organizationId:'org',accessVersion:2,role:'owner',status:'active',buildingScope:'all',buildingIds:[]};
const seed=()=>({
 'organizations/org':{accessVersion:2,createdBy:'owner'},
 'memberships/owner_org':owner,
 'buildings/b1':{organizationId:'org',name:'Toa A',timeZone:'Asia/Ho_Chi_Minh'},
 'buildings/b2':{organizationId:'org',name:'Toa B',timeZone:'Asia/Ho_Chi_Minh'},
 'buildings/other':{organizationId:'other',name:'Not ours',timeZone:'Asia/Ho_Chi_Minh'},
 'rooms/r101':{organizationId:'org',buildingId:'b1',roomNumber:'101',rentalMode:'both'},
 'rooms/r102':{organizationId:'org',buildingId:'b1',roomNumber:'102',rentalMode:'hourly',openProblemBlocks:['p1']},
 'rooms/r10':{organizationId:'org',buildingId:'b1',roomNumber:'10',rentalMode:'monthly'},
 'rooms/r201':{organizationId:'org',buildingId:'b2',roomNumber:'201',rentalMode:'monthly'},
 // 2 nights, fully paid, Airbnb, checked in. Local 2026-10-01 14:00 → 10-03 12:00 (+07:00).
 'bookings/k1':{organizationId:'org',buildingId:'b1',roomId:'r101',guestName:'Nguyen Van An',guestPhone:'0901',status:'checkedIn',platform:'airbnb',contactChannel:'zalo',
  startTime:at('2026-10-01T07:00:00Z'),endTime:at('2026-10-03T05:00:00Z'),totalPrice:1000000,paidAmount:1000000,depositPaidAmount:0,currency:'VND',createdBy:'owner'},
 // Deposit only, not checked in.
 'bookings/k2':{organizationId:'org',buildingId:'b1',roomId:'r102',guestName:'Tran Thi Binh',status:'confirmed',platform:'direct',
  startTime:at('2026-10-05T07:00:00Z'),endTime:at('2026-10-07T05:00:00Z'),totalPrice:800000,paidAmount:0,depositPaidAmount:200000,depositRefundedAmount:0,currency:'VND',createdBy:'someoneElse'},
 // Cancelled: never on the calendar.
 'bookings/k3':{organizationId:'org',buildingId:'b1',roomId:'r101',guestName:'Cancelled',status:'cancelled',
  startTime:at('2026-10-10T07:00:00Z'),endTime:at('2026-10-11T05:00:00Z'),totalPrice:1,paidAmount:0,currency:'VND'},
 // Outside the window.
 'bookings/k4':{organizationId:'org',buildingId:'b1',roomId:'r101',guestName:'November',status:'pending',
  startTime:at('2026-11-10T07:00:00Z'),endTime:at('2026-11-11T05:00:00Z'),totalPrice:1,paidAmount:0,currency:'VND'},
 // Long-term lease since September, monthly, rent paid until 2026-10-05, roommate.
 'tenants/lease1':{organizationId:'org',buildingId:'b1',roomId:'r10',fullName:'Le Van Chinh',phoneNumber:'0902',status:'active',isMainTenant:true,
  moveInDate:at('2026-09-04T17:00:00Z'),moveInLocalDate:'2026-09-05',moveOutDate:null,contractEndLocalDate:'2027-09-05',paymentPeriodMonths:1,currency:'VND'},
 'tenants/mate1':{organizationId:'org',buildingId:'b1',roomId:'r10',fullName:'Pham Thi Dung',status:'active',isMainTenant:false,mainTenantId:'lease1',moveOutDate:null},
 'payments/i1':{organizationId:'org',buildingId:'b1',tenantId:'lease1',invoiceKind:'tenantRent',status:'paid',billingStartLocalDate:'2026-09-05',billingEndLocalDate:'2026-10-05'},
 'payments/i2':{organizationId:'org',buildingId:'b1',tenantId:'lease1',invoiceKind:'tenantRent',status:'cancelled',billingStartLocalDate:'2026-10-05',billingEndLocalDate:'2026-11-05'},
 // Open problem on 102.
 'technicalProblems/p1':{organizationId:'org',buildingId:'b1',roomId:'r102',title:'Den hong',status:'open',blocksRoom:true},
 'technicalProblems/p2':{organizationId:'org',buildingId:'b1',roomId:'r101',title:'Fixed',status:'fixed',blocksRoom:false},
});
const call=(store,data={},uid='owner')=>createCalendarViewHandler({db:store,Timestamp:Ts,HttpsError:CodeError})({auth:uid?{uid}:undefined,data:{organizationId:'org',from:'2026-10-01',to:'2026-11-01',...data}});
const code=async(p,c)=>assert.equal((await p.then(()=>null,e=>e)).code,c);
const bar=(r,i)=>r.properties.flatMap(p=>p.bars).find(b=>b.id.startsWith(i));

test('multiple buildings load concurrently with a bounded batch and stable order',async()=>{
 const data=seed();
 for(let i=3;i<=9;i++)data[`buildings/b${i}`]={organizationId:'org',name:`Toa ${i}`,timeZone:'Asia/Ho_Chi_Minh'};
 const db=fakeDb(data),collection=db.collection;
 let active=0,peak=0,firstBatch=0;
 const wrap=q=>({
  where:(...args)=>wrap(q.where(...args)),
  get:async()=>{
   active++;peak=Math.max(peak,active);
   // Hold each room read until the next event-loop turn. This detects serial
   // building loading without relying on wall-clock performance thresholds.
   await new Promise(resolve=>setImmediate(()=>{if(!firstBatch)firstBatch=active;resolve();}));
   try{return await q.get();}finally{active--;}
  },
 });
 db.collection=name=>name==='rooms'?wrap(collection(name)):collection(name);
 const result=await call(db);
 assert.equal(firstBatch,4,'four buildings must start before the first room read completes');
 assert.equal(peak,4,'do not fan out all buildings at once');
 assert.deepEqual(result,await call(fakeDb(data)),'parallel completion must preserve the complete calendar projection and order');
});

test('owner sees every property, rooms in number order, and the month\'s bars',async()=>{
 Ts.clock=Date.parse('2026-10-02T03:00:00Z');
 const r=await call(fakeDb(seed()));
 assert.deepEqual(r.properties.map(p=>p.name),['Toa A','Toa B']);
 const a=r.properties[0];
 assert.equal(a.today,'2026-10-02');
 // 2026-10-04: the property's own clock, for the calendar's "now" line.
 assert.match(a.now,/^2026-10-02 \d{2}:\d{2}$/);
 assert.deepEqual(a.rooms.map(x=>x.roomNumber),['10','101','102']);
 assert.deepEqual(a.rooms.find(x=>x.id==='r102'),{id:'r102',roomNumber:'102',shortStay:true,monthly:true,blocked:true,problems:[{id:'p1',title:'Den hong',blocksRoom:true}],needsCleaning:false});
 assert.deepEqual(a.rooms.find(x=>x.id==='r101').problems,[]);
 assert.deepEqual(a.bars.map(b=>b.id).sort(),['booking:k1','booking:k2','lease:lease1:r10:'+Date.parse('2026-09-04T17:00:00Z')].sort());
 assert.equal(a.canCreateBookings,true);assert.equal(a.canLease,true);
});

test('booking bar: local times, platform, payment dot and paid share',async()=>{
 Ts.clock=Date.parse('2026-10-02T03:00:00Z');
 const r=await call(fakeDb(seed()));
 const k1=bar(r,'booking:k1');
 assert.equal(k1.start,'2026-10-01 14:00');assert.equal(k1.end,'2026-10-03 12:00');
 assert.equal(k1.kind,'short');assert.equal(k1.status,'staying');assert.equal(k1.pay,'paid');assert.equal(k1.paidFraction,1);
 assert.equal(k1.platform,'airbnb');assert.equal(k1.channel,'zalo');assert.equal(k1.phone,true);assert.equal(k1.canOpen,true);assert.equal(k1.recordId,'k1');
 const k2=bar(r,'booking:k2');
 assert.equal(k2.kind,'short');assert.equal(k2.deposit,true);assert.equal(k1.deposit,false);assert.equal(k2.pay,'deposit');assert.equal(k2.platform,null);assert.equal(k2.status,'upcoming');
 assert.equal(k2.problem,true,'open problem on the room');
});

test('lease bar: open-ended with planned end, paid until, roommates',async()=>{
 Ts.clock=Date.parse('2026-10-02T03:00:00Z');
 const r=await call(fakeDb(seed()));
 const l=bar(r,'lease:lease1');
 assert.equal(l.start,'2026-09-05 12:00');assert.equal(l.end,null);assert.equal(l.plannedEnd,'2027-09-05');
 assert.equal(l.kind,'long');assert.equal(l.status,'staying');assert.equal(l.roommates,1);
 assert.equal(l.pay,'paid');assert.equal(l.paidUntil,'2026-10-05 00:00');
 // After the paid period the dot turns red.
 Ts.clock=Date.parse('2026-10-06T03:00:00Z');
 assert.equal(bar(await call(fakeDb(seed())),'lease:lease1').pay,'due');
});

test('unpaid rent invoice that has started makes the lease red',async()=>{
 Ts.clock=Date.parse('2026-10-02T03:00:00Z');
 const s=seed();s['payments/i3']={organizationId:'org',buildingId:'b1',tenantId:'lease1',invoiceKind:'period',calculation:{includeRent:true},status:'partial',billingStartLocalDate:'2026-10-01',billingEndLocalDate:'2026-11-01'};
 assert.equal(bar(await call(fakeDb(s)),'lease:lease1').pay,'due');
});

test('moved-out lease ends at its move-out day; a room move shows the old room too',async()=>{
 Ts.clock=Date.parse('2026-10-20T03:00:00Z');
 const s=seed();
 Object.assign(s['tenants/lease1'],{status:'moveOut',moveOutDate:at('2026-10-14T17:00:00Z'),settlementId:'set1'});
 s['tenants/lease2']={organizationId:'org',buildingId:'b2',roomId:'r201',fullName:'Moved Person',status:'active',isMainTenant:true,moveInDate:at('2026-08-31T17:00:00Z'),occupancyStartDate:at('2026-10-09T17:00:00Z')};
 s['leaseOccupancy/h1']={organizationId:'org',tenantId:'lease2',buildingId:'b1',roomId:'r101',start:at('2026-08-31T17:00:00Z'),end:at('2026-10-09T17:00:00Z'),isMainTenant:true};
 const r=await call(fakeDb(s));
 const l1=bar(r,'lease:lease1');
 assert.equal(l1.end,'2026-10-15 12:00');assert.equal(l1.status,'out');assert.equal(l1.pay,'paid');
 const old=r.properties[0].bars.find(b=>b.id.startsWith('lease:lease2'));
 assert.equal(old.roomId,'r101');assert.equal(old.name,'Moved Person');assert.equal(old.status,'out');assert.equal(old.end,'2026-10-10 12:00');
 const now=r.properties[1].bars.find(b=>b.id.startsWith('lease:lease2'));
 assert.equal(now.start,'2026-10-10 12:00');assert.equal(now.status,'staying');
});

test('staff limited to their own bookings and no lease access see other stays anonymously',async()=>{
 Ts.clock=Date.parse('2026-10-02T03:00:00Z');
 const s=seed();
 s['memberships/rec_org']={ownerId:'rec',organizationId:'org',accessVersion:2,role:'custom1',roleGrants:{readBookings:'own',createBookings:'managed'},status:'active',buildingScope:'selected',buildingIds:['b1']};
 s['bookings/k2'].createdBy='rec';
 const r=await call(fakeDb(s),{},'rec');
 assert.deepEqual(r.properties.map(p=>p.id),['b1']);
 const k1=bar(r,'booking:k1');
 assert.deepEqual([k1.anonymous,k1.name,k1.canOpen,k1.pay,k1.platform,k1.recordId],[true,'',false,undefined,undefined,undefined]);
 const k2=bar(r,'booking:k2');
 assert.equal(k2.name,'Tran Thi Binh');assert.equal(k2.canOpen,true);
 const l=bar(r,'lease:lease1');
 assert.deepEqual([l.anonymous,l.name,l.canOpen,l.pay,l.paidUntil],[true,'',false,undefined,undefined]);
 assert.equal(r.properties[0].canLease,false);
});

test('a member with nothing to do on the calendar gets no property',async()=>{
 const s=seed();
 s['memberships/none_org']={ownerId:'none',organizationId:'org',accessVersion:2,role:'custom1',roleGrants:{readOwnActivity:'own'},status:'active',buildingScope:'all',buildingIds:[]};
 assert.deepEqual((await call(fakeDb(s),{},'none')).properties,[]);
});

// 2026-10-05 (Tom): cleaning on the calendar.
const cleaningSeed=()=>{
 const s=seed();
 s['memberships/maid_org']={ownerId:'maid',organizationId:'org',accessVersion:2,role:'housekeeper',status:'active',buildingScope:'all',buildingIds:[]};
 s['staffProfiles/maid']={organizationId:'org',displayName:'Chi Lan'};
 // k1 checked out on 10-03 at 12:05 (local); a cleaning planned 13:00–14:00, started 13:10.
 s['bookings/k1'].status='checkedOut';s['bookings/k1'].checkedOutAt=at('2026-10-03T05:05:00Z');
 s['housekeepingTasks/t1']={organizationId:'org',buildingId:'b1',roomId:'r101',assigneeId:'maid',title:'Don phong',status:'inProgress',
  plannedStart:'2026-10-03 13:00',plannedEnd:'2026-10-03 14:00',startedAt:at('2026-10-03T06:10:00Z'),createdAt:at('2026-10-03T05:00:00Z')};
 // Someone else's finished cleaning of 102, no plan: started 09:00, done 09:40.
 // maid2 has no staff profile: the bar uses the member's name.
 s['memberships/maid2_org']={...s['memberships/maid_org'],ownerId:'maid2',displayName:'Chi Hoa'};
 s['housekeepingTasks/t2']={organizationId:'org',buildingId:'b1',roomId:'r102',assigneeId:'maid2',title:'Lau kinh',status:'completed',
  startedAt:at('2026-10-02T02:00:00Z'),completedAt:at('2026-10-02T02:40:00Z'),createdAt:at('2026-10-02T01:00:00Z')};
 return s;
};

test('cleaning bars: planned window, real work time, and rooms that need cleaning',async()=>{
 Ts.clock=Date.parse('2026-10-03T06:30:00Z'); // 13:30 local
 const r=await call(fakeDb(cleaningSeed()));
 const a=r.properties[0];
 const t1=bar(r,'cleaning:t1');
 assert.deepEqual([t1.type,t1.kind,t1.roomId,t1.start,t1.end,t1.status,t1.taskStatus,t1.name,t1.title],
  ['cleaning','cleaning','r101','2026-10-03 13:00','2026-10-03 14:00','inProgress','inProgress','Chi Lan','Don phong']);
 assert.deepEqual([t1.plannedStart,t1.plannedEnd,t1.actualStart,t1.actualEnd,t1.paidUntil],
  ['2026-10-03 13:00','2026-10-03 14:00','2026-10-03 13:10',null,'2026-10-03 13:30']);
 const t2=bar(r,'cleaning:t2');
 assert.deepEqual([t2.start,t2.end,t2.status,t2.pay,t2.plannedStart,t2.name],['2026-10-02 09:00','2026-10-02 09:40','completed','paid',null,'Chi Hoa']);
 // 101: a guest left at 12:05 and its cleaning is not done yet.
 assert.equal(a.rooms.find(x=>x.id==='r101').needsCleaning,true);
 assert.equal(a.rooms.find(x=>x.id==='r102').needsCleaning,false);
 assert.equal(a.canAssignCleaning,true);assert.equal(a.cleaningOnly,false);
 // Once the cleaning is done after the check-out, the room is clean.
 const s=cleaningSeed();s['housekeepingTasks/t1'].status='completed';s['housekeepingTasks/t1'].completedAt=at('2026-10-03T06:20:00Z');
 const done=await call(fakeDb(s));
 assert.equal(done.properties[0].rooms.find(x=>x.id==='r101').needsCleaning,false);
 // Finished: the bar shrinks to the real work time (13:10 → 13:20), the plan stays in the details.
 const t1done=bar(done,'cleaning:t1');
 assert.deepEqual([t1done.start,t1done.end,t1done.status,t1done.plannedEnd],['2026-10-03 13:10','2026-10-03 13:20','completed','2026-10-03 14:00']);
 // Done without Bắt đầu: from the planned start up to when it was done…
 const s2=cleaningSeed();Object.assign(s2['housekeepingTasks/t1'],{status:'completed',startedAt:undefined,completedAt:at('2026-10-03T06:40:00Z')});
 assert.deepEqual((({start,end})=>[start,end])(bar(await call(fakeDb(s2)),'cleaning:t1')),['2026-10-03 13:00','2026-10-03 13:40']);
 // …or a 30 min block when it was done before the plan began.
 const s3=cleaningSeed();Object.assign(s3['housekeepingTasks/t1'],{status:'completed',startedAt:undefined,completedAt:at('2026-10-03T05:50:00Z')});
 assert.deepEqual((({start,end})=>[start,end])(bar(await call(fakeDb(s3)),'cleaning:t1')),['2026-10-03 12:20','2026-10-03 12:50']);
});

test('a cleaner sees the calendar with only their own cleaning, no guests or money',async()=>{
 Ts.clock=Date.parse('2026-10-03T06:30:00Z');
 const r=await call(fakeDb(cleaningSeed()),{},'maid');
 assert.deepEqual(r.properties.map(p=>p.id),['b1','b2']);
 const a=r.properties[0];
 assert.equal(a.cleaningOnly,true);assert.equal(a.canCreateBookings,false);assert.equal(a.canLease,false);assert.equal(a.canAssignCleaning,false);
 assert.deepEqual(a.bars.map(b=>b.id),['cleaning:t1']);
 assert.equal(a.bars[0].canOpen,true);
 assert.equal(a.rooms.find(x=>x.id==='r101').needsCleaning,true);
});

test('refuses: signed out, other organization, suspended, bad dates, too many days, extra keys',async()=>{
 await code(call(fakeDb(seed()),{},null),'unauthenticated');
 await code(call(fakeDb(seed()),{organizationId:'other'}),'permission-denied');
 const s=seed();s['memberships/owner_org']={...owner,status:'suspended'};
 await code(call(fakeDb(s)),'permission-denied');
 const v1=seed();v1['organizations/org']={accessVersion:1};
 await code(call(fakeDb(v1)),'permission-denied');
 await code(call(fakeDb(seed()),{from:'2026-10-32'}),'invalid-argument');
 await code(call(fakeDb(seed()),{to:'2026-10-01'}),'invalid-argument');
 await code(call(fakeDb(seed()),{to:'2027-02-01'}),'invalid-argument');
 await code(call(fakeDb(seed()),{extra:1}),'invalid-argument');
});

test('a property without a time zone is listed so it can be fixed, with no bars',async()=>{
 const s=seed();delete s['buildings/b2'].timeZone;
 const p=(await call(fakeDb(s))).properties.find(x=>x.id==='b2');
 assert.equal(p.needsTimeZone,true);assert.deepEqual(p.bars,[]);
});

test('payment rules',()=>{
 assert.deepEqual(bookingPay({totalPrice:100,paidAmount:40}),{pay:'due',fraction:0.4});
 assert.equal(bookingPay({totalPrice:100,paidAmount:0,depositPaidAmount:50,depositRefundedAmount:50}).pay,'due');
 // Deposit taken with the booking (2026-10-04): in paidAmount; only the deposit paid reads "deposit".
 assert.deepEqual(bookingPay({totalPrice:100,paidAmount:30,depositPayment:{amount:30}}),{pay:'deposit',fraction:0.3});
 assert.equal(bookingPay({totalPrice:100,paidAmount:50,depositPayment:{amount:30}}).pay,'due');
 assert.equal(bookingPay({totalPrice:100,paidAmount:100,depositPayment:{amount:100}}).pay,'paid');
 assert.equal(bookingPay({totalPrice:0,paidAmount:0}).pay,'paid');
 assert.equal(leasePay({depositMinor:5},[],'2026-10-01','upcoming').pay,'deposit');
 assert.equal(leasePay({},[],'2026-10-01','upcoming').pay,'due');
 assert.equal(leasePay({},[],'2026-10-01','out').pay,'due');
});
