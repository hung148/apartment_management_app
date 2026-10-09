'use strict';
const {createHash}=require('node:crypto');
const CURRENCIES=['USD','VND'];
function normalizeRates(rows){
 if(!Array.isArray(rows))throw Error('currency_rates_unavailable');
 const perUsd={USD:'1'},dates={};
 for(const row of rows){
  if(!row||row.base!=='USD'||!CURRENCIES.includes(row.quote))continue;
  if(typeof row.rate!=='number'||!Number.isFinite(row.rate)||row.rate<=0||
     !/^\d{4}-\d{2}-\d{2}$/.test(row.date??'')||!Number.isFinite(Date.parse(row.date)))throw Error('currency_rates_unavailable');
  perUsd[row.quote]=String(row.rate);dates[row.quote]=row.date;
 }
 if(!perUsd.VND)throw Error('currency_rates_unavailable');
 const data={provider:'Frankfurter',perUsd,dates};
 return {id:createHash('sha256').update(JSON.stringify(data)).digest('hex'),...data};
}
async function fetchReferenceRates(){
 const response=await fetch('https://api.frankfurter.dev/v2/rates?base=USD&quotes=VND',{signal:AbortSignal.timeout(12000)});
 if(!response.ok)throw Error('currency_rates_unavailable');
 return response.json();
}
function rational(value){
 const m=/^(\d+)(?:\.(\d+))?(?:e([+-]?\d+))?$/i.exec(String(value));
 if(!m)throw Error('currency_rates_unavailable');
 const exponent=Number(m[3]??0)-(m[2]?.length??0);
 if(Math.abs(exponent)>30)throw Error('currency_rates_unavailable');
 let n=BigInt(m[1]+(m[2]??'')),d=1n;
 if(n<=0n)throw Error('currency_rates_unavailable');
 if(exponent>=0)n*=10n**BigInt(exponent);else d=10n**BigInt(-exponent);
 return [n,d];
}
function convertMinor(amount,from,to,snapshot){
 if(!Number.isSafeInteger(amount)||!CURRENCIES.includes(from)||!CURRENCIES.includes(to))throw Error('currency_invalid_amount');
 if(from===to)return amount;
 const [sn,sd]=rational(snapshot?.perUsd?.[from]),[tn,td]=rational(snapshot?.perUsd?.[to]);
 const n=BigInt(amount)*tn*sd*(to==='USD'?100n:1n),d=sn*td*(from==='USD'?100n:1n);
 const magnitude=((n<0n?-n:n)*2n+d)/(2n*d),result=n<0n?-magnitude:magnitude;
 if(result>1000000000000n||result< -1000000000000n)throw Error('currency_invalid_amount');
 return Number(result);
}
// A reference supplied by the client is only an identifier. Monetary rates are
// read from immutable, backend-written snapshots, never from request values.
async function readReferenceRates(tx,db,id){
 if(typeof id!=='string'||! /^[a-f0-9]{64}$/.test(id))throw Error('currency_rates_required');
 const row=(await tx.get(db.doc(`referenceExchangeRates/${id}`))).data();
 if(!row||row.id!==id)throw Error('currency_rates_required');
 return row;
}
function convertCalculation(calculation,currency,snapshot){
 const source=calculation.currency;
 if(source===currency)return calculation;
 const visit=value=>{
  if(Array.isArray(value))return value.map(visit);
  if(!value||typeof value!=='object')return value;
  return Object.fromEntries(Object.entries(value).map(([key,item])=>[
   key,key==='currency'?currency:key.endsWith('Minor')&&typeof item==='number'?convertMinor(item,source,currency,snapshot):visit(item),
  ]));
 };
 const converted=visit(calculation);
 // Each independently billed line rounds in the destination currency. Keep
 // its displayed sum equal to the charged total where lines constitute a sum.
 if(Array.isArray(calculation.lines)&&calculation.lines.length&&calculation.lines.every(l=>Number.isSafeInteger(l.amountMinor))&&
    calculation.lines.reduce((n,l)=>n+l.amountMinor,0)===calculation.amountMinor){
  converted.amountMinor=converted.lines.reduce((n,l)=>n+l.amountMinor,0);
 }
 if(calculation.amountMinor>0&&converted.amountMinor<=0)throw Error('currency_amount_too_small');
 return {...converted,sourceCalculation:calculation,exchangeRateSnapshotId:snapshot.id};
}
module.exports={normalizeRates,fetchReferenceRates,convertMinor,readReferenceRates,convertCalculation};
