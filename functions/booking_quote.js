'use strict';
const {validDate}=require('./property_contract');const {validZone}=require('./booking_settings');
function localTime(value,zone,occurrence='first'){
 if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(value)||!validDate(value.slice(0,10))||!validZone(zone)||!['first','second'].includes(occurrence)||Number(value.slice(11,13))>23||Number(value.slice(14))>59)return null;
 const nominal=Date.parse(value.replace(' ','T')+':00Z'),format=new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}),matches=[];
 for(let offset=-840;offset<=840;offset+=15){const instant=nominal-offset*60000,parts=Object.fromEntries(format.formatToParts(new Date(instant)).map(p=>[p.type,p.value]));if(`${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}`===value)matches.push(instant);}
 matches.sort((a,b)=>a-b);return matches.length?matches[occurrence==='second'?matches.length-1:0]:null;
}
// Midnight UTC of the property-local calendar date of an instant.
function localDate(instant,zone){const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(instant)).map(x=>[x.type,x.value]));return Date.UTC(+p.year,+p.month-1,+p.day);}
// Nights between the property-local check-in and check-out dates (B2): 14:00 → 12:00 next day is one night.
function nightCount(start,end,zone){if(!validZone(zone)||!Number.isFinite(start)||!Number.isFinite(end)||end<=start)return 0;return Math.round((localDate(end,zone)-localDate(start,zone))/86400000);}
// options.zone: property time zone (needed for 'nightly'). options.nightPricesMinor: one price per night (custom prices).
// options.hourlyPriceMinor (2026-10-03): price per hour; hours × price, never switched to a day price.
function bookingPrice(room,start,end,mode='hourly',{zone,nightPricesMinor,hourlyPriceMinor}={}){
 const scale=room.currency==='USD'?100:1,duration=end-start;if(!Number.isFinite(duration)||duration<=0||duration>366*86400000)throw Error('booking_invalid_dates');
 if(mode==='nightly'){
  const nights=nightCount(start,end,zone);if(nights<1||nights>366)throw Error('booking_invalid_dates');
  let list=nightPricesMinor;
  if(list==null){const rate=room.nightlyPrice??room.dailyPrice,m=Math.round(rate*scale);if(typeof rate!=='number'||!Number.isFinite(rate)||rate<=0||Math.abs(rate*scale-m)>1e-6)throw Error('booking_rate_required');list=Array(nights).fill(m);}
  else if(!Array.isArray(list)||list.length!==nights||list.some(v=>!Number.isSafeInteger(v)||v<=0||v>1e12))throw Error('booking_night_prices_invalid');
  const totalMinor=list.reduce((a,b)=>a+b,0);if(!Number.isSafeInteger(totalMinor)||totalMinor>1e12)throw Error('booking_invalid_amount');
  return {totalMinor,pricingType:'nightly',currency:room.currency??'VND',nights,nightPricesMinor:[...list]};
 }
 if(mode==='hourly'&&hourlyPriceMinor!=null){
  if(!Number.isSafeInteger(hourlyPriceMinor)||hourlyPriceMinor<=0||hourlyPriceMinor>1e12)throw Error('booking_invalid_amount');
  const totalMinor=Math.round(hourlyPriceMinor*duration/3600000);if(!Number.isSafeInteger(totalMinor)||totalMinor<=0||totalMinor>1e12)throw Error('booking_invalid_amount');
  return {totalMinor,pricingType:'hourly',currency:room.currency??'VND',hourlyPriceMinor};
 }
 let type=mode;if(mode==='hourly'&&room.dailyPrice!=null&&room.dailyPriceThresholdHours!=null&&duration/3600000>=room.dailyPriceThresholdHours)type='daily';
 const rate=room[`${type}Price`],rateMinor=Math.round(rate*scale);if(typeof rate!=='number'||!Number.isFinite(rate)||rate<=0||Math.abs(rate*scale-rateMinor)>1e-6)throw Error('booking_rate_required');
 const totalMinor=type==='hourly'?Math.round(rateMinor*duration/3600000):rateMinor*Math.ceil(duration/86400000);if(!Number.isSafeInteger(totalMinor)||totalMinor<=0||totalMinor>1e12)throw Error('booking_invalid_amount');return {totalMinor,pricingType:type,currency:room.currency??'VND'};
}
module.exports={localTime,bookingPrice,nightCount};
