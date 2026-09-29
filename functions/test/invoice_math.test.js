const {test}=require('node:test');const assert=require('node:assert/strict');
const {proratedRent}=require('../invoice_math');
const calc=(overrides={})=>proratedRent({tenant:{currency:'VND',monthlyRentMinor:3100000},startDate:'2026-01-01',endDate:'2026-02-01',timeZone:'Asia/Ho_Chi_Minh',intervals:[{startDate:'2026-01-01',endDate:null}],...overrides});
test('calendar-day proration handles leap February, move-out exclusion and rate amendments',()=>{
 assert.equal(calc().amountMinor,3100000);
 assert.equal(calc({intervals:[{startDate:'2026-01-16',endDate:'2026-02-01'}]}).amountMinor,1600000);
 assert.equal(calc({tenant:{currency:'USD',monthlyRentMinor:29000},startDate:'2028-02-01',endDate:'2028-03-01',intervals:[{startDate:'2028-02-01',endDate:'2028-02-16'}]}).amountMinor,15000);
 assert.equal(calc({tenant:{currency:'VND',monthlyRentMinor:3100000,rentSchedule:[{effectiveDate:'2026-01-16',amountMinor:6200000}]}}).amountMinor,4700000);
 assert.equal(calc({intervals:[{startDate:'2026-01-01',endDate:'2026-01-16'},{startDate:'2026-01-16',endDate:'2026-02-01'}]}).amountMinor,3100000);
});
test('round once in minor units; invalid and empty periods fail closed',()=>{
 assert.equal(calc({tenant:{currency:'USD',monthlyRentMinor:100},intervals:[{startDate:'2026-01-01',endDate:'2026-01-03'}]}).amountMinor,6);
 for(const override of [{startDate:'2026-02-30'},{endDate:'2026-01-01'},{endDate:'2028-01-01'},{intervals:[]},{tenant:{currency:'USD',monthlyRentMinor:-1}}])assert.throws(()=>calc(override));
});
