const {test}=require('node:test'),assert=require('node:assert/strict');
const {utilityCharge,meterUsage,validateTariff}=require('../utility_math');
const flat=(priceMinor,currency='VND')=>({currency,bands:[{throughMilli:null,priceMinor}]});
test('utility amounts use exact integer arithmetic and round once',()=>{
 assert.equal(utilityCharge(1250,flat(3500)).amountMinor,4375);
 assert.equal(utilityCharge(500,flat(25,'USD')).amountMinor,13);
 assert.equal(utilityCharge(0,flat(3500)).amountMinor,0);
 assert.equal(utilityCharge(1234,flat(0)).amountMinor,0);
});
test('tier boundaries charge only their measured portion',()=>{
 const tariff={currency:'VND',bands:[{throughMilli:50000,priceMinor:1800},{throughMilli:100000,priceMinor:2000},{throughMilli:null,priceMinor:2500}]};
 assert.equal(utilityCharge(50000,tariff).amountMinor,90000);
 assert.equal(utilityCharge(125000,tariff).amountMinor,252500);
 assert.deepEqual(utilityCharge(125000,tariff).lines.map(x=>x.quantityMilli),[50000,50000,25000]);
});
test('reset includes the old meter remainder and new meter consumption',()=>{
 assert.equal(meterUsage(90000,120000),30000);
 assert.equal(meterUsage(90000,12000,{oldFinalMilli:95000,newStartMilli:2000}),15000);
 assert.throws(()=>meterUsage(90000,12000),/decreased/);
 assert.throws(()=>meterUsage(90000,12000,{oldFinalMilli:80000,newStartMilli:0}),/invalid_reset/);
 assert.throws(()=>meterUsage(1,2,{newStartMilli:0}),/invalid_reset/);
});
test('invalid bands, unsupported currencies, unsafe quantities and totals are rejected',()=>{
 for(const value of [-1,0.5,NaN,Infinity,Number.MAX_SAFE_INTEGER])assert.throws(()=>utilityCharge(value,flat(1)));
 for(const tariff of [flat(-1),flat(1,'EUR'),{currency:'VND',bands:[]},{currency:'VND',bands:[{throughMilli:1000,priceMinor:1}]},{currency:'VND',bands:[{throughMilli:1000,priceMinor:1},{throughMilli:500,priceMinor:2},{throughMilli:null,priceMinor:3}]}])assert.throws(()=>validateTariff(tariff));
 assert.throws(()=>utilityCharge(1e12,flat(1e12)),/too_large/);
});
