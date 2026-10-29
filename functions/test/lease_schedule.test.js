'use strict';
// Bảng thanh toán theo kỳ (PAYMENT_SCHEDULE.md, Tom 2026-10-26): the rules.
const test=require('node:test'),assert=require('node:assert/strict');
const {buildSchedule,toStored,applyChange,checkResult}=require('../lease_schedule');
const zone='Asia/Ho_Chi_Minh';
const lease=(over={})=>({currency:'VND',monthlyRentMinor:10000000,periodRentMinor:10000000,paymentPeriodMonths:1,
 moveInLocalDate:'2026-10-25',contractEndLocalDate:'2027-04-25',surcharges:[{id:'s1',label:'Rác',amountMinor:100000,basis:'room',frequency:'period'}],...over});
const intervals=t=>[{roomId:'r',startDate:t.moveInLocalDate,endDate:null}];
const build=(t,stored,invoices=[])=>buildSchedule({t,zone,stored,invoices,people:1,intervals:intervals(t)});
const range=rows=>rows.map(r=>`${r.start}..${r.end}`);
// One change, the way the server does it: apply, store, rebuild, check.
function change(t,stored,c,invoices=[]){
 const before=build(t,stored,invoices);
 const {rows,removed}=applyChange(before.rows,c,{window:before.window,by:'u',at:'now'});
 const next=toStored(rows),after=build(t,next,invoices);
 checkResult(before.rows,after.rows,removed);
 return {stored:next,rows:after.rows};
}

test('six monthly kỳ from move-in to the contract end, rent + recurring phụ thu',()=>{
 const {rows}=build(lease());
 assert.deepEqual(range(rows),['2026-10-25..2026-11-25','2026-11-25..2026-12-25','2026-12-25..2027-01-25','2027-01-25..2027-02-25','2027-02-25..2027-03-25','2027-03-25..2027-04-25']);
 assert.ok(rows.every(r=>r.amountMinor===10100000&&r.due===r.start&&r.paidMinor===0&&r.leftMinor===10100000&&r.wholeMonths===1));
});

test('one-time phụ thu only in Kỳ 1; per person counts people',()=>{
 const t=lease({surcharges:[{id:'o',label:'Phí vào',amountMinor:500000,basis:'room',frequency:'once'},{id:'p',label:'Nước',amountMinor:50000,basis:'person',frequency:'period'}]});
 const {rows}=buildSchedule({t,zone,people:3,intervals:intervals(t)});
 assert.equal(rows[0].amountMinor,10000000+500000+150000);
 assert.equal(rows[1].amountMinor,10000000+150000);
});

test('the contract ends inside a kỳ: the last kỳ is shorter and prorated',()=>{
 const t=lease({paymentPeriodMonths:3,periodRentMinor:30000000,contractEndLocalDate:'2027-02-25',surcharges:[]});
 const {rows}=build(t);
 assert.deepEqual(range(rows),['2026-10-25..2027-01-25','2027-01-25..2027-02-25']);
 assert.equal(rows[0].amountMinor,30000000);
 assert.equal(rows[1].amountMinor,10000000);
 assert.equal(rows[1].wholeMonths,1);
});

test('the end date is the day the tenant leaves: one year = exactly 12 kỳ',()=>{
 const {rows}=build(lease({moveInLocalDate:'2026-10-27',contractEndLocalDate:'2027-10-27'}));
 assert.equal(rows.length,12);assert.equal(rows.at(-1).end,'2027-10-27');
});

test('no contract end date: the table asks for one',()=>{
 const r=build(lease({contractEndLocalDate:null}));
 assert.equal(r.needsEnd,true);assert.deepEqual(r.rows,[]);
});

test('a shorter kỳ moves the later ones earlier (whole months) and one is added at the end',()=>{
 const {rows}=change(lease(),null,{op:'edit',rowId:'k20261125',end:'2026-12-20'});
 assert.deepEqual(range(rows),['2026-10-25..2026-11-25','2026-11-25..2026-12-20','2026-12-20..2027-01-20','2027-01-20..2027-02-20','2027-02-20..2027-03-20','2027-03-20..2027-04-20','2027-04-20..2027-04-25']);
 assert.equal(rows[1].datesEdited,true);
 assert.equal(rows.at(-1).days,5);
});

test('changing Kỳ 3 start moves the line with Kỳ 2; Kỳ 3 and later shift',()=>{
 const {rows}=change(lease(),null,{op:'edit',rowId:'k20261225',start:'2026-12-28'});
 assert.equal(rows[1].end,'2026-12-28');assert.equal(rows[1].datesEdited,true);
 assert.equal(rows[2].start,'2026-12-28');assert.equal(rows[2].end,'2027-01-28');
});

test('Kỳ 1 may start after move-in (days before are not billed), never before',()=>{
 const {rows}=change(lease(),null,{op:'edit',rowId:'k20261025',start:'2026-10-28'});
 assert.equal(rows[0].start,'2026-10-28');assert.equal(rows[0].end,'2026-11-28');
 assert.throws(()=>change(lease(),null,{op:'edit',rowId:'k20261025',start:'2026-10-20'}),/schedule_before_move_in/);
});

test('an invoiced kỳ is locked and can never be moved by another change',()=>{
 const inv=[{id:'inv2',startDate:'2026-11-25',endDate:'2026-12-25',totalMinor:10250000,paidMinor:5000000}];
 const {rows}=build(lease(),null,inv);
 assert.equal(rows[1].locked,true);assert.equal(rows[1].amountMinor,10250000);assert.equal(rows[1].leftMinor,5250000);
 assert.throws(()=>change(lease(),null,{op:'edit',rowId:'k20261125',end:'2026-12-20'},inv),/schedule_row_locked/);
 assert.throws(()=>change(lease(),null,{op:'edit',rowId:'k20261025',end:'2026-11-20'},inv),/schedule_moves_locked/);
 // Kỳ 3's start is Kỳ 2's end: refused as well.
 assert.throws(()=>change(lease(),null,{op:'edit',rowId:'k20261225',start:'2026-12-28'},inv),/schedule_row_locked/);
});

test('pushing a hand-edited kỳ past the contract end is refused',()=>{
 const first=change(lease(),null,{op:'edit',rowId:'k20270325',end:'2027-04-20'});
 assert.equal(first.rows.at(-1).start,'2027-04-20');
 assert.throws(()=>change(lease(),first.stored,{op:'edit',rowId:'k20261025',end:'2026-12-01'}),/schedule_past_contract_end/);
 assert.throws(()=>change(lease(),null,{op:'edit',rowId:'k20270325',end:'2027-05-10'}),/schedule_past_contract_end/);
});

test('amount: another amount needs a reason; the calculated amount clears the edit',()=>{
 assert.throws(()=>change(lease(),null,{op:'edit',rowId:'k20261025',amountMinor:9000000}),/schedule_reason_required/);
 assert.throws(()=>change(lease(),null,{op:'edit',rowId:'k20261025',amountMinor:100000,reason:'x'}),/schedule_amount_below_surcharges/);
 const a=change(lease(),null,{op:'edit',rowId:'k20261025',amountMinor:9000000,reason:'Giảm tháng đầu'});
 assert.equal(a.rows[0].amountMinor,9000000);assert.equal(a.rows[0].rentMinor,8900000);assert.equal(a.rows[0].reason,'Giảm tháng đầu');
 const b=change(lease(),a.stored,{op:'edit',rowId:'k20261025',amountMinor:10100000});
 assert.equal(b.rows[0].amountEdited,false);
});

test('a rent change recalculates kỳ nobody edited; hand-set amounts stay',()=>{
 const a=change(lease(),null,{op:'edit',rowId:'k20261025',amountMinor:9000000,reason:'Giảm'});
 const t=lease({monthlyRentMinor:12000000,periodRentMinor:12000000});
 const {rows}=build(t,a.stored);
 assert.equal(rows[0].amountMinor,9000000);assert.equal(rows[1].amountMinor,12100000);
});

test('Hạn thu: a hand-set due day keeps its distance when the kỳ moves; otherwise the first day',()=>{
 const a=change(lease(),null,{op:'edit',rowId:'k20261125',due:'2026-11-30'});
 assert.equal(a.rows[1].due,'2026-11-30');
 const b=change(lease(),a.stored,{op:'edit',rowId:'k20261025',end:'2026-11-22'});
 assert.equal(b.rows[1].start,'2026-11-22');assert.equal(b.rows[1].due,'2026-11-27');assert.equal(b.rows[2].due,b.rows[2].start);
 assert.throws(()=>change(lease(),null,{op:'edit',rowId:'k20261125',due:'2026-12-26'}),/schedule_due_outside/);
 // Old leases with a due day of the month keep it for kỳ nobody edited.
 assert.equal(build(lease({paymentDueDay:5})).rows[0].due,'2026-10-25');
 assert.equal(build(lease({paymentDueDay:28})).rows[0].due,'2026-10-28');
});

test('Thêm splits a kỳ; Xóa joins it into the one before (Kỳ 1 into Kỳ 2)',()=>{
 const a=change(lease(),null,{op:'split',rowId:'k20261025',date:'2026-11-10'});
 assert.deepEqual(range(a.rows).slice(0,3),['2026-10-25..2026-11-10','2026-11-10..2026-11-25','2026-11-25..2026-12-25']);
 assert.equal(a.rows.length,7);
 const b=change(lease(),a.stored,{op:'merge',rowId:a.rows[1].id});
 assert.deepEqual(range(b.rows).slice(0,2),['2026-10-25..2026-11-25','2026-11-25..2026-12-25']);
 const c=change(lease(),null,{op:'merge',rowId:'k20261025'});
 assert.equal(c.rows[0].start,'2026-10-25');assert.equal(c.rows[0].end,'2026-12-25');assert.equal(c.rows.length,5);
 assert.throws(()=>change(lease(),null,{op:'split',rowId:'k20261025',date:'2026-11-25'}),/schedule_split_outside/);
 const inv=[{id:'i1',startDate:'2026-10-25',endDate:'2026-11-25',totalMinor:1,paidMinor:0}];
 assert.throws(()=>change(lease(),null,{op:'merge',rowId:'k20261125'},inv),/schedule_row_locked/);
});

test('a split hand-set amount is shared by days',()=>{
 const a=change(lease(),null,{op:'edit',rowId:'k20261025',amountMinor:9300000,reason:'Giảm'});
 const b=change(lease(),a.stored,{op:'split',rowId:'k20261025',date:'2026-11-04'});
 assert.equal(b.rows[0].amountMinor+b.rows[1].amountMinor,9300000);
 assert.equal(b.rows[0].amountMinor,3000000);
});

test('Trả phòng cuts the table at the move-out day',()=>{
 const t=lease({moveOutDate:{toMillis:()=>Date.parse('2026-12-09T17:00:00Z')}}); // 10/12 local
 const {rows}=build(t);
 assert.deepEqual(range(rows),['2026-10-25..2026-11-25','2026-11-25..2026-12-10']);
});

test('old invoices: same dates lock the kỳ even after the table was saved; others are listed',()=>{
 const inv=[{id:'old1',startDate:'2026-10-25',endDate:'2026-11-25',totalMinor:10100000,paidMinor:10100000},{id:'odd',startDate:'2026-10-26',endDate:'2026-11-26',totalMinor:1,paidMinor:0}];
 const r=build(lease(),null,inv);
 assert.equal(r.rows[0].locked,true);assert.deepEqual(r.unmatched,['odd']);
 const a=change(lease(),null,{op:'edit',rowId:'k20261225',end:'2027-01-20'},inv);
 assert.equal(a.rows[0].locked,true);
});
