'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {propertyDate,leaseDatePolicy,propertyDayStart}=require('../lease_dates');
test('date-only entry converts to the first real property-local instant, including skipped midnight and skipped days',()=>{
 assert.equal(propertyDayStart('2026-09-27','Asia/Ho_Chi_Minh'),Date.parse('2026-09-26T17:00:00Z'));
 assert.equal(propertyDayStart('2026-03-08','America/Los_Angeles'),Date.parse('2026-03-08T08:00:00Z'));
 assert.equal(propertyDayStart('2026-11-01','America/Los_Angeles'),Date.parse('2026-11-01T07:00:00Z'));
 assert.equal(propertyDayStart('2018-11-04','America/Sao_Paulo'),Date.parse('2018-11-04T03:00:00Z'));
 assert.equal(propertyDayStart('2011-12-30','Pacific/Apia'),null);
 assert.equal(propertyDayStart('2026-02-30','UTC'),null);
});
const nowMillis=Date.parse('2026-09-27T00:30:00Z');
const evaluate=patch=>leaseDatePolicy({moveInMillis:nowMillis,nowMillis,timeZone:'Asia/Ho_Chi_Minh',role:'manager',...patch});
test('property dates use the selected timezone, including midnight and DST boundaries',()=>{
 assert.equal(propertyDate(nowMillis,'America/Los_Angeles'),'2026-09-26');
 assert.equal(propertyDate(nowMillis,'Asia/Ho_Chi_Minh'),'2026-09-27');
 for(const instant of ['2026-03-08T09:59:00Z','2026-03-08T10:01:00Z','2026-11-01T08:30:00Z','2026-11-01T09:30:00Z'])assert.equal(propertyDate(Date.parse(instant),'America/Los_Angeles'),instant.slice(0,10));
 assert.equal(propertyDate(NaN,'UTC'),null);
 assert.equal(propertyDate(nowMillis,'Invalid/Timezone'),null);
});
test('managers may use today and future dates, but only owners/admins may backdate with a reason',()=>{
 const past=Date.parse('2026-09-25T17:00:00Z');
 assert.equal(evaluate({moveInMillis:Date.parse('2026-09-26T17:00:00Z')}).localDate,'2026-09-27');
 assert.equal(evaluate({moveInMillis:Date.parse('2026-09-28T00:00:00Z')}).backdated,false);
 for(const role of ['manager','receptionist','viewer'])assert.equal(evaluate({role,moveInMillis:past,reason:'Import'}).key,'lease_backdate_owner_admin_required');
 for(const role of ['owner','administrator']){
  for(const reason of [undefined,'','   '])assert.equal(evaluate({role,moveInMillis:past,reason}).key,'lease_backdate_reason_required');
  assert.equal(evaluate({role,moveInMillis:past,reason:'  Existing lease  '}).reason,'Existing lease');
 }
 for(const reason of [123,{},'a'.repeat(1001)])assert.equal(evaluate({role:'owner',moveInMillis:past,reason}).key,'lease_backdate_reason_invalid');
});
test('the same instant can be today in one property and yesterday in another',()=>{
 const moveInMillis=Date.parse('2026-09-26T22:00:00Z');
 assert.equal(evaluate({moveInMillis}).backdated,false);
 assert.equal(evaluate({moveInMillis,timeZone:'UTC'}).key,'lease_backdate_owner_admin_required');
 assert.equal(evaluate({timeZone:null}).key,'lease_property_timezone_required');
 assert.equal(evaluate({moveInMillis:Infinity}).key,'booking_invalid_dates');
});
