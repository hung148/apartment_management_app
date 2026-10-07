'use strict';
// B5 service fees. Money is in currency minor units; quantities are
// thousandths. A fee's partial-period rule turns each person's (or the
// lease's) days present into a share of the full rate (SERVICE_FEES.md).
const {validDate}=require('./property_contract');
const MAX=1e12;
const int=(v,lo,hi)=>Number.isSafeInteger(v)&&v>=lo&&v<=hi;
const exact=(o,keys)=>o&&typeof o==='object'&&!Array.isArray(o)&&Object.keys(o).every(k=>keys.includes(k));
const nextDate=d=>new Date(Date.parse(d+'T00:00:00Z')+86400000).toISOString().slice(0,10);
const dayCount=(a,b)=>Math.round((Date.parse(b+'T00:00:00Z')-Date.parse(a+'T00:00:00Z'))/86400000);
const BASES=['room','person','quantity'];

function validateRule(rule){
 if(!exact(rule,['mode','steps','day']))throw Error('service_invalid_rule');
 if(rule.mode==='days'){if(rule.steps!==undefined||rule.day!==undefined)throw Error('service_invalid_rule');return rule;}
 if(rule.mode==='checkDate'){if(rule.steps!==undefined||!['first','last'].includes(rule.day))throw Error('service_invalid_rule');return rule;}
 if(rule.mode!=='thresholds'||rule.day!==undefined||!Array.isArray(rule.steps)||!rule.steps.length||rule.steps.length>6)throw Error('service_invalid_rule');
 let days=0,percent=0;
 for(const s of rule.steps){
  if(!exact(s,['minDays','percent'])||!int(s.minDays,1,366)||!int(s.percent,1,100)||s.minDays<=days||s.percent<=percent)throw Error('service_invalid_rule');
  days=s.minDays;percent=s.percent;
 }
 return rule;
}

// A dated version of a fee. Inactive versions stop the fee from that date.
function validateVersion(version,basis){
 if(!BASES.includes(basis))throw Error('service_invalid_fee');
 if(!exact(version,['effectiveDate','active','rateMinor','rule','includedPeople','roundingMinor'])||!validDate(version.effectiveDate)||typeof version.active!=='boolean')throw Error('service_invalid_fee');
 if(!version.active){if(Object.keys(version).length!==2)throw Error('service_invalid_fee');return {effectiveDate:version.effectiveDate,active:false};}
 if(!int(version.rateMinor,0,MAX)||!int(version.roundingMinor,0,1e6)||!int(version.includedPeople,0,20))throw Error('service_invalid_fee');
 if(basis==='quantity'){if(version.rule!==null||version.includedPeople!==0)throw Error('service_invalid_fee');}
 else validateRule(version.rule);
 if(basis==='room'&&version.includedPeople!==0)throw Error('service_invalid_fee');
 return {effectiveDate:version.effectiveDate,active:true,rateMinor:version.rateMinor,rule:version.rule===null?null:JSON.parse(JSON.stringify(version.rule)),includedPeople:version.includedPeople,roundingMinor:version.roundingMinor};
}

function validateOverride(o){
 if(!exact(o,['effectiveDate','mode','rateMinor'])||!validDate(o.effectiveDate)||!['inherit','off','rate'].includes(o.mode))throw Error('service_invalid_override');
 if(o.mode==='rate'?!int(o.rateMinor,0,MAX):o.rateMinor!==undefined)throw Error('service_invalid_override');
 return o.mode==='rate'?{effectiveDate:o.effectiveDate,mode:'rate',rateMinor:o.rateMinor}:{effectiveDate:o.effectiveDate,mode:o.mode};
}

// Dated history: unique dates, never before what was already billed.
function addDated(history,entry,billedThrough,limit=60){
 if(billedThrough&&entry.effectiveDate<billedThrough)throw Error('service_fee_past_billed');
 if(history.some(x=>x.effectiveDate===entry.effectiveDate))throw Error('service_fee_date_exists');
 if(history.length>=limit)throw Error('service_fee_history_limit');
 return [...history,entry].sort((a,b)=>a.effectiveDate.localeCompare(b.effectiveDate));
}

const at=(rows,date)=>(rows??[]).filter(x=>x.effectiveDate<=date).at(-1)??null;
/** What applies to one room on one date: null (not charged) or the terms. */
function resolveFee(fee,overrides,date){
 const v=at(fee.versions,date);if(!v||!v.active)return null;
 const o=at(overrides,date);if(o?.mode==='off')return null;
 return {...v,rateMinor:o?.mode==='rate'?o.rateMinor:v.rateMinor,roomRate:o?.mode==='rate'};
}
/** The terms for a whole period; a change inside it needs separate invoices. */
function resolvePeriod(fee,overrides,startDate,endDate){
 const terms=resolveFee(fee,overrides,startDate);
 if(!terms)throw Error('service_fee_not_in_force');
 // Compare what is charged, not when it was written down again.
 const same=x=>{if(!x)return null;const {effectiveDate,...rest}=x;return JSON.stringify(rest);};
 const changes=[...(fee.versions??[]),...(overrides??[])].filter(x=>x.effectiveDate>startDate&&x.effectiveDate<endDate);
 if(changes.some(x=>same(resolveFee(fee,overrides,x.effectiveDate))!==same(terms)))throw Error('service_fee_boundary_required');
 return terms;
}

// [numerator, denominator] of a person's share of the full rate.
function share(rule,present,periodDays,onFirst,onLast){
 if(present>=periodDays)return [1n,1n];
 if(present<=0)return [0n,1n];
 if(rule.mode==='days')return [BigInt(present),BigInt(periodDays)];
 if(rule.mode==='checkDate')return [(rule.day==='first'?onFirst:onLast)?1n:0n,1n];
 const step=rule.steps.filter(s=>s.minDays<=present).at(-1);
 return [BigInt(step?.percent??0),100n];
}
/** Length of [start, end) in months as [numerator, denominator]: whole
 * calendar months from the start date, plus the leftover days as a share of
 * the next month (1 Oct–1 Nov = 1; 2 Oct–2 Jan = 3; 1–15 Oct = 14/31). */
function monthsBetween(start,end){
 const add=(date,k)=>{const [y,m,d]=date.split('-').map(Number),t=new Date(Date.UTC(y,m-1+k,1)),last=new Date(Date.UTC(t.getUTCFullYear(),t.getUTCMonth()+1,0)).getUTCDate();return new Date(Date.UTC(t.getUTCFullYear(),t.getUTCMonth(),Math.min(d,last))).toISOString().slice(0,10);};
 let k=0;while(add(start,k+1)<=end)k++;
 const from=add(start,k),rest=dayCount(from,end),span=dayCount(from,add(start,k+1));
 const gcd=(a,b)=>b?gcd(b,a%b):a,n=k*span+rest,g=gcd(n,span)||1;
 return [BigInt(n/g),BigInt(span/g)];
}
function amount(rateMinor,[n,d],roundingMinor,[mn,md]=[1n,1n]){
 n*=mn;d*=md;
 let minor=Number((BigInt(rateMinor)*n*2n+d)/(2n*d));
 if(roundingMinor>1)minor=Math.floor((minor+roundingMinor/2)/roundingMinor)*roundingMinor;
 if(!Number.isSafeInteger(minor)||minor>MAX)throw Error('service_amount_too_large');
 return minor;
}

/**
 * people: [{id,name,isMain,intervals:[{startDate,endDate|null}]}] in the room.
 * Days are calendar dates in the property time zone, end exclusive.
 */
function serviceCharge({basis,terms,startDate,endDate,people,quantityMilli=null,currency}){
 if(!validDate(startDate)||!validDate(endDate)||endDate<=startDate||dayCount(startDate,endDate)>366)throw Error('service_invalid_period');
 const periodDays=dayCount(startDate,endDate),last=new Date(Date.parse(endDate+'T00:00:00Z')-86400000).toISOString().slice(0,10);
 const here=(p,day)=>p.intervals.some(i=>day>=i.startDate&&(i.endDate==null||day<i.endDate));
 const main=people.find(p=>p.isMain);
 if(!main)throw Error('service_tenant_not_in_room');
 const mainDays=new Set();for(let day=startDate;day<endDate;day=nextDate(day))if(here(main,day))mainDays.add(day);
 if(!mainDays.size)throw Error('service_tenant_not_in_room');
 // Room and per-person prices are per month; the period may be several months.
 const months=monthsBetween(startDate,endDate);
 let lines;
 if(basis==='quantity'){
  if(!int(quantityMilli,1,1e9))throw Error('service_invalid_quantity');
  lines=[{tenantId:main.id,name:main.name,quantityMilli,amountMinor:amount(terms.rateMinor,[BigInt(quantityMilli),1000n],terms.roundingMinor)}];
 }else{
  // A roommate counts only on days the lease itself is in the room.
  const rows=(basis==='room'?[main]:people).map(p=>{
   let present=0;for(const day of mainDays)if(here(p,day))present++;
   return {p,present,first:[...mainDays].find(day=>here(p,day))??null};
  }).filter(r=>r.present>0).sort((a,b)=>a.first.localeCompare(b.first)||(b.p.isMain-a.p.isMain)||a.p.name.localeCompare(b.p.name)||a.p.id.localeCompare(b.p.id));
  lines=rows.map((r,i)=>{
   const free=i<terms.includedPeople,s=share(terms.rule,r.present,periodDays,mainDays.has(startDate)&&here(r.p,startDate),mainDays.has(last)&&here(r.p,last));
   return {tenantId:r.p.id,name:r.p.name,days:r.present,periodDays,share:[Number(s[0]),Number(s[1])],free,amountMinor:free?0:amount(terms.rateMinor,s,terms.roundingMinor,months)};
  });
 }
 const amountMinor=lines.reduce((n,l)=>n+l.amountMinor,0);
 if(amountMinor<=0)throw Error('service_no_billable_charge');
 if(!Number.isSafeInteger(amountMinor)||amountMinor>MAX)throw Error('service_amount_too_large');
 return {amountMinor,currency,basis,periodDays,months:[Number(months[0]),Number(months[1])],startDate,endDate,lines,terms:{rateMinor:terms.rateMinor,roomRate:terms.roomRate===true,rule:terms.rule,includedPeople:terms.includedPeople,roundingMinor:terms.roundingMinor,effectiveDate:terms.effectiveDate}};
}
module.exports={validateRule,validateVersion,validateOverride,addDated,resolveFee,resolvePeriod,serviceCharge,monthsBetween,nextDate,dayCount,BASES};
