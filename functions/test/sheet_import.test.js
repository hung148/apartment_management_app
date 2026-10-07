// Sheet import (2026-10-05): made-up rows in the old app's format only.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createSheetImportHandler,stamp,money,phone,pricing,source}=require('../sheet_import');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const owner={ownerId:'owner',organizationId:'org',accessVersion:2,role:'owner',status:'active',buildingScope:'all',buildingIds:[]};
const seed=()=>({
 'organizations/org':{accessVersion:2,createdBy:'owner'},
 'memberships/owner_org':owner,
 'memberships/maid_org':{ownerId:'maid',organizationId:'org',accessVersion:2,role:'manager',status:'active',buildingScope:'all',buildingIds:[]},
 'staffProfiles/old1':{organizationId:'org',code:'S01',displayName:'Đã có'},
});
const tab=(headers,rows)=>({headers,rows});
const pay=list=>JSON.stringify(list);
const sheets=()=>({
 'Phòng':tab(['ID','Tên cơ sở','Giá thuê cơ sở','Mã phòng Json','Ghi chú'],[
  ['B1','Nhà Mẫu',30000000,JSON.stringify([{maPhong:'P101',trangThai:'Đã dọn',ghiChu:''},{maPhong:'P102',trangThai:'Thuê dài hạn',ghiChu:'cửa sổ'},{maPhong:'P103',trangThai:'Thuê dài hạn',ghiChu:''}]),'ghi chú tòa'],
  [null,null,null,null,null],
 ]),
 'Đặt phòng':tab(['ID','Tên cơ sở','Mã phòng','Ngày tạo','Tên khách hàng','Số điện thoại','Nguồn','Nhân viên','Hình thức phòng','Ngày giờ checkin','Ngày giờ checkout','Đơn giá','Phụ phí','Tổng doanh thu','Ghi chú','Thanh toán Json','Số tiền còn lại'],[
  // Past 2N1D stay, deposit + rest, phone lost its 0.
  ['K1','Nhà Mẫu','P101','2026-09-01 10:00:00','Khách A',912345678,'Booking','Thu','2N1D','2026-09-10 14:00:00','2026-09-11 12:00:00',500000,50000,550000,'','' +pay([{ngayThanhToan:'2026-09-05',soTien:200000,ghiChu:'cọc'},{ngayThanhToan:'2026-09-11',soTien:350000,ghiChu:''}]),0],
  // Overlaps K1, no phone, paid too much, by hour.
  ['K2','Nhà Mẫu','P101',null,'Khách B','ko có','Chính chủ','Ai Đó','Thuê giờ','2026-09-11 10:00:00','2026-09-11 13:00:00',200000,0,200000,'ghi','' +pay([{ngayThanhToan:'2026-09-11',soTien:250000,ghiChu:''}]),-50000],
  // Long stay (labelled), still running on 2026-09-28; one rent payment, one deposit, a 0 đ line (skipped quietly).
  ['K3','Nhà Mẫu','P102',null,'Người Thuê','0901 234 567',null,'thu.login','Thuê dài hạn','2026-08-01 14:00:00','2026-12-01 12:00:00',20000000,100000,20100000,'',pay([{ngayThanhToan:'2026-08-01',soTien:5000000,ghiChu:'tiền cọc'},{ngayThanhToan:'2026-08-01',soTien:5000000,ghiChu:'tiền thuê tháng 8'},{ngayThanhToan:'2026-08-02',soTien:0,ghiChu:''}]),10100000],
  // Unlabelled 25 days → a lease, ended. Room not in the Phòng tab.
  ['K4','Nhà Mẫu','P999',null,'Dài Ngày','xxx',null,null,null,'2026-07-01 14:00:00','2026-07-26 12:00:00',6000000,0,6000000,'',pay([]),6000000],
  // Future stay.
  ['K5','Nhà Mẫu','P103',null,'Sắp Tới','k','Facebook Ads',null,'Qua đêm','2026-10-20 21:00:00','2026-10-21 10:00:00',400000,0,400000,'',pay([]),400000],
  // Bad dates.
  ['K6','Nhà Mẫu','P101',null,'Lỗi','',null,null,null,'2026-09-20 14:00:00','2026-09-20 12:00:00',1,0,1,'',pay([]),1],
 ]),
 'Nhân viên':tab(['ID','Tên nhân viên','Tên đăng nhập','Quyền','Quản lý cơ sở','Màu','Tỷ lệ hoa hồng'],[
  ['S1','Thu','thu.login','Quản lý','[]','#24C6B3',8],
  ['S2','Chủ','chu','Admin','[]','red',0],
 ]),
 'Chi phí':tab(['ID','Ngày chi','Cơ sở','Nhóm chi phí','Nội dung chi','Số tiền','Ghi chú'],[
  ['E1','2026-09-15 00:00:00','Nhà Mẫu','Chi phí thuê nhà','Tiền nhà tháng 9',30000000,''],
  ['E2','2026-09-15 00:00:00','Không Có','Khác','x',1000,''],
 ]),
});
const handler=(store,driveAccess)=>createSheetImportHandler({db:store,Timestamp:Ts,HttpsError:CodeError,driveAccess});
const call=(store,data,uid='owner',driveAccess)=>handler(store,driveAccess)({auth:{uid},data:{organizationId:'org',...data}});
const code=async(p,c)=>{await assert.rejects(p,e=>{assert.equal(e.code,c);return true;});};
const codes=r=>r.problems.map(p=>p.code).sort();

test('helpers: dates, money, phones, price types, sources',()=>{
 assert.equal(stamp('2026-09-10 14:00:00'),'2026-09-10 14:00');
 assert.equal(stamp('10/09/2026 14:05'),'2026-09-10 14:05');
 assert.equal(stamp(46275.5),'2026-09-10 12:00');
 assert.equal(stamp('hôm qua'),null);
 assert.deepEqual([money(500000.0),money('500.000'),money('1,250,000'),money(null),money('abc')],[500000,500000,1250000,0,null]);
 assert.deepEqual([phone(912345678),phone('ko có'),phone('xxx'),phone('0901 234 567'),phone(0),phone('+84901234567')],['0912345678','','','0901234567','','+84901234567']);
 assert.deepEqual(['Thuê giờ','Qua đêm','3N2D','Combo 2N1D'].map(m=>pricing(m,0,1)),['hourly','overnight','nightly','nightly']);
 assert.deepEqual([source('Booking'),source('Chính chủ'),source('Facebook Ads'),source('Cộng tác viên')],
  [{source:'online',platform:'booking'},{source:'walkIn',platform:'direct'},{source:'online',platform:'other'},{source:'other',platform:null}]);
});

test('preview: counts, problems and overlaps; nothing written',async()=>{
 Ts.clock=Date.parse('2026-09-28T05:00:00Z');
 const store=fakeDb(seed()),before=store.store.size;
 const r=await call(store,{action:'preview',sheets:sheets()});
 assert.equal(store.store.size,before);
 assert.deepEqual(r.counts,{buildings:1,rooms:4,bookings:3,leases:2,payments:4,staff:2,expenses:1,buildingRents:1});
 assert.deepEqual(codes(r),['bad_dates','expense_no_building','long_term_no_lease','overpaid','room_added','staff_unknown']);
 assert.equal(r.problems.find(p=>p.code==='long_term_no_lease').room,'P103');
 assert.equal(r.problems.find(p=>p.code==='staff_unknown').staff,'Ai Đó');
 assert.equal(r.overlapCount,1);
 assert.deepEqual([r.overlaps[0].room,r.overlaps[0].a.id,r.overlaps[0].b.id],['P101','K1','K2']);
 assert.equal(r.existing.bookings.there,0);
});

test('apply rejects overlapping source stays before any write',async()=>{
 const store=fakeDb(seed()),before=JSON.stringify([...store.store]);
 await assert.rejects(call(store,{action:'apply',sheets:sheets(),operationId:'conflict'}),/import_overlap/);
 assert.equal(JSON.stringify([...store.store]),before);
});

test('apply rejects an existing-room conflict atomically; adjacent checkout is accepted',async()=>{
 const source=sheets();source['Đặt phòng'].rows[1][9]='2026-09-11 12:00:00';
 const store=fakeDb(seed());
 const preview=await call(store,{action:'preview',sheets:source});
 const {planImport,documents}=require('../sheet_import');
 const plan=planImport(source,{organizationId:'org',nowMs:Ts.now().toMillis(),fail:(c,m)=>{throw new CodeError(c,m);}});
 const room=plan.bookings[0].roomId;
 store.store.set(`rooms/${room}`,{organizationId:'org',bookingRevision:4});
 store.store.set('bookings/existing',{organizationId:'org',roomId:room,status:'checkedOut',startTime:Ts.fromMillis(plan.bookings[0].start),endTime:Ts.fromMillis(plan.bookings[0].end)});
 const before=JSON.stringify([...store.store]);
 await assert.rejects(call(store,{action:'apply',sheets:source,operationId:'existing'}),/import_overlap/);
 assert.equal(JSON.stringify([...store.store]),before);
 store.store.set('bookings/existing',{...store.store.get('bookings/existing'),endTime:Ts.fromMillis(plan.bookings[0].start),startTime:Ts.fromMillis(plan.bookings[0].start-3600000)});
 await call(store,{action:'apply',sheets:source,operationId:'adjacent'});
 assert.equal(store.store.get(`rooms/${room}`).bookingRevision,5);
});

test('apply: records in the app shapes; the same file again creates nothing',async()=>{
 Ts.clock=Date.parse('2026-09-28T05:00:00Z');
 const store=fakeDb(seed());
 const validSheets=sheets();validSheets['Đặt phòng'].rows[1][9]='2026-09-11 12:00:00';
 const r=await call(store,{action:'apply',sheets:validSheets,operationId:'op1'});
 // payments: 4 stay payments + 1 expense.
 assert.deepEqual(r.created,{buildings:1,rooms:4,staffProfiles:2,bookings:3,tenants:2,payments:5});
 const all=[...store.store.entries()];
 const one=(col,f)=>all.filter(([p])=>p.startsWith(col+'/')).map(([p,v])=>({id:p.split('/')[1],...v})).filter(f);
 const b=one('buildings',x=>x.importSource)[0];
 assert.deepEqual([b.name,b.timeZone,b.currency,b.importedRentInMinor,b.organizationId],['Nhà Mẫu','Asia/Ho_Chi_Minh','VND',30000000,'org']);
 const rooms=one('rooms',x=>x.buildingId===b.id).map(x=>x.roomNumber).sort();
 assert.deepEqual(rooms,['P101','P102','P103','P999']);
 const k1=one('bookings',x=>x.guestName==='Khách A')[0];
 assert.deepEqual([k1.status,k1.totalPrice,k1.paidAmount,k1.depositAmount,k1.pricingType,k1.source,k1.platform,k1.guestPhone],['checkedOut',550000,550000,200000,'nightly','online','booking','0912345678']);
 assert.deepEqual(k1.surcharges,[{label:'Phụ phí',amount:50000}]);
 assert.equal(k1.startTime.toMillis(),Date.parse('2026-09-10T07:00:00Z'));
 assert.equal(k1.depositPayment.paidOn,'2026-09-05');
 assert.match(k1.notes,/Gói: 2N1D/);assert.match(k1.notes,/Nguồn: Booking/);
 const thu=one('staffProfiles',x=>x.displayName==='Thu')[0];
 assert.equal(k1.staffInChargeId,thu.id);
 assert.deepEqual([thu.code,thu.importedRole,thu.commissionPercent,thu.color,thu.accountId],['S02','manager',8,'#24c6b3',null]);
 const chu=one('staffProfiles',x=>x.displayName==='Chủ')[0];
 assert.deepEqual([chu.code,chu.importedRole,chu.color],['S03','administrator','']);
 const k2=one('bookings',x=>x.guestName==='Khách B')[0];
 assert.deepEqual([k2.pricingType,k2.source,k2.guestPhone,k2.staffInChargeId],['hourly','walkIn',null,null]);
 const k5=one('bookings',x=>x.guestName==='Sắp Tới')[0];
 assert.deepEqual([k5.status,k5.pricingType,k5.checkedInAt],['confirmed','overnight',undefined]);
 const t3=one('tenants',x=>x.fullName==='Người Thuê')[0];
 assert.deepEqual([t3.status,t3.moveInLocalDate,t3.contractEndLocalDate,t3.monthlyRentMinor,t3.depositMinor,t3.phoneNumber,t3.moveOutDate,t3.staffInChargeId],
  ['active','2026-08-01','2026-12-01',5000000,5000000,'0901234567',null,thu.id]);
 assert.match(t3.notes,/Phụ phí: 100,000/);
 const t4=one('tenants',x=>x.fullName==='Dài Ngày')[0];
 assert.deepEqual([t4.status,t4.moveOutLocalDate,t4.monthlyRentMinor],['moveOut','2026-07-26',6000000]);
 const rent=one('payments',x=>x.tenantId===t3.id);
 assert.deepEqual(rent.map(x=>[x.invoiceKind,x.type,x.amountMinor,x.status,x.dueLocalDate]),[['tenantRent','rent',5000000,'paid','2026-08-01']]);
 const k1pay=one('payments',x=>x.bookingId===k1.id).sort((a,c)=>a.paidAt.toMillis()-c.paidAt.toMillis());
 assert.deepEqual(k1pay.map(x=>[x.amount,x.bookingDeposit??false,x.type]),[[200000,true,'hourlyRent'],[350000,false,'hourlyRent']]);
 const exp=one('payments',x=>x.invoiceKind==='expense')[0];
 assert.deepEqual([exp.direction,exp.amountMinor,exp.calculation.category,exp.status,exp.buildingId],['expense',30000000,'Chi phí thuê nhà','paid',b.id]);
 assert.ok(r.sheet.find(t=>t.name==='Đặt phòng').rows.length===3);
 assert.equal(one('teamActivity',x=>x.action==='sheet_import').length,1);
 // The owner fixes a name; the same file again: nothing new, nothing overwritten.
 store.store.set(`bookings/${k1.id}`,{...store.store.get(`bookings/${k1.id}`),guestName:'Đã sửa'});
 const size=store.store.size;
 const again=await call(store,{action:'apply',sheets:validSheets,operationId:'op2'});
 assert.deepEqual(again.created,{});
 assert.equal(store.store.get(`bookings/${k1.id}`).guestName,'Đã sửa');
 assert.equal(again.existing.bookings.there,3);
 assert.equal(store.store.size,size+2); // the run record and its activity line only
});

test('refuses: a password column, a non-owner, missing tabs or columns, bad cells',async()=>{
 const s=sheets();s['Nhân viên']=tab(['ID','Tên nhân viên','Mật khẩu'],[['S1','Thu','123']]);
 await code(call(fakeDb(seed()),{action:'preview',sheets:s}),'invalid-argument');
 await code(call(fakeDb(seed()),{action:'preview',sheets:sheets()},'maid'),'permission-denied');
 const noBookings=sheets();delete noBookings['Đặt phòng'];
 await code(call(fakeDb(seed()),{action:'preview',sheets:noBookings}),'invalid-argument');
 const noColumn=sheets();noColumn['Phòng']=tab(['ID','Tên cơ sở'],[['B1','x']]);
 await code(call(fakeDb(seed()),{action:'preview',sheets:noColumn}),'invalid-argument');
 const strange=sheets();strange['Khác']=tab(['ID'],[]);
 await code(call(fakeDb(seed()),{action:'preview',sheets:strange}),'invalid-argument');
 const objectCell=sheets();objectCell['Phòng'].rows[0][4]={x:1};
 await code(call(fakeDb(seed()),{action:'preview',sheets:objectCell}),'invalid-argument');
 await code(call(fakeDb(seed()),{action:'apply',sheets:sheets()}),'invalid-argument');
 await code(call(fakeDb(seed()),{action:'preview',sheets:sheets(),extra:1}),'invalid-argument');
});

test('saveSheet: the new .xlsx goes to the CanHo360 folder as a Google Sheet',async()=>{
 const uploads=[];
 const driveAccess={open:async()=>({rootFolder:async()=>'root1',upload:async f=>{uploads.push(f);return {id:'f1'};}})};
 const store=fakeDb(seed());
 const xlsx=Buffer.from('PK\x03\x04rest').toString('base64');
 const r=await call(store,{action:'saveSheet',fileBase64:xlsx,name:'CanHo360 - dữ liệu nhập.xlsx'},'owner',driveAccess);
 assert.deepEqual(r,{fileId:'f1',url:'https://docs.google.com/spreadsheets/d/f1/edit'});
 assert.deepEqual([uploads[0].parent,uploads[0].convertTo,uploads[0].name],['root1','application/vnd.google-apps.spreadsheet','CanHo360 - dữ liệu nhập.xlsx']);
 await code(call(store,{action:'saveSheet',fileBase64:Buffer.from('not a zip').toString('base64'),name:'x'},'owner',driveAccess),'invalid-argument');
 await code(call(store,{action:'saveSheet',fileBase64:xlsx,name:'x'},'maid',driveAccess),'permission-denied');
});
