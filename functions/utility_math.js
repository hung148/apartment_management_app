'use strict';
// Meter quantities are thousandths of a unit; prices and totals are minor money.
const MAX=1e12;
const quantity=v=>Number.isSafeInteger(v)&&v>=0&&v<=MAX;
function validateTariff(tariff){
 if(!tariff||!['VND','USD'].includes(tariff.currency)||!Array.isArray(tariff.bands)||!tariff.bands.length||tariff.bands.length>12)throw Error('utility_invalid_tariff');
 let previous=0;
 for(const [i,band] of tariff.bands.entries()){
  if(!band||!quantity(band.priceMinor)||Object.keys(band).some(k=>!['throughMilli','priceMinor'].includes(k)))throw Error('utility_invalid_tariff');
  if(i===tariff.bands.length-1){if(band.throughMilli!==null)throw Error('utility_invalid_tariff');}
  else {if(!quantity(band.throughMilli)||band.throughMilli<=previous)throw Error('utility_invalid_tariff');previous=band.throughMilli;}
 }
 return tariff;
}
function utilityCharge(usageMilli,tariff){
 if(!quantity(usageMilli))throw Error('utility_invalid_reading');validateTariff(tariff);
 let lower=0,remaining=usageMilli,numerator=0n;const lines=[];
 for(const band of tariff.bands){
  const units=band.throughMilli===null?remaining:Math.min(remaining,band.throughMilli-lower);
  if(units>0){lines.push({quantityMilli:units,priceMinor:band.priceMinor});numerator+=BigInt(units)*BigInt(band.priceMinor);remaining-=units;}
  if(!remaining)break;lower=band.throughMilli;
 }
 const amountMinor=Number((numerator+500n)/1000n);
 if(!Number.isSafeInteger(amountMinor)||amountMinor>MAX)throw Error('utility_amount_too_large');
 return {usageMilli,amountMinor,currency:tariff.currency,lines};
}
function meterUsage(previous,current,{oldFinalMilli=null,newStartMilli=null}={}){
 if(!quantity(previous)||!quantity(current))throw Error('utility_invalid_reading');
 if(oldFinalMilli===null&&newStartMilli===null){if(current<previous)throw Error('utility_reading_decreased');return current-previous;}
 if(!quantity(oldFinalMilli)||!quantity(newStartMilli)||oldFinalMilli<previous||current<newStartMilli)throw Error('utility_invalid_reset');
 const usage=oldFinalMilli-previous+current-newStartMilli;
 if(!quantity(usage))throw Error('utility_invalid_reading');return usage;
}
module.exports={validateTariff,utilityCharge,meterUsage};
