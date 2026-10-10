'use strict';
const {validZone}=require('./booking_settings');
const dateFormatter=timeZone=>new Intl.DateTimeFormat('en',{timeZone,year:'numeric',month:'2-digit',day:'2-digit',era:'short'});
function formattedDate(instant,formatter){
 const p=Object.fromEntries(formatter.formatToParts(instant).map(v=>[v.type,v.value]));
 if(p.era!=='AD'||Number(p.year)>9999)return null;
 return `${p.year.padStart(4,'0')}-${p.month}-${p.day}`;
}

// Calendar dates are derived on the server in the property's timezone. Neither
// a client-supplied "today" nor the server host's local timezone participates.
function propertyDate(instant,timeZone){
 if(!Number.isFinite(instant)||!validZone(timeZone))return null;
 try{
  return formattedDate(instant,dateFormatter(timeZone));
 }catch{return null;}
}

// canBackdate: the member's backdateRecords permission. `role` is the older form
// (owner/administrator only) kept for callers that have no membership.
function leaseDatePolicy({moveInMillis,nowMillis,timeZone,role,canBackdate,reason}){
 if(!validZone(timeZone))return {error:'failed-precondition',key:'lease_property_timezone_required'};
 const localDate=propertyDate(moveInMillis,timeZone),today=propertyDate(nowMillis,timeZone);
 if(!localDate||!today)return {error:'invalid-argument',key:'booking_invalid_dates'};
 const backdated=localDate<today;
 if(backdated&&!(typeof canBackdate==='boolean'?canBackdate:['owner','administrator'].includes(role)))return {error:'permission-denied',key:'lease_backdate_owner_admin_required'};
 if(reason!==undefined&&(typeof reason!=='string'||reason.length>1000))return {error:'invalid-argument',key:'lease_backdate_reason_invalid'};
 if(backdated&&(typeof reason!=='string'||!reason.trim()))return {error:'invalid-argument',key:'lease_backdate_reason_required'};
 return {localDate,timeZone,backdated,reason:backdated?reason.trim():null};
}
// First instant belonging to the requested local day. Binary search also handles
// zones whose daylight-saving transition skips midnight. Skipped whole days fail.
function propertyDayStart(date,timeZone){
 const {validDate}=require('./property_contract');
 if(!validDate(date)||!validZone(timeZone))return null;
 const formatter=dateFormatter(timeZone);
 const nominal=Date.parse(date+'T00:00:00Z');
 let lo=nominal-48*3600000,hi=nominal+48*3600000;
 while(lo<hi){const mid=Math.floor((lo+hi)/2);if(formattedDate(mid,formatter)<date)lo=mid+1;else hi=mid;}
 return formattedDate(lo,formatter)===date?lo:null;
}
module.exports={propertyDate,leaseDatePolicy,propertyDayStart};
