const {test}=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createTechnicalProblemsHandler,invalidProblemInput}=require('../technical_problems');
const {createCalendarHandler}=require('../calendar');
const {createLeaseLifecycleHandler}=require('../lease_lifecycle');
const at=d=>Ts.fromMillis(Date.parse(d+'T00:00:00+07:00'));
const member=(uid,role,extra={})=>({ownerId:uid,organizationId:'o',accessVersion:2,status:'active',role,buildingScope:'all',buildingIds:[],displayName:uid,...extra});

// Today is 20 Nov 2026 in Vietnam. Room 101 has a lease (Le Van Chinh), room 102 a future booking.
function setup(){
 Ts.clock=Date.parse('2026-11-20T05:00:00Z');
 const db=fakeDb({
  'organizations/o':{accessVersion:2,paymentAccounts:[{id:'vcb',label:'Vietcombank 0123'}]},
  'buildings/b':{organizationId:'o',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},
  'rooms/r1':{organizationId:'o',buildingId:'b',roomNumber:'101',rentalMode:'both',currency:'VND'},
  'rooms/r2':{organizationId:'o',buildingId:'b',roomNumber:'102',rentalMode:'both',currency:'VND'},
  'memberships/owner_o':member('owner','owner'),
  'memberships/maid_o':member('maid','housekeeper'),
  'memberships/front_o':member('front','receptionist'),
  'memberships/inv_o':member('inv','investor'),
  'memberships/far_o':member('far','manager',{buildingScope:'selected',buildingIds:['other']}),
  'tenants/t':{organizationId:'o',buildingId:'b',roomId:'r1',isMainTenant:true,status:'active',fullName:'Le Van Chinh',currency:'VND',moveInDate:at('2026-10-02')},
  'bookings/k':{organizationId:'o',buildingId:'b',roomId:'r2',guestName:'Nguyen Van An',status:'confirmed',startTime:at('2026-12-01'),endTime:at('2026-12-03')},
 });
 const run=createTechnicalProblemsHandler({db,Timestamp:Ts,HttpsError:CodeError});
 const call=(data,uid='owner')=>run({auth:{uid},data:{organizationId:'o',buildingId:'b',...data}});
 return {db,call};
}
const report=o=>({action:'report',operationId:'p1',roomId:'r1',title:'Máy lạnh hỏng',description:'Chảy nước',blocksRoom:false,...o});
const fix=(problemId,o)=>({action:'fix',operationId:'f1',problemId,revision:'0:0',fixedByName:'Thợ Hùng',fixedDate:'2026-11-20',costMinor:500000,recordExpense:false,paymentMethod:null,accountId:null,note:'',...o});

test('new repair cost uses selected currency and exact retry survives later currency change',async()=>{
 const {db,call}=setup();
 const {problemId}=await call(report());
 db.store.get('organizations/o').displayCurrency='USD';
 const request=fix(problemId,{costMinor:1234,inputCurrency:'USD',recordExpense:true,paymentMethod:'cash'});
 const result=await call(request);
 assert.equal(db.store.get(`technicalProblems/${problemId}`).currency,'USD');
 assert.equal(db.store.get(`technicalProblems/${problemId}`).costMinor,1234);
 assert.equal(db.store.get(`payments/${result.expenseId}`).currency,'USD');
 assert.equal(db.store.get(`payments/${result.expenseId}`).amount,12.34);
 assert.equal(db.store.get('buildings/b').currency,'VND');
 db.store.get('organizations/o').displayCurrency='VND';
 assert.deepEqual(await call(request),result);
 const other=await call(report({operationId:'p2'}));
 await assert.rejects(call(fix(other.problemId,{operationId:'stale',inputCurrency:'USD'})),e=>e.message==='problem_currency_changed');
});

test('who can see, report, block and fix',async()=>{
 const {call}=setup();
 // Housekeeping and reception can report; only a manager can block the room.
 const {problemId}=await call(report(),'maid');
 await assert.rejects(call(report({operationId:'p2',blocksRoom:true}),'front'),e=>e.message==='problem_block_needs_manager');
 await call(report({operationId:'p3',roomId:'r2',title:'Vòi nước rỉ'}),'front');
 // Investors can read but not report; staff of another property see nothing.
 const seen=await call({action:'list'},'inv');
 assert.equal(seen.records.length,2);assert.equal(seen.canReport,false);assert.equal(seen.canManage,false);assert.deepEqual(seen.accounts,[]);
 await assert.rejects(call(report({operationId:'p4'}),'inv'),e=>e.code==='permission-denied');
 await assert.rejects(call({action:'list'},'far'),e=>e.code==='permission-denied');
 await assert.rejects(call(fix(problemId),'maid'),e=>e.code==='permission-denied');
 const list=await call({action:'list'});
 assert.equal(list.canManage,true);assert.equal(list.canExpense,true);
 const p=list.records.find(r=>r.id===problemId);
 assert.equal(p.reportedByName,'maid');assert.equal(p.reportedLocalDate,'2026-11-20');assert.deepEqual(p.occupant,{kind:'lease',id:'t',name:'Le Van Chinh'});
 assert.deepEqual(list.rooms.map(r=>[r.roomNumber,r.blocked]),[['101',false],['102',false]]);
});

test('blocking: warnings, no new booking or room move, unblocked when fixed, blocked again on reopen',async()=>{
 const {db,call}=setup();
 const r=await call(report({roomId:'r2',blocksRoom:true}));
 assert.deepEqual(r.warnings.map(w=>[w.kind,w.name,w.start]),[['booking','Nguyen Van An','2026-12-01']],'existing booking listed, not cancelled');
 assert.deepEqual(db.store.get('rooms/r2').openProblemBlocks,[r.problemId]);
 assert.equal(db.store.get('bookings/k').status,'confirmed');
 const calendar=createCalendarHandler({db,Timestamp:Ts,HttpsError:CodeError,FieldValue:{increment:n=>n}});
 const book=id=>calendar({action:'create',bookingId:id,booking:{organizationId:'o',roomId:'r2',guestName:'Guest',startTime:{__timestamp:Date.parse('2026-12-10T05:00:00Z')},endTime:{__timestamp:Date.parse('2026-12-10T08:00:00Z')},totalPrice:100000}},{auth:{uid:'owner'}});
 await assert.rejects(book('new1'),e=>e.message==='room_has_open_problem');
 const lease=createLeaseLifecycleHandler({db,Timestamp:Ts,HttpsError:CodeError});
 await assert.rejects(lease({auth:{uid:'owner'},data:{action:'move',organizationId:'o',buildingId:'b',tenantId:'t',destinationRoomId:'r2',effectiveDate:'2026-11-20',operationId:'mv',revision:'0:0',timeZone:'Asia/Ho_Chi_Minh',reason:'Đổi phòng'}}),e=>e.message==='room_has_open_problem'||e.code==='invalid-argument');
 assert.equal(db.store.get('tenants/t').roomId,'r1');
 const list=await call({action:'list'});assert.equal(list.rooms.find(x=>x.id==='r2').blocked,true);
 // Fixed: the room takes bookings again.
 await call(fix(r.problemId));
 assert.deepEqual(db.store.get('rooms/r2').openProblemBlocks,[]);
 await book('new2');assert.equal(db.store.get('bookings/new2').roomId,'r2');
 // Reopened: blocked again, with a reason.
 await assert.rejects(call({action:'reopen',operationId:'o0',problemId:r.problemId,revision:'0:0',note:''}),e=>e.message==='problem_reopen_needs_reason');
 const again=await call({action:'reopen',operationId:'o1',problemId:r.problemId,revision:'0:0',note:'Lại hỏng'});
 assert.equal(again.warnings.length,2,'both bookings now listed');
 assert.deepEqual(db.store.get('rooms/r2').openProblemBlocks,[r.problemId]);
 // A manager can lift the block without fixing.
 await call({action:'update',operationId:'u1',problemId:r.problemId,revision:'0:0',title:'Máy lạnh hỏng',description:'',blocksRoom:false});
 assert.deepEqual(db.store.get('rooms/r2').openProblemBlocks,[]);
});

test('fixing records who, when, cost and optionally a paid building expense',async()=>{
 const {db,call}=setup();
 const {problemId}=await call(report());
 await assert.rejects(call(fix(problemId,{fixedDate:'2026-11-21'})),e=>e.message==='problem_fixed_in_future');
 await assert.rejects(call(fix(problemId,{fixedDate:'2026-11-19'})),e=>e.message==='problem_fixed_before_report');
 await assert.rejects(call(fix(problemId,{recordExpense:true,costMinor:null})),e=>e.message==='problem_expense_needs_cost');
 await assert.rejects(call(fix(problemId,{recordExpense:true})),e=>e.message==='problem_expense_needs_method');
 const r=await call(fix(problemId,{recordExpense:true,paymentMethod:'bankTransfer',accountId:'vcb'}));
 const p=db.store.get(`technicalProblems/${problemId}`);
 assert.equal(p.status,'fixed');assert.equal(p.fixedByName,'Thợ Hùng');assert.equal(p.costMinor,500000);assert.equal(p.expenseId,r.expenseId);
 const e=db.store.get(`payments/${r.expenseId}`);
 assert.equal(e.direction,'expense');assert.equal(e.invoiceKind,'repair');assert.equal(e.status,'paid');assert.equal(e.totalMinor,500000);assert.equal(e.paidAmount,500000);
 assert.equal(e.paymentAccountLabel,'Vietcombank 0123');assert.equal(e.tenantName,'Thợ Hùng');assert.equal(e.billingStartLocalDate,'2026-11-20');assert.equal(e.problemId,problemId);
 // Retry returns the same result; a second fix is refused.
 assert.deepEqual(await call(fix(problemId,{recordExpense:true,paymentMethod:'bankTransfer',accountId:'vcb'})),r);
 await assert.rejects(call(fix(problemId,{operationId:'f2'})),e=>e.message==='problem_not_open');
 // Fixing without an expense: cost only, nothing in Thu chi.
 const {problemId:other}=await call(report({operationId:'p2',roomId:'r2'}));
 const plain=await call(fix(other,{operationId:'f3',costMinor:null}));
 assert.equal(plain.expenseId,null);assert.equal(db.store.get(`technicalProblems/${other}`).costMinor,null);
 // A manager without payment rights can fix but not record the expense.
 db.store.set('memberships/boss_o',member('boss','fixer',{roleGrants:{manageProperty:'managed'}}));
 const {problemId:third}=await call(report({operationId:'p5'}));
 await assert.rejects(call(fix(third,{operationId:'f4',recordExpense:true,paymentMethod:'cash'}),'boss'),e=>e.message==='problem_expense_needs_permission'||e.code==='permission-denied');
});

test('input checks',()=>{
 const base={organizationId:'o',buildingId:'b'};
 assert.equal(invalidProblemInput({...base,action:'list'}),null);
 assert.equal(invalidProblemInput({...base,action:'list',status:'x'}),'problem_invalid');
 assert.equal(invalidProblemInput({...base,...report(),title:' '}),'problem_invalid_text');
 assert.equal(invalidProblemInput({...base,...report(),title:'x'.repeat(121)}),'problem_invalid_text');
 assert.equal(invalidProblemInput({...base,...report(),extra:1}),'problem_invalid');
 assert.equal(invalidProblemInput({...base,...fix('p',{costMinor:-1})}),'problem_invalid_cost');
 assert.equal(invalidProblemInput({...base,...fix('p',{paymentMethod:'cash'})}),'problem_invalid_fix');
 assert.equal(invalidProblemInput({...base,...fix('p',{recordExpense:true,paymentMethod:'cash',accountId:'vcb'})}),'problem_invalid_fix');
 assert.equal(invalidProblemInput({...base,...fix('p',{fixedDate:'2026-02-30'})}),'problem_invalid_fix');
});
