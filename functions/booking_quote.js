'use strict';
const {validDate}=require('./property_contract');const {validZone}=require('./booking_settings');
function localTime(value,zone,occurrence='first'){
 if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(value)||!validDate(value.slice(0,10))||!validZone(zone)||!['first','second'].includes(occurrence)||Number(value.slice(11,13))>23||Number(value.slice(14))>59)return null;
 const nominal=Date.parse(value.replace(' ','T')+':00Z'),format=new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}),matches=[];
 for(let offset=-840;offset<=840;offset+=15){const instant=nominal-offset*60000,parts=Object.fromEntries(format.formatToParts(new Date(instant)).map(p=>[p.type,p.value]));if(`${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}`===value)matches.push(instant);}
 matches.sort((a,b)=>a-b);return matches.length?matches[occurrence==='second'?matches.length-1:0]:null;
}
function bookingPrice(room,start,end,mode='hourly'){
 const scale=room.currency==='USD'?100:1,duration=end-start;if(!Number.isFinite(duration)||duration<=0||duration>366*86400000)throw Error('booking_invalid_dates');
 let type=mode;if(mode==='hourly'&&room.dailyPrice!=null&&room.dailyPriceThresholdHours!=null&&duration/3600000>=room.dailyPriceThresholdHours)type='daily';
 const rate=room[`${type}Price`],rateMinor=Math.round(rate*scale);if(typeof rate!=='number'||!Number.isFinite(rate)||rate<=0||Math.abs(rate*scale-rateMinor)>1e-6)throw Error('booking_rate_required');
 const totalMinor=type==='hourly'?Math.round(rateMinor*duration/3600000):rateMinor*Math.ceil(duration/86400000);if(!Number.isSafeInteger(totalMinor)||totalMinor<=0||totalMinor>1e12)throw Error('booking_invalid_amount');return {totalMinor,pricingType:type,currency:room.currency??'VND'};
}
module.exports={localTime,bookingPrice};
