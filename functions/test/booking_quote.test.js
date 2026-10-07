const {test}=require('node:test');const assert=require('node:assert/strict');const {localTime,bookingPrice}=require('../booking_quote');
test('property-local booking times reject skipped hours and select repeated hours explicitly',()=>{
 assert.equal(localTime('2026-03-08 02:30','America/New_York'),null);
 const first=localTime('2026-11-01 01:30','America/New_York','first'),second=localTime('2026-11-01 01:30','America/New_York','second');assert.equal(second-first,3600000);
 assert.equal(localTime('2026-09-27 09:00','Asia/Ho_Chi_Minh'),Date.parse('2026-09-27T02:00:00Z'));assert.equal(localTime('2026-02-30 09:00','UTC'),null);
});
test('server booking prices use exact minor units and daily blocks across long stays',()=>{
 const r={currency:'USD',hourlyPrice:10.01,dailyPrice:40,overnightPrice:30,dailyPriceThresholdHours:5};
 assert.equal(bookingPrice(r,0,90*60000,'hourly').totalMinor,1502);assert.equal(bookingPrice(r,0,6*3600000,'hourly').totalMinor,4000);assert.equal(bookingPrice(r,0,25*3600000,'daily').totalMinor,8000);assert.equal(bookingPrice(r,0,25*3600000,'overnight').totalMinor,6000);assert.throws(()=>bookingPrice(r,1,0));
});

test('a given hourly price: hours × price, rounded, never a day price',()=>{
  const {bookingPrice}=require('../booking_quote');
  const room={hourlyPrice:100000,dailyPrice:500000,dailyPriceThresholdHours:6,currency:'VND'};
  const h=3600000;
  assert.deepEqual(bookingPrice(room,0,10*h,'hourly',{hourlyPriceMinor:70000}),{totalMinor:700000,pricingType:'hourly',currency:'VND',hourlyPriceMinor:70000});
  assert.equal(bookingPrice(room,0,1.5*h,'hourly',{hourlyPriceMinor:100001}).totalMinor,150002);
  assert.throws(()=>bookingPrice(room,0,h,'hourly',{hourlyPriceMinor:-1}),/booking_invalid_amount/);
  assert.equal(bookingPrice(room,0,10*h,'hourly').pricingType,'daily');
});
