'use strict';
const {validateTariff}=require('./utility_math');
const {validDate}=require('./property_contract');

// Prices apply from a measured boundary. Never estimate consumption across a
// price change by dividing it by days: meter usage is not uniformly distributed.
function addTariff(history,{effectiveDate,tariff},lastDate=null){
 if(!validDate(effectiveDate))throw Error('utility_invalid_tariff_date');
 if(tariff!==null)validateTariff(tariff);
 if(lastDate&&effectiveDate<lastDate)throw Error('utility_tariff_past_reading');
 if(history.some(x=>x.effectiveDate===effectiveDate))throw Error('utility_tariff_date_exists');
 if(history.length>=120)throw Error('utility_tariff_history_limit');
 return [...history,{effectiveDate,tariff}].sort((a,b)=>a.effectiveDate.localeCompare(b.effectiveDate));
}
function resolveTariff(roomHistory,propertyHistory,startDate,endDate,currency){
 const at=(rows,date)=>rows.filter(x=>x.effectiveDate<=date).at(-1)?.tariff??null;
 const pick=date=>at(roomHistory,date)??at(propertyHistory,date);
 const tariff=pick(startDate);
 if(!tariff||(currency!==undefined&&tariff.currency!==currency))throw Error('utility_tariff_required');
 const changes=[...roomHistory,...propertyHistory].filter(x=>x.effectiveDate>startDate&&x.effectiveDate<endDate);
 if(changes.some(x=>JSON.stringify(pick(x.effectiveDate))!==JSON.stringify(tariff)))throw Error('utility_tariff_boundary_required');
 return tariff;
}
module.exports={addTariff,resolveTariff};
