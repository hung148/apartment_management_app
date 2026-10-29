const {test}=require('node:test'),assert=require('node:assert/strict');
const {planHourlyTemplates}=require('../hourly_migration');
test('each different flat hourly price becomes one template; existing ones are kept',()=>{
 const p=planHourlyTemplates({buildingCurrency:'VND',rooms:[{hourlyPrice:100000},{hourlyPrice:100000},{hourlyPrice:80000},{hourlyPrice:null},{hourlyPrice:50000,deletedAt:1},{hourlyPrice:5,currency:'USD'}],
  existing:[{id:'t',name:'Giờ',currency:'VND',hourPricesMinor:[80000]}]});
 assert.deepEqual(p.add,[{id:'flat_100000',name:'100,000 mỗi giờ',currency:'VND',hourPricesMinor:[100000]}]);
 assert.equal(p.otherCurrencyRooms,1);
});
test('never more than 20 templates; the rest are reported',()=>{
 const rooms=Array.from({length:25},(_,i)=>({hourlyPrice:(i+1)*1000}));
 const p=planHourlyTemplates({buildingCurrency:'VND',rooms,existing:[]});
 assert.equal(p.add.length,20);assert.equal(p.skipped.length,5);
 assert.equal(planHourlyTemplates({buildingCurrency:'USD',rooms:[{hourlyPrice:2.5,currency:'USD'}],existing:[]}).add[0].name,'2.50 USD mỗi giờ');
});
