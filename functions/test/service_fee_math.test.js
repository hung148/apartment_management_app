const {test}=require('node:test'),assert=require('node:assert/strict');
const {validateRule,validateVersion,validateOverride,addDated,resolveFee,resolvePeriod,serviceCharge}=require('../service_fee_math');
const v=(o={})=>({effectiveDate:'2026-09-01',active:true,rateMinor:100000,rule:{mode:'days'},includedPeople:0,roundingMinor:0,...o});
const terms=o=>({...v(o),roomRate:false});
const main={id:'t',name:'Chinh',isMain:true,intervals:[{startDate:'2026-01-01',endDate:null}]};
const mate=(id,startDate,endDate=null,name=id)=>({id,name,isMain:false,intervals:[{startDate,endDate}]});
const charge=(o,people=[main],extra={})=>serviceCharge({basis:'person',terms:terms(o),startDate:'2026-09-01',endDate:'2026-10-01',people,currency:'VND',...extra});

test('rules: days, thresholds with increasing steps, check date; anything else is refused',()=>{
 assert.ok(validateRule({mode:'days'}));assert.ok(validateRule({mode:'checkDate',day:'last'}));
 assert.ok(validateRule({mode:'thresholds',steps:[{minDays:1,percent:50},{minDays:15,percent:100}]}));
 for(const bad of [null,{mode:'x'},{mode:'days',day:'first'},{mode:'checkDate',day:'middle'},{mode:'thresholds',steps:[]},
  {mode:'thresholds',steps:[{minDays:15,percent:100},{minDays:1,percent:50}]},{mode:'thresholds',steps:[{minDays:1,percent:60},{minDays:15,percent:50}]},
  {mode:'thresholds',steps:[{minDays:0,percent:50}]},{mode:'thresholds',steps:[{minDays:1,percent:101}]},{mode:'thresholds',steps:[{minDays:1,percent:50,extra:1}]},
  {mode:'thresholds',steps:Array.from({length:7},(_,i)=>({minDays:i+1,percent:i+1}))}])assert.throws(()=>validateRule(bad),/service_invalid_rule/);
});
test('versions: basis decides the allowed fields; inactive versions carry only a date',()=>{
 assert.deepEqual(validateVersion({effectiveDate:'2026-09-01',active:false},'person'),{effectiveDate:'2026-09-01',active:false});
 assert.equal(validateVersion(v({rule:null}),'quantity').rule,null);
 for(const [version,basis] of [[v({includedPeople:1}),'room'],[v(),'quantity'],[v({rule:null}),'person'],[v({rateMinor:-1}),'person'],[v({rateMinor:1.5}),'person'],
  [v({effectiveDate:'2026-02-30'}),'person'],[{...v(),extra:1},'person'],[{effectiveDate:'2026-09-01',active:false,rateMinor:1},'person'],[v(),'monthly']])
  assert.throws(()=>validateVersion(version,basis),/service_invalid_(fee|rule)/);
 assert.throws(()=>validateOverride({effectiveDate:'2026-09-01',mode:'off',rateMinor:1}),/service_invalid_override/);
 assert.throws(()=>validateOverride({effectiveDate:'2026-09-01',mode:'rate'}),/service_invalid_override/);
});
test('dated history: unique dates, sorted, never before what was billed',()=>{
 const h=addDated([{effectiveDate:'2026-10-01'}],{effectiveDate:'2026-09-01'},null);assert.deepEqual(h.map(x=>x.effectiveDate),['2026-09-01','2026-10-01']);
 assert.throws(()=>addDated(h,{effectiveDate:'2026-09-01'},null),/date_exists/);
 assert.throws(()=>addDated(h,{effectiveDate:'2026-09-15'},'2026-10-01'),/past_billed/);
 assert.doesNotThrow(()=>addDated(h,{effectiveDate:'2026-10-02'},'2026-10-01'));
});
test('room overrides change the rate, turn the fee off or return to the default',()=>{
 const fee={versions:[v()]};
 assert.equal(resolveFee(fee,[{effectiveDate:'2026-09-01',mode:'rate',rateMinor:70000}],'2026-09-10').rateMinor,70000);
 assert.equal(resolveFee(fee,[{effectiveDate:'2026-09-01',mode:'off'}],'2026-09-10'),null);
 assert.equal(resolveFee(fee,[{effectiveDate:'2026-09-01',mode:'off'},{effectiveDate:'2026-09-05',mode:'inherit'}],'2026-09-10').rateMinor,100000);
 assert.equal(resolveFee({versions:[v(),{effectiveDate:'2026-09-20',active:false}]},[],'2026-09-25'),null);
 assert.equal(resolveFee(fee,[],'2026-08-31'),null);
});
test('a price change inside the period needs separate invoices; an unchanged re-statement does not',()=>{
 const fee={versions:[v(),v({effectiveDate:'2026-09-15',rateMinor:120000})]};
 assert.throws(()=>resolvePeriod(fee,[],'2026-09-01','2026-10-01'),/boundary_required/);
 assert.equal(resolvePeriod(fee,[],'2026-09-15','2026-10-01').rateMinor,120000);
 assert.equal(resolvePeriod({versions:[v(),v({effectiveDate:'2026-09-15'})]},[],'2026-09-01','2026-10-01').rateMinor,100000);
 assert.throws(()=>resolvePeriod(fee,[],'2026-08-01','2026-08-31'),/not_in_force/);
 assert.throws(()=>resolvePeriod(fee,[{effectiveDate:'2026-09-10',mode:'off'}],'2026-09-01','2026-09-14'),/boundary_required/);
});
test('by days: a roommate who moved in on day 21 of 30 pays 10/30; the lease pays in full',()=>{
 const c=charge({},[main,mate('m','2026-09-21',null,'Dung')]);
 assert.deepEqual(c.lines.map(l=>[l.name,l.days,l.amountMinor]),[['Chinh',30,100000],['Dung',10,33333]]);
 assert.equal(c.amountMinor,133333);assert.equal(c.periodDays,30);
});
test('by thresholds: any-day, over-15 and half/full presets',()=>{
 const people=[main,mate('a','2026-09-21'),mate('b','2026-09-10')];// a: 10 days, b: 21 days
 const any=charge({rule:{mode:'thresholds',steps:[{minDays:1,percent:100}]}},people).lines.map(l=>l.amountMinor);
 assert.deepEqual(any,[100000,100000,100000]);
 const over15=charge({rule:{mode:'thresholds',steps:[{minDays:15,percent:100}]}},people);
 assert.deepEqual(over15.lines.map(l=>[l.tenantId,l.amountMinor]),[['t',100000],['b',100000],['a',0]]);
 const half=charge({rule:{mode:'thresholds',steps:[{minDays:1,percent:50},{minDays:15,percent:100}]}},people).lines.map(l=>l.amountMinor);
 assert.deepEqual(half,[100000,100000,50000]);
});
test('a person present for the whole period always gets the full share, even when the period is shorter than a threshold',()=>{
 // Prices are per month: a 10-day invoice is 10/30 of September.
 const c=serviceCharge({basis:'person',terms:terms({rule:{mode:'thresholds',steps:[{minDays:15,percent:100}]}}),startDate:'2026-09-01',endDate:'2026-09-11',people:[main],currency:'VND'});
 assert.equal(c.amountMinor,33333);
});
test('prices are per month: a whole 3-month lease period charges three months; partial months by days',()=>{
 const {monthsBetween}=require('../service_fee_math');
 assert.deepEqual(monthsBetween('2026-10-01','2026-11-01'),[1n,1n]);
 assert.deepEqual(monthsBetween('2026-10-02','2027-01-02'),[3n,1n]);
 assert.deepEqual(monthsBetween('2026-10-01','2026-10-15'),[14n,31n]);
 assert.deepEqual(monthsBetween('2026-01-31','2026-02-28'),[1n,1n]);
 const lease={...main,intervals:[{startDate:'2026-10-02',endDate:null}]};
 const c=serviceCharge({basis:'person',terms:terms(),startDate:'2026-10-02',endDate:'2027-01-02',people:[lease,mate('m','2026-12-02')],currency:'VND'});
 // Lease: 3 months. Roommate: 31 of 92 days of a 3-month period → 31/92 × 3 months.
 assert.deepEqual(c.lines.map(l=>l.amountMinor),[300000,101087]);
});
test('by check date: only people living there on the first (or last) day count',()=>{
 const people=[main,mate('in','2026-09-21'),mate('out','2026-08-01','2026-09-15')];
 assert.deepEqual(charge({rule:{mode:'checkDate',day:'first'}},people).lines.map(l=>[l.tenantId,l.amountMinor]),[['t',100000],['out',100000],['in',0]]);
 assert.deepEqual(charge({rule:{mode:'checkDate',day:'last'}},people).lines.map(l=>[l.tenantId,l.amountMinor]),[['t',100000],['out',0],['in',100000]]);
});
test('people included free: the earliest N people by move-in are free; rounding applies per line',()=>{
 const people=[main,mate('m1','2026-09-01',null,'An'),mate('m2','2026-09-21',null,'Binh')];
 const c=charge({includedPeople:2,roundingMinor:1000},people);
 assert.deepEqual(c.lines.map(l=>[l.tenantId,l.free,l.amountMinor]),[['t',true,0],['m1',true,0],['m2',false,33000]]);
 assert.equal(c.amountMinor,33000);
 assert.throws(()=>charge({includedPeople:5},people),/no_billable_charge/);
});
test('room basis charges the lease once, prorated by the lease days',()=>{
 const lease={...main,intervals:[{startDate:'2026-09-16',endDate:null}]};
 const c=serviceCharge({basis:'room',terms:terms(),startDate:'2026-09-01',endDate:'2026-10-01',people:[lease,mate('m','2026-09-16')],currency:'VND'});
 assert.deepEqual(c.lines.map(l=>[l.tenantId,l.days,l.amountMinor]),[['t',15,50000]]);
});
test('roommates count only on days the lease is in the room; no lease days means no charge',()=>{
 const lease={...main,intervals:[{startDate:'2026-09-01',endDate:'2026-09-11'}]};
 const c=charge({},[lease,mate('m','2026-09-01')]);assert.deepEqual(c.lines.map(l=>l.days),[10,10]);
 assert.throws(()=>charge({},[{...main,intervals:[{startDate:'2026-10-05',endDate:null}]}]),/tenant_not_in_room/);
 assert.throws(()=>charge({},[mate('m','2026-09-01')]),/tenant_not_in_room/);
});
test('quantity basis: rate × quantity with three decimals, rounded half up',()=>{
 const c=serviceCharge({basis:'quantity',terms:terms({rule:null,rateMinor:15000}),startDate:'2026-09-05',endDate:'2026-09-06',people:[main],quantityMilli:2500,currency:'VND'});
 assert.equal(c.amountMinor,37500);assert.equal(c.lines[0].quantityMilli,2500);
 assert.throws(()=>serviceCharge({basis:'quantity',terms:terms({rule:null}),startDate:'2026-09-05',endDate:'2026-09-06',people:[main],quantityMilli:0,currency:'VND'}),/invalid_quantity/);
});
test('periods must be ordered and at most 366 days',()=>{
 for(const [startDate,endDate] of [['2026-09-02','2026-09-01'],['2026-01-01','2027-01-03'],['2026-02-30','2026-03-01']])
  assert.throws(()=>serviceCharge({basis:'person',terms:terms(),startDate,endDate,people:[main],currency:'VND'}),/invalid_period/);
});
