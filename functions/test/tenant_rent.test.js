const {test}=require('node:test');
const assert=require('node:assert/strict');
const {rentPlan,rentForDate}=require('../tenant_rent');
test('rent selects the latest effective date and preserves original rent before changes',()=>{
 const t={currency:'USD',monthlyRent:123.45,rentSchedule:[{effectiveDate:'2030-01-01',amountMinor:15000},{effectiveDate:'2030-03-01',amountMinor:17500}]};
 assert.equal(rentForDate(t,'2029-12-31'),12345);assert.equal(rentForDate(t,'2030-01-01'),15000);assert.equal(rentForDate(t,'2030-02-28'),15000);assert.equal(rentForDate(t,'2030-03-01'),17500);assert.equal(t.monthlyRent,123.45);
 assert.equal(rentPlan({...t,monthlyRent:1.234}),null);assert.equal(rentPlan({...t,rentSchedule:[...t.rentSchedule].reverse()}),null);assert.equal(rentForDate(t,'2030-02-30'),null);assert.equal(rentPlan({...t,currency:'EUR'}),null);
});
