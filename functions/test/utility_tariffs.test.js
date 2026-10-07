const {test}=require('node:test'),assert=require('node:assert/strict');
const {addTariff,resolveTariff}=require('../utility_tariffs');
const price=n=>({currency:'VND',bands:[{throughMilli:null,priceMinor:n}]});
const change=(date,n)=>({effectiveDate:date,tariff:n===null?null:price(n)});
test('property defaults, room overrides and return to default are dated',()=>{
 const property=[change('2026-01-01',3000),change('2026-03-01',4000)];
 const room=[change('2026-02-01',3500),change('2026-04-01',null)];
 assert.equal(resolveTariff(room,property,'2026-01-01','2026-02-01','VND').bands[0].priceMinor,3000);
 assert.equal(resolveTariff(room,property,'2026-02-01','2026-04-01','VND').bands[0].priceMinor,3500);
 assert.equal(resolveTariff(room,property,'2026-04-01','2026-05-01','VND').bands[0].priceMinor,4000);
});
test('mid-interval price changes require a measured boundary; boundary end uses old price',()=>{
 const property=[change('2026-01-01',3000),change('2026-02-15',4000)];
 assert.throws(()=>resolveTariff([],property,'2026-02-01','2026-03-01','VND'),/boundary_required/);
 assert.equal(resolveTariff([],property,'2026-02-01','2026-02-15','VND').bands[0].priceMinor,3000);
 assert.throws(()=>resolveTariff([],property,'2025-12-01','2026-01-01','VND'),/tariff_required/);
 assert.throws(()=>resolveTariff([],property,'2026-01-01','2026-02-01','USD'),/tariff_required/);
});
test('tariff history rejects duplicate dates, invalid dates and retroactive room changes',()=>{
 const rows=addTariff([],change('2026-01-01',3000));
 assert.throws(()=>addTariff(rows,change('2026-01-01',4000)),/date_exists/);
 assert.throws(()=>addTariff(rows,change('2026-02-30',4000)),/invalid_tariff_date/);
 assert.throws(()=>addTariff(rows,change('2026-02-01',4000),'2026-03-01'),/past_reading/);
 assert.equal(rows[0].tariff.bands[0].priceMinor,3000);
});
