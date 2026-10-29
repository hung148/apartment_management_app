'use strict';
// 2026-10-26 (Tom, PRICE_DEFAULTS.md): rooms' flat hourly prices become the
// building's hourly templates — each different price one template with the
// same price every hour ("100,000 mỗi giờ"). Pure planner; the tool writes.
const MAX_TEMPLATES=20;
const scaleOf=c=>c==='USD'?100:1;
const label=(minor,currency)=>{
 const v=minor/scaleOf(currency);
 const text=currency==='USD'?v.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g,','):String(Math.round(v)).replace(/\B(?=(\d{3})+(?!\d))/g,',');
 return `${text}${currency==='USD'?' USD':''} mỗi giờ`;
};
/** rooms: [{hourlyPrice, currency, deletedAt}] of one building;
 * existing: the building's templates. Returns the templates to add. */
function planHourlyTemplates({buildingCurrency,rooms,existing}){
 const currency=buildingCurrency??'VND';
 const prices=[...new Set(rooms.filter(r=>!r.deletedAt&&(r.currency??'VND')===currency&&typeof r.hourlyPrice==='number'&&r.hourlyPrice>0)
  .map(r=>Math.round(r.hourlyPrice*scaleOf(currency))))].sort((a,b)=>a-b);
 const have=new Set((existing??[]).filter(t=>t.currency===currency&&Array.isArray(t.hourPricesMinor)&&t.hourPricesMinor.length===1).map(t=>t.hourPricesMinor[0]));
 const add=prices.filter(p=>!have.has(p)).map(p=>({id:`flat_${p}`,name:label(p,currency),currency,hourPricesMinor:[p]}));
 const room=MAX_TEMPLATES-(existing??[]).length;
 return {add:add.slice(0,Math.max(0,room)),skipped:add.slice(Math.max(0,room)),otherCurrencyRooms:rooms.filter(r=>!r.deletedAt&&typeof r.hourlyPrice==='number'&&r.hourlyPrice>0&&(r.currency??'VND')!==currency).length};
}
module.exports={planHourlyTemplates};
