'use strict';
const {rentForDate}=require('./tenant_rent');
const {validDate}=require('./property_contract');
const {propertyDate,propertyDayStart}=require('./lease_dates');
const nextDate=d=>new Date(Date.parse(d+'T00:00:00Z')+86400000).toISOString().slice(0,10);
const monthDays=d=>new Date(Date.UTC(Number(d.slice(0,4)),Number(d.slice(5,7)),0)).getUTCDate();
function proratedRent({tenant,startDate,endDate,intervals,timeZone}){
 if(!validDate(startDate)||!validDate(endDate)||endDate<=startDate||(Date.parse(endDate)-Date.parse(startDate))/86400000>366)throw Error('invoice_invalid_period');
 let numerator=0n,denominator=1n,days=0;const lines=[];
 for(let day=startDate;day<endDate;day=nextDate(day)){
  // Effective dates are calendar dates. A departure at local midnight does not charge that date.
  if(!intervals.some(i=>day>=i.startDate&&(i.endDate==null||day<i.endDate)))continue;
  const midnight=propertyDayStart(day,timeZone);if(midnight===null)continue;
  const rateDate=tenant.rentTimeZone?propertyDate(midnight,tenant.rentTimeZone):day;const minor=rentForDate(tenant,rateDate);if(minor===null)throw Error('invoice_invalid_rent');
  const count=monthDays(day),divisor=BigInt(count);numerator=numerator*divisor+BigInt(minor)*denominator;denominator*=divisor;
  const gcd=(a,b)=>b===0n?a:gcd(b,a%b),common=gcd(numerator,denominator);numerator/=common;denominator/=common;days++;
  const previous=lines.at(-1);if(previous&&previous.rateMinor===minor&&previous.monthDays===count&&previous.endDate===day)previous.endDate=nextDate(day);else lines.push({startDate:day,endDate:nextDate(day),rateMinor:minor,monthDays:count});
 }
 const amountMinor=Number((numerator+denominator/2n)/denominator);if(!Number.isSafeInteger(amountMinor)||amountMinor<=0||amountMinor>1e12)throw Error('invoice_empty_or_invalid_total');
 return {amountMinor,days,lines,timeZone,startDate,endDate};
}
module.exports={proratedRent,nextDate,monthDays};
