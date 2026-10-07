'use strict';
// Sheet import (2026-10-05, Tom): the .xlsx export of anh Hưng's old app →
// CanHo360. Design: IMPORT_SHEET.md. The app reads the file and sends only the
// known columns (never "Mật khẩu"); this module maps them, previews and writes.
//  - preview: what would be created, problems to look at, overlapping stays.
//  - apply:   creates what is missing. Every record's ID comes from the old
//             app's ID, so running the same file again creates nothing twice
//             and never overwrites what the owner changed since.
//  - saveSheet: uploads the new sheet (built by the app) to the owner's
//             connected Google Drive as a Google Sheet.
const {createHash}=require('node:crypto');
const {localTime}=require('./booking_quote');
const {propertyDate,propertyDayStart}=require('./lease_dates');

const ZONE='Asia/Ho_Chi_Minh',CURRENCY='VND';
const TABS={
 'Phòng':{need:['ID','Tên cơ sở','Mã phòng Json'],more:['Giá thuê cơ sở','Ghi chú']},
 'Đặt phòng':{need:['ID','Tên cơ sở','Mã phòng','Tên khách hàng','Ngày giờ checkin','Ngày giờ checkout','Tổng doanh thu'],
  more:['Ngày tạo','Số điện thoại','Nguồn','Nhân viên','Hình thức phòng','Đơn giá','Phụ phí','Ghi chú','Thanh toán Json','Số tiền còn lại']},
 'Nhân viên':{need:['ID','Tên nhân viên'],more:['Tên đăng nhập','Quyền','Quản lý cơ sở','Màu','Tỷ lệ hoa hồng']},
 'Chi phí':{need:['ID','Ngày chi','Cơ sở','Số tiền'],more:['Nhóm chi phí','Nội dung chi','Ghi chú']},
};
const REQUIRED_TABS=['Phòng','Đặt phòng'];
// Never accepted, even if an app version sent it by mistake.
const SECRET=/m[ậa]t\s*kh[ẩa]u|password/i;
const MAX_ROWS=5000,MAX_CELL=5000;
const LONG_STAY_DAYS=20;
const ROLES={'admin':'administrator','quản trị':'administrator','quản trị viên':'administrator','quản lý':'manager','nhà đầu tư':'investor','nhân viên':'staff'};

const norm=v=>String(v??'').normalize('NFC').trim().replace(/\s+/g,' ').toLowerCase();
const text=(v,max=1000)=>{if(v==null)return '';const s=String(v).normalize('NFC').trim();return s.length>max?s.slice(0,max):s;};
const sha=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');

/** 'YYYY-MM-DD HH:mm' from a cell: text from the app ('2026-10-06 14:00:00'),
 * 'dd/MM/yyyy HH:mm', or an Excel serial number. */
function stamp(v){
 if(typeof v==='number'&&Number.isFinite(v)&&v>20000&&v<80000){
  const ms=Math.round((v-25569)*86400000/60000)*60000,d=new Date(ms).toISOString();
  return `${d.slice(0,10)} ${d.slice(11,16)}`;
 }
 if(typeof v!=='string')return null;
 const s=v.trim();
 let m=s.match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?)?$/);
 if(m)return `${m[1]}-${m[2]}-${m[3]} ${(m[4]??'00').padStart(2,'0')}:${m[5]??'00'}`;
 m=s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::\d{2})?)?$/);
 if(m)return `${m[3]}-${m[2].padStart(2,'0')}-${m[1].padStart(2,'0')} ${(m[4]??'00').padStart(2,'0')}:${m[5]??'00'}`;
 return null;
}
const instant=s=>s?localTime(s,ZONE):null;
/** Whole đồng: 500000, 500000.0, "500.000", "500,000". Empty = 0; not a number = null. */
function money(v){
 if(v==null||v==='')return 0;
 if(typeof v==='number')return Number.isFinite(v)?Math.round(v):null;
 if(typeof v!=='string')return null;
 const s=v.trim().replace(/[₫đ\s]|vnd/gi,'');
 if(!/^-?[\d.,]+$/.test(s))return null;
 const n=Number(s.replace(/[.,](?=\d{3}(\D|$))/g,'').replace(',','.'));
 return Number.isFinite(n)?Math.round(n):null;
}
/** "ko có", "xxx", "k"… → ''; 912345678 (lost its 0) → 0912345678. */
function phone(v){
 if(v==null)return '';
 let s=typeof v==='number'?String(Math.round(v)):String(v).trim();
 s=s.replace(/[\s.\-()]/g,'');
 if(!/^\+?\d{6,}$/.test(s))return '';
 if(/^\d{9}$/.test(s)&&s[0]!=='0')s='0'+s;
 return s.slice(0,30);
}
/** A JSON cell: null when empty, undefined when unreadable. */
function json(v){
 if(v==null||v==='')return null;
 if(typeof v!=='string')return undefined;
 try{return JSON.parse(v);}catch{return undefined;}
}
const isDeposit=note=>/c[ọo]c/i.test(String(note??''));
/** Our price type from the old "Hình thức phòng" (packages 2N1D… are nights). */
function pricing(method,start,end){
 const m=norm(method);
 if(/giờ|\bgio\b/.test(m))return 'hourly';
 if(/qua đêm|qua dem/.test(m))return 'overnight';
 if(/\d+\s*n\s*\d+\s*d|combo|đêm|\bdem\b/.test(m))return 'nightly';
 if(/ngày|\bngay\b/.test(m))return 'daily';
 return end-start<24*3600000&&propertyDate(start,ZONE)===propertyDate(end,ZONE)?'hourly':'nightly';
}
/** Booking source: the old app's free list → ours (the original word stays in the notes). */
function source(v){
 const s=norm(v);
 if(!s)return {source:'other',platform:null};
 for(const p of ['booking','agoda','airbnb','traveloka'])if(s.includes(p))return {source:'online',platform:p};
 if(/facebook|google|online|website|tiktok|\bads\b/.test(s))return {source:'online',platform:'other'};
 if(/chính chủ|chinh chu|trực tiếp|truc tiep|vãng lai|vang lai|walk/.test(s))return {source:'walkIn',platform:'direct'};
 if(/điện thoại|dien thoai|phone/.test(s))return {source:'phone',platform:'direct'};
 return {source:'other',platform:null};
}

/** Raw tabs → rows of {column: value}. Checks the shape; refuses secrets. */
function readTabs(sheets,fail){
 if(!sheets||typeof sheets!=='object'||Array.isArray(sheets))fail('invalid-argument','import_invalid_file');
 const out={};
 for(const [tab,raw] of Object.entries(sheets)){
  const spec=TABS[tab];
  if(!spec)fail('invalid-argument','import_invalid_file');
  if(!raw||typeof raw!=='object'||!Array.isArray(raw.headers)||!Array.isArray(raw.rows)||raw.rows.length>MAX_ROWS)fail('invalid-argument','import_invalid_file');
  const headers=raw.headers.map(h=>typeof h==='string'?h.normalize('NFC').trim():'');
  if(headers.some(h=>SECRET.test(h)))fail('invalid-argument','import_secret_column');
  if(headers.some(h=>![...spec.need,...spec.more].includes(h))||new Set(headers).size!==headers.length)fail('invalid-argument','import_invalid_file');
  const missing=spec.need.filter(h=>!headers.includes(h));
  if(missing.length)fail('invalid-argument','import_missing_column',{tab,columns:missing});
  out[tab]=raw.rows.map(r=>{
   if(!Array.isArray(r)||r.length>headers.length)fail('invalid-argument','import_invalid_file');
   const row={};
   headers.forEach((h,i)=>{
    const v=r[i]??null;
    if(v!==null&&!['string','number','boolean'].includes(typeof v))fail('invalid-argument','import_invalid_file');
    if(typeof v==='string'&&v.length>MAX_CELL)fail('invalid-argument','import_invalid_file');
    row[h]=typeof v==='string'&&!v.trim()?null:v;
   });
   return row;
  }).filter(row=>row.ID!=null&&String(row.ID).trim()!=='');
 }
 for(const tab of REQUIRED_TABS)if(!out[tab])fail('invalid-argument','import_missing_tab',{tab});
 return out;
}

/** The whole import worked out, without writing anything. */
function planImport(sheets,{organizationId,nowMs,fail}){
 const tabs=readTabs(sheets,fail);
 const id=(kind,...parts)=>`imp_${kind}_${sha([organizationId,kind,...parts]).slice(0,24)}`;
 const problems=[],overlaps=[];
 const problem=(code,tab,ref={})=>problems.push({code,tab,...ref});
 const today=propertyDate(nowMs,ZONE);

 // Buildings and rooms (tab Phòng).
 const buildings=[],byName=new Map(),seen=new Set();
 const addBuilding=(sourceId,name,extra={})=>{
  const b={id:id('b',String(sourceId)),sourceId:String(sourceId),name:text(name,160)||String(sourceId),rentMinor:0,note:'',rooms:[],roomByCode:new Map(),...extra};
  buildings.push(b);byName.set(norm(b.name),b);return b;
 };
 const addRoom=(b,code,extra={})=>{
  const r={id:id('r',b.sourceId,norm(code)),code:text(code,40),longTerm:false,note:'',buildingId:b.id,...extra};
  b.rooms.push(r);b.roomByCode.set(norm(code),r);return r;
 };
 for(const row of tabs['Phòng']){
  const sid=String(row.ID).trim();
  if(seen.has(sid)){problem('duplicate_id','Phòng',{id:sid});continue;}
  seen.add(sid);
  const name=text(row['Tên cơ sở'],160);
  if(!name){problem('building_no_name','Phòng',{id:sid});continue;}
  if(byName.has(norm(name))){problem('duplicate_building','Phòng',{id:sid,building:name});continue;}
  const rent=money(row['Giá thuê cơ sở']);
  if(rent===null||rent<0)problem('bad_amount','Phòng',{id:sid,building:name});
  const b=addBuilding(sid,name,{rentMinor:rent>0?rent:0,note:text(row['Ghi chú'],2000)});
  const list=json(row['Mã phòng Json']);
  if(list===undefined||(list!==null&&!Array.isArray(list))){problem('bad_rooms','Phòng',{id:sid,building:name});continue;}
  for(const x of list??[]){
   const code=text(x?.maPhong,40);
   if(!code){problem('room_no_code','Phòng',{id:sid,building:name});continue;}
   if(b.roomByCode.has(norm(code))){problem('duplicate_room','Phòng',{id:sid,building:name,room:code});continue;}
   addRoom(b,code,{longTerm:norm(x?.trangThai)==='thuê dài hạn',note:text(x?.ghiChu,500)});
  }
 }

 // Staff (tab Nhân viên): profiles waiting for an email invitation.
 const staff=[],staffByName=new Map();
 seen.clear();
 for(const row of tabs['Nhân viên']??[]){
  const sid=String(row.ID).trim();
  if(seen.has(sid)){problem('duplicate_id','Nhân viên',{id:sid});continue;}
  seen.add(sid);
  const name=text(row['Tên nhân viên'],120);
  if(!name){problem('staff_no_name','Nhân viên',{id:sid});continue;}
  const r=row['Tỷ lệ hoa hồng'],rate=typeof r==='number'&&r>=0&&r<=100?r:0;
  const color=typeof row['Màu']==='string'&&/^#[0-9a-fA-F]{6}$/.test(row['Màu'].trim())?row['Màu'].trim().toLowerCase():'';
  const s={id:id('s',sid),sourceId:sid,name,role:ROLES[norm(row['Quyền'])]??'staff',roleText:text(row['Quyền'],60),commissionPercent:rate,color};
  staff.push(s);
  for(const k of [name,row['Tên đăng nhập']])if(k!=null&&String(k).trim()&&!staffByName.has(norm(k)))staffByName.set(norm(k),s);
 }

 // Stays (tab Đặt phòng): leases and short stays, with their payments.
 const bookings=[],leases=[],payments=[],unknownStaff=new Set();
 seen.clear();
 for(const row of tabs['Đặt phòng']){
  const sid=String(row.ID).trim(),guest=text(row['Tên khách hàng'],100);
  const ref={id:sid,guest};
  if(seen.has(sid)){problem('duplicate_id','Đặt phòng',ref);continue;}
  seen.add(sid);
  // The building and room: added when the Phòng tab does not list them.
  const bname=text(row['Tên cơ sở'],160),code=text(row['Mã phòng'],40);
  if(!bname||!code){problem('stay_no_room','Đặt phòng',ref);continue;}
  let b=byName.get(norm(bname));
  if(!b){b=addBuilding(`name:${norm(bname)}`,bname);problem('building_added','Đặt phòng',{...ref,building:bname});}
  let room=b.roomByCode.get(norm(code));
  if(!room){room=addRoom(b,code);problem('room_added','Đặt phòng',{...ref,building:b.name,room:code});}
  Object.assign(ref,{building:b.name,room:room.code});
  const startLocal=stamp(row['Ngày giờ checkin']),endLocal=stamp(row['Ngày giờ checkout']);
  const start=instant(startLocal),end=instant(endLocal);
  if(start==null||end==null||end<=start){problem('bad_dates','Đặt phòng',ref);continue;}
  const price=money(row['Đơn giá']),fee=money(row['Phụ phí']),total=money(row['Tổng doanh thu']);
  if(total===null||total<0||price===null||fee===null||fee<0){problem('bad_amount','Đặt phòng',ref);continue;}
  const method=text(row['Hình thức phòng'],60),days=(end-start)/86400000;
  const lease=norm(method)==='thuê dài hạn'||(!method&&days>LONG_STAY_DAYS);
  const staffName=row['Nhân viên']!=null?String(row['Nhân viên']).trim():'';
  const who=staffName?staffByName.get(norm(staffName)):null;
  if(staffName&&!who&&!unknownStaff.has(norm(staffName))){unknownStaff.add(norm(staffName));problem('staff_unknown','Đặt phòng',{id:sid,staff:staffName});}
  // Payments: "cọc" in the note = deposit.
  const list=json(row['Thanh toán Json']);
  if(list===undefined||(list!==null&&!Array.isArray(list)))problem('bad_payment','Đặt phòng',ref);
  const paid=[];
  (Array.isArray(list)?list:[]).forEach((p,i)=>{
   const amount=money(p?.soTien),day=typeof p?.ngayThanhToan==='string'?stamp(p.ngayThanhToan)?.slice(0,10):null;
   if(amount===0)return; // a 0 đ line in the old app: nothing was paid
   if(amount===null||amount<0||!day||propertyDayStart(day,ZONE)==null){problem('bad_payment','Đặt phòng',ref);return;}
   paid.push({id:id('p',sid,i),amount,day,deposit:isDeposit(p?.ghiChu),note:text(p?.ghiChu,500)});
  });
  const paidTotal=paid.reduce((a,p)=>a+p.amount,0);
  const src=text(row['Nguồn'],60),note=text(row['Ghi chú'],1500);
  const notes=[note,method&&!lease?`Gói: ${method}`:'',src?`Nguồn: ${src}`:'',lease&&fee>0?`Phụ phí: ${fee.toLocaleString('en-US')}`:''].filter(Boolean).join('\n').slice(0,2000);
  if(!guest)problem('no_name','Đặt phòng',ref);
  const common={sourceId:sid,buildingId:b.id,building:b.name,roomId:room.id,room:room.code,guest:guest||'Khách không tên',phone:phone(row['Số điện thoại']),
   startLocal,endLocal,start,end,total,staffId:who?.id??null,notes,paid,paidTotal};
  if(lease){
   const tenantId=id('t',sid),months=Math.max(1,Math.round(days/30)),startDay=startLocal.slice(0,10),endDay=endLocal.slice(0,10);
   const rentMinor=Math.max(1,Math.round((price||total)/months));
   if(endDay<=startDay){problem('bad_dates','Đặt phòng',ref);continue;}
   leases.push({...common,id:tenantId,months,rentMinor,startDay,endDay,ended:endDay<=today,
    depositMinor:paid.filter(p=>p.deposit).reduce((a,p)=>a+p.amount,0)});
   for(const p of paid)if(!p.deposit)payments.push({...p,kind:'rent',stay:'lease',stayId:tenantId,sourceId:sid,buildingId:b.id,roomId:room.id,building:b.name,room:room.code,guest:common.guest});
  }else{
   if(paidTotal>total)problem('overpaid','Đặt phòng',ref);
   const bookingId=id('k',sid),status=end<=nowMs?'checkedOut':start<=nowMs?'checkedIn':'confirmed';
   bookings.push({...common,id:bookingId,fee,method,pricingType:pricing(method,start,end),...source(src),status,
    depositMinor:paid.filter(p=>p.deposit).reduce((a,p)=>a+p.amount,0)});
   for(const p of paid)payments.push({...p,kind:p.deposit?'deposit':'stay',stay:'booking',stayId:bookingId,sourceId:sid,buildingId:b.id,roomId:room.id,building:b.name,room:room.code,guest:common.guest});
  }
 }

 // Overlapping stays are shown in preview and block application.
 const stays=[...bookings.map(s=>({...s,what:'booking',to:s.end})),...leases.map(s=>({...s,what:'lease',to:propertyDayStart(s.endDay,ZONE)}))];
 const byRoom=new Map();
 for(const s of stays){if(!byRoom.has(s.roomId))byRoom.set(s.roomId,[]);byRoom.get(s.roomId).push(s);}
 const side=s=>({id:s.sourceId,guest:s.guest,start:s.startLocal,end:s.endLocal,kind:s.what});
 for(const list of byRoom.values()){
  list.sort((a,c)=>a.start-c.start);
  for(let i=0;i<list.length;i++)for(let j=i+1;j<list.length&&list[j].start<list[i].to;j++)
   overlaps.push({building:list[i].building,room:list[i].room,a:side(list[i]),b:side(list[j])});
 }
 // Rooms marked "Thuê dài hạn" in the old app with no lease running today.
 for(const b of buildings)for(const r of b.rooms)if(r.longTerm&&!leases.some(l=>l.roomId===r.id&&!l.ended))problem('long_term_no_lease','Phòng',{building:b.name,room:r.code});

 // Expenses (tab Chi phí).
 const expenses=[];
 seen.clear();
 for(const row of tabs['Chi phí']??[]){
  const sid=String(row.ID).trim();
  if(seen.has(sid)){problem('duplicate_id','Chi phí',{id:sid});continue;}
  seen.add(sid);
  const b=byName.get(norm(row['Cơ sở'])),day=stamp(row['Ngày chi'])?.slice(0,10),amount=money(row['Số tiền']);
  if(!b){problem('expense_no_building','Chi phí',{id:sid,building:text(row['Cơ sở'],160)});continue;}
  if(!day||propertyDayStart(day,ZONE)==null||amount===null||amount<=0){problem('bad_amount','Chi phí',{id:sid,building:b.name});continue;}
  expenses.push({id:id('e',sid),sourceId:sid,buildingId:b.id,building:b.name,day,amountMinor:amount,category:text(row['Nhóm chi phí'],120),content:text(row['Nội dung chi'],500),note:text(row['Ghi chú'],500)});
 }
 const rooms=buildings.reduce((a,b)=>a+b.rooms.length,0);
 return {buildings,staff,bookings,leases,payments,expenses,problems,overlaps,
  counts:{buildings:buildings.length,rooms,bookings:bookings.length,leases:leases.length,payments:payments.length,staff:staff.length,expenses:expenses.length,buildingRents:buildings.filter(b=>b.rentMinor>0).length}};
}

/** Documents to create, in the same shapes the app's own screens write. */
function documents(plan,{organizationId,uid,now,Timestamp,runId,staffCodes}){
 const ts=ms=>Timestamp.fromMillis(ms),noon=day=>localTime(`${day} 12:00`,ZONE);
 const imported=sourceId=>({kind:'oldAppSheet',sourceId,runId});
 const base={organizationId,createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid};
 const docs=[],add=(kind,path,data)=>docs.push({kind,path,data});
 const bookingById=new Map(plan.bookings.map(k=>[k.id,k]));
 for(const b of plan.buildings){
  add('buildings',`buildings/${b.id}`,{...base,name:b.name,address:'',timeZone:ZONE,currency:CURRENCY,importSource:imported(b.sourceId),
   ...(b.note?{importNote:b.note}:{}),...(b.rentMinor>0?{importedRentInMinor:b.rentMinor}:{})});
  for(const r of b.rooms)add('rooms',`rooms/${r.id}`,{...base,buildingId:b.id,roomNumber:r.code,roomType:'',area:0,currency:CURRENCY,rentalMode:'both',
   importSource:imported(`${b.sourceId}/${r.code}`),...(r.note?{importNote:r.note}:{})});
 }
 for(const s of plan.staff){
  const {updatedBy,...meta}=base;
  add('staffProfiles',`staffProfiles/${s.id}`,{...meta,code:staffCodes.get(s.id),displayName:s.name,email:'',phone:'',color:s.color,employmentStatus:'active',accountId:null,
   importedRole:s.role,commissionPercent:s.commissionPercent,importSource:imported(s.sourceId)});
 }
 for(const k of plan.bookings){
  const deposit=k.paid.find(p=>p.deposit);
  add('bookings',`bookings/${k.id}`,{...base,roomId:k.roomId,buildingId:k.buildingId,currency:CURRENCY,status:k.status,
   paidAmount:k.paidTotal,depositAmount:k.depositMinor,depositPaidAmount:0,depositRefundedAmount:0,depositRefunded:false,
   guestName:k.guest,guestPhone:k.phone||null,notes:k.notes||null,pricingType:k.pricingType,source:k.source,...(k.platform?{platform:k.platform}:{}),
   staffInChargeId:k.staffId,totalPrice:k.total,surcharges:k.fee>0?[{label:'Phụ phí',amount:k.fee}]:[],nightPrices:null,hourlyPrice:null,
   startTime:ts(k.start),endTime:ts(k.end),
   ...(k.status!=='confirmed'?{checkedInAt:ts(k.start)}:{}),...(k.status==='checkedOut'?{checkedOutAt:ts(k.end)}:{}),
   ...(deposit?{depositPayment:{amount:deposit.amount,paymentMethod:'other',paidOn:deposit.day,paidAt:ts(noon(deposit.day)),paymentId:deposit.id}}:{}),
   importSource:imported(k.sourceId)});
 }
 for(const l of plan.leases){
  const moveIn=propertyDayStart(l.startDay,ZONE),end=propertyDayStart(l.endDay,ZONE);
  add('tenants',`tenants/${l.id}`,{...base,buildingId:l.buildingId,roomId:l.roomId,fullName:l.guest,phoneNumber:l.phone,status:l.ended?'moveOut':'active',
   isMainTenant:true,mainTenantId:null,moveInDate:ts(moveIn),moveInLocalDate:l.startDay,moveInTimeZone:ZONE,
   moveOutDate:l.ended?ts(end):null,...(l.ended?{moveOutLocalDate:l.endDay,moveOutTimeZone:ZONE}:{}),
   contractStartDate:ts(moveIn),contractEndDate:ts(end),contractEndLocalDate:l.endDay,
   monthlyRent:l.rentMinor,monthlyRentMinor:l.rentMinor,currency:CURRENCY,staffInChargeId:l.staffId,
   paymentPeriodMonths:1,paymentDueDay:null,periodRentMinor:l.rentMinor,
   ...(l.depositMinor>0?{deposit:l.depositMinor,depositMinor:l.depositMinor,depositMethod:null,depositAccountId:null,depositAccountLabel:null,depositNote:'Từ file cũ'}:{}),
   ...(l.notes?{notes:l.notes}:{}),importSource:imported(l.sourceId)});
 }
 for(const p of plan.payments){
  const paidAt=ts(noon(p.day));
  if(p.stay==='booking'){
   const k=bookingById.get(p.stayId);
   add('payments',`payments/${p.id}`,{organizationId,buildingId:p.buildingId,roomId:p.roomId,tenantId:null,tenantName:p.guest,bookingId:p.stayId,
    type:'hourlyRent',status:'paid',amount:p.amount,paidAmount:p.amount,currency:CURRENCY,paymentMethod:'other',dueDate:ts(k.end),paidAt,createdAt:now,
    billingStartDate:ts(k.start),billingEndDate:ts(k.end),descriptionKey:p.deposit?'booking_deposit_payment':'booking_payment',...(p.deposit?{bookingDeposit:true}:{}),
    ...(p.note?{importNote:p.note}:{}),importSource:imported(`${p.sourceId}#${p.id}`)});
  }else{
   add('payments',`payments/${p.id}`,{...base,buildingId:p.buildingId,roomId:p.roomId,tenantId:p.stayId,tenantName:p.guest,invoiceVersion:2,invoiceKind:'tenantRent',type:'rent',
    direction:'income',currency:CURRENCY,amount:p.amount,amountMinor:p.amount,totalMinor:p.amount,paidAmount:p.amount,status:'paid',paidAt,paidBy:uid,paymentMethod:'other',
    billingStartLocalDate:p.day,billingEndLocalDate:p.day,dueLocalDate:p.day,dueDate:ts(propertyDayStart(p.day,ZONE)),timeZone:ZONE,
    calculation:{imported:true,amountMinor:p.amount,currency:CURRENCY,note:p.note},description:(p.note||'Tiền thuê (từ file cũ)').slice(0,1000),importSource:imported(`${p.sourceId}#${p.id}`)});
  }
 }
 for(const e of plan.expenses){
  const what=[e.category,e.content].filter(Boolean).join(': ')||'Chi phí';
  add('payments',`payments/${e.id}`,{...base,buildingId:e.buildingId,roomId:'',tenantId:null,tenantName:e.content||e.category||'Chi phí',invoiceVersion:2,invoiceKind:'expense',type:'expense',
   direction:'expense',currency:CURRENCY,amount:e.amountMinor,amountMinor:e.amountMinor,totalMinor:e.amountMinor,paidAmount:e.amountMinor,status:'paid',paidAt:ts(noon(e.day)),paidBy:uid,paymentMethod:'other',
   billingStartLocalDate:e.day,billingEndLocalDate:e.day,dueLocalDate:e.day,dueDate:ts(propertyDayStart(e.day,ZONE)),timeZone:ZONE,
   calculation:{chargeType:'expense',category:e.category,content:e.content,amountMinor:e.amountMinor,currency:CURRENCY},
   description:[what,e.note].filter(Boolean).join(' — ').slice(0,1000),importSource:imported(e.sourceId)});
 }
 return docs;
}

/** Rows for the new Google Sheet (the app turns them into an .xlsx). */
function exportTabs(plan){
 const status={confirmed:'Đã đặt',checkedIn:'Đang ở',checkedOut:'Đã trả phòng'};
 const pricingText={hourly:'Theo giờ',overnight:'Qua đêm',nightly:'Theo đêm',daily:'Theo ngày'};
 const leaseDeposits=plan.leases.flatMap(l=>l.paid.filter(p=>p.deposit).map(p=>[p.day,l.building,l.room,l.guest,p.amount,'Tiền cọc (hợp đồng)',p.note]));
 return [
  {name:'Tòa nhà',headers:['Tòa nhà','Số phòng','Tiền thuê tòa nhà / tháng','Ghi chú'],rows:plan.buildings.map(b=>[b.name,b.rooms.length,b.rentMinor||'',b.note])},
  {name:'Phòng',headers:['Tòa nhà','Phòng','Ghi chú'],rows:plan.buildings.flatMap(b=>b.rooms.map(r=>[b.name,r.code,r.note]))},
  {name:'Đặt phòng',headers:['Mã cũ','Tòa nhà','Phòng','Khách','Số điện thoại','Nhận phòng','Trả phòng','Loại giá','Tổng tiền','Đã trả','Còn lại','Trạng thái','Ghi chú'],
   rows:plan.bookings.map(k=>[k.sourceId,k.building,k.room,k.guest,k.phone,k.startLocal,k.endLocal,pricingText[k.pricingType],k.total,k.paidTotal,k.total-k.paidTotal,status[k.status],k.notes])},
  {name:'Hợp đồng thuê',headers:['Mã cũ','Tòa nhà','Phòng','Người thuê','Số điện thoại','Từ ngày','Đến ngày','Tiền thuê / tháng','Tiền cọc','Đã trả tiền thuê','Trạng thái','Ghi chú'],
   rows:plan.leases.map(l=>[l.sourceId,l.building,l.room,l.guest,l.phone,l.startDay,l.endDay,l.rentMinor,l.depositMinor,l.paid.filter(p=>!p.deposit).reduce((a,p)=>a+p.amount,0),l.ended?'Đã trả phòng':'Đang thuê',l.notes])},
  {name:'Thanh toán',headers:['Ngày','Tòa nhà','Phòng','Người trả','Số tiền','Loại','Ghi chú'],
   rows:[...plan.payments.map(p=>[p.day,p.building,p.room,p.guest,p.amount,p.kind==='deposit'?'Tiền cọc':p.kind==='rent'?'Tiền thuê':'Tiền phòng',p.note]),...leaseDeposits]
    .sort((a,c)=>String(a[0]).localeCompare(String(c[0])))},
  {name:'Nhân viên',headers:['Tên','Vai trò (file cũ)','Hoa hồng %'],rows:plan.staff.map(s=>[s.name,s.roleText,s.commissionPercent])},
  {name:'Chi phí',headers:['Ngày','Tòa nhà','Nhóm','Nội dung','Số tiền','Ghi chú'],rows:plan.expenses.map(e=>[e.day,e.building,e.category,e.content,e.amountMinor,e.note])},
 ];
}

/** What the preview screen shows: counts, problems, overlaps (capped). */
function summary(plan,existing){
 return {counts:plan.counts,existing,problems:plan.problems.slice(0,500),problemCount:plan.problems.length,
  overlaps:plan.overlaps.slice(0,300),overlapCount:plan.overlaps.length,
  buildings:plan.buildings.map(b=>({name:b.name,rooms:b.rooms.length,rentMinor:b.rentMinor}))};
}

function createSheetImportHandler({db,Timestamp,HttpsError,driveAccess}){
 const fail=(code,key,details)=>{throw new HttpsError(code,key,details);};
 const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
 const KEYS={preview:['sheets'],apply:['sheets','operationId'],saveSheet:['fileBase64','name']};
 return async request=>{
  const d=request.data||{},uid=request.auth?.uid;
  if(!uid)fail('unauthenticated','sign_in_required');
  const keys=KEYS[d.action];
  if(!keys||!id(d.organizationId)||Object.keys(d).some(k=>!['action','organizationId',...keys].includes(k)))fail('invalid-argument','import_invalid_file');
  // The owner only (owner or co-owner).
  const m=(await db.doc(`memberships/${uid}_${d.organizationId}`).get()).data();
  const org=(await db.doc(`organizations/${d.organizationId}`).get()).data();
  if(!org||org.accessVersion!==2||!m||m.ownerId!==uid||m.organizationId!==d.organizationId||m.accessVersion!==2||m.status!=='active'||!['owner','coOwner'].includes(m.role))fail('permission-denied','import_owner_only');

  if(d.action==='saveSheet'){
   if(typeof d.fileBase64!=='string'||d.fileBase64.length>6*1024*1024||typeof d.name!=='string'||!d.name.trim()||d.name.length>150)fail('invalid-argument','import_invalid_file');
   const bytes=Buffer.from(d.fileBase64,'base64');
   if(bytes.length<4||bytes[0]!==0x50||bytes[1]!==0x4b)fail('invalid-argument','import_invalid_file'); // an .xlsx is a zip
   if(!driveAccess)fail('failed-precondition','drive_not_connected');
   const drive=await driveAccess.open(d.organizationId);
   const folder=await drive.rootFolder();
   const file=await drive.upload({name:d.name.trim(),parent:folder,bytes,mimeType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',convertTo:'application/vnd.google-apps.spreadsheet'});
   await db.collection('teamActivity').doc().set({organizationId:d.organizationId,actorId:uid,createdAt:Timestamp.now(),action:'sheet_saved_to_drive',targetId:d.organizationId,after:{fileId:file.id}});
   return {fileId:file.id,url:`https://docs.google.com/spreadsheets/d/${file.id}/edit`};
  }

  const nowMs=Timestamp.now().toMillis();
  const plan=planImport(d.sheets,{organizationId:d.organizationId,nowMs,fail});
  // Staff codes S01, S02… after the ones already used; an imported profile keeps its code.
  const profiles=(await db.collection('staffProfiles').where('organizationId','==',d.organizationId).get()).docs;
  const used=new Set(profiles.map(v=>v.data().code)),staffCodes=new Map();
  for(const v of profiles)if(plan.staff.some(s=>s.id===v.id))staffCodes.set(v.id,v.data().code);
  let n=1;
  for(const s of plan.staff){
   if(staffCodes.has(s.id))continue;
   while(used.has(`S${String(n).padStart(2,'0')}`))n++;
   const c=`S${String(n).padStart(2,'0')}`;used.add(c);staffCodes.set(s.id,c);
  }
  const runId=sha([d.organizationId,'run',d.operationId??'preview']).slice(0,24);
  const now=Timestamp.now(),docs=documents(plan,{organizationId:d.organizationId,uid,now,Timestamp,runId,staffCodes});
  if(docs.length>20000)fail('invalid-argument','import_too_large');
  // What is already there (the same file again): never written twice.
  const refs=docs.map(x=>db.doc(x.path)),there=new Set();
  for(let i=0;i<refs.length;i+=200){
   const part=refs.slice(i,i+200);
   const snaps=typeof db.getAll==='function'?await db.getAll(...part):await Promise.all(part.map(r=>r.get()));
   snaps.forEach((s,j)=>{if(!s.exists)return;if(s.data().organizationId!==d.organizationId)fail('failed-precondition','import_conflict');there.add(part[j].path);});
  }
  const existing={};
  for(const x of docs){existing[x.kind]??={total:0,there:0};existing[x.kind].total++;if(there.has(x.path))existing[x.kind].there++;}
  if(d.action==='preview')return summary(plan,existing);

  if(!id(d.operationId))fail('invalid-argument','import_invalid_file');
  if(plan.overlaps.length)fail('failed-precondition','import_overlap');
  const missing=docs.filter(x=>!there.has(x.path));
  // One transaction prevents partial imports and uses the same room revision
  // lock as normal reservations/leases. Large files need a smaller split.
  const incoming=missing.filter(x=>['bookings','tenants'].includes(x.kind));
  const roomIds=[...new Set(incoming.map(x=>x.data.roomId))];
  if(missing.length+roomIds.length>450)fail('invalid-argument','import_too_large');
  const millis=v=>v?.toMillis?v.toMillis():null;
  const interval=(kind,x)=>kind==='bookings'?[millis(x.startTime),millis(x.endTime)]:
    [millis(x.moveInDate),millis(x.moveOutDate)??Infinity];
  const applied=await db.runTransaction(async tx=>{
   const member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
   const organization=await tx.get(db.doc(`organizations/${d.organizationId}`));
   if(member.data()?.status!=='active'||member.data()?.role!=='owner'||organization.data()?.closedAt||organization.data()?.mergedInto||
     (organization.data()?.ownerTransferredTo??organization.data()?.createdBy)!==uid)
    fail('permission-denied','import_owner_only');
   const roomLocks=[];
   for(const roomId of roomIds){
    const ref=db.doc(`rooms/${roomId}`),room=await tx.get(ref);
    if(room.exists&&room.data().organizationId!==d.organizationId)fail('failed-precondition','import_conflict');
    roomLocks.push({ref,exists:room.exists,revision:room.data()?.bookingRevision??0});
    for(const kind of ['bookings','tenants']){
     const existing=await tx.get(db.collection(kind).where('roomId','==',roomId));
     for(const row of existing.docs){const x=row.data();
      if(kind==='bookings'&&['cancelled','noShow'].includes(x.status))continue;
      if(kind==='tenants'&&x.isMainTenant===false)continue;
      const [start,end]=interval(kind,x);if(start===null)continue;
      for(const candidate of incoming.filter(v=>v.data.roomId===roomId&&v.path!==row.ref.path)){
       const [a,b]=interval(candidate.kind,candidate.data);
       if(a<end&&(b??Infinity)>start)fail('failed-precondition','import_overlap');
      }
     }
    }
   }
   // Recheck all deterministic IDs so concurrent retry does not duplicate data.
   const create=[];
   for(const x of missing){const saved=await tx.get(db.doc(x.path));
    if(saved.exists){if(saved.data().organizationId!==d.organizationId)fail('failed-precondition','import_conflict');}
    else create.push(x);
   }
   for(const x of create)tx.create(db.doc(x.path),x.data);
   for(const room of roomLocks)if(room.exists)tx.update(room.ref,{bookingRevision:room.revision+1});
   return create;
  });
  const created={};
  for(const x of applied)created[x.kind]=(created[x.kind]??0)+1;
  await db.doc(`importRuns/${d.organizationId}_${runId}`).set({organizationId:d.organizationId,actorId:uid,createdAt:now,created,counts:plan.counts,problemCount:plan.problems.length,overlapCount:plan.overlaps.length});
  await db.collection('teamActivity').doc().set({organizationId:d.organizationId,actorId:uid,createdAt:now,action:'sheet_import',targetId:d.organizationId,after:{created,problems:plan.problems.length,overlaps:plan.overlaps.length}});
  return {...summary(plan,existing),created,sheet:exportTabs(plan)};
 };
}
module.exports={createSheetImportHandler,planImport,documents,exportTabs,stamp,money,phone,pricing,source};
