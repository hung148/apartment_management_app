'use strict';
// Bảng thanh toán theo kỳ (PAYMENT_SCHEDULE.md, Tom 2026-10-26).
// Pure rules: no Firestore. The lease stores `paymentSchedule` only after the
// first hand change; until then the table is built from the lease on every read.
// Dates are property-local YYYY-MM-DD; a kỳ is [start, end) (end exclusive).
const {addMonths,periodRent}=require('./period_invoice');
const {monthsBetween}=require('./service_fee_math');
const {propertyDate}=require('./lease_dates');
const {validDate}=require('./property_contract');

const DAY=86400000;
const addDays=(date,n)=>new Date(Date.parse(date+'T00:00:00Z')+n*DAY).toISOString().slice(0,10);
const daysBetween=(a,b)=>Math.round((Date.parse(b+'T00:00:00Z')-Date.parse(a+'T00:00:00Z'))/DAY);
const MAX_ROWS=240;

/** Where the table runs: move-in .. min(contract end, move-out). The contract
 * end date is the day the tenant leaves: not billed (Tom, 2026-10-26), so
 * 27/10/2026 → 27/10/2027 is exactly 12 monthly kỳ. */
function leaseWindow(t,zone){
 const start=typeof t.moveInLocalDate==='string'?t.moveInLocalDate:t.moveInDate?.toMillis?propertyDate(t.moveInDate.toMillis(),zone):null;
 const contractEnd=typeof t.contractEndLocalDate==='string'&&validDate(t.contractEndLocalDate)?t.contractEndLocalDate:null;
 const moveOut=t.moveOutDate?.toMillis?propertyDate(t.moveOutDate.toMillis(),zone):null;
 const end=contractEnd&&moveOut?(moveOut<contractEnd?moveOut:contractEnd):contractEnd??moveOut;
 return {start,end,contractEnd,moveOut};
}

/** Rent + phụ thu that a kỳ costs when nobody changed it by hand. */
function defaultAmount(t,{start,end,first,people,intervals,zone}){
 let rentMinor=0;
 try{rentMinor=periodRent({tenant:t,startDate:start,endDate:end,intervals,timeZone:zone}).amountMinor;}catch{rentMinor=0;}
 let surchargeMinor=0;
 for(const s of Array.isArray(t.surcharges)?t.surcharges:[]){
  if(!s||!Number.isSafeInteger(s.amountMinor)||s.amountMinor<=0)continue;
  const unit=s.amountMinor*(s.basis==='person'?Math.max(1,people):1);
  if(s.frequency==='period')surchargeMinor+=unit;
  else if(s.frequency==='month'){const [n,d]=monthsBetween(start,end);surchargeMinor+=Number((BigInt(unit)*n*2n+d)/(2n*d));}
  else if(s.frequency==='once'&&first)surchargeMinor+=unit;
 }
 return {rentMinor,surchargeMinor,totalMinor:rentMinor+surchargeMinor};
}

/** The old "due day of the month" (leases from before 2026-10-26). */
function legacyDue(t,start){
 if(!Number.isSafeInteger(t.paymentDueDay))return start;
 const y=Number(start.slice(0,4)),mo=Number(start.slice(5,7)),last=new Date(Date.UTC(y,mo,0)).getUTCDate();
 const c=`${start.slice(0,8)}${String(Math.min(t.paymentDueDay,last)).padStart(2,'0')}`;
 return c>start?c:start;
}

/**
 * Build the rows. stored: lease.paymentSchedule (may be missing).
 * invoices: the lease's live period invoices with rent
 *   [{id,scheduleRowId?,startDate,endDate,totalMinor,paidMinor}].
 * Returns {rows, needsEnd} — rows: [{id,start,end,due,amountMinor,rentMinor,
 *   surchargeMinor,defaultMinor,datesEdited,startEdited,dueEdited,dueOffset,
 *   amountEdited,reason,invoice|null,locked,overflow}]
 */
function buildSchedule({t,zone,stored,invoices=[],people=1,intervals=[]}){
 const w=leaseWindow(t,zone),months=Number.isSafeInteger(t.paymentPeriodMonths)&&t.paymentPeriodMonths>0?t.paymentPeriodMonths:1;
 if(!w.start||!w.end)return {rows:[],needsEnd:!w.end,window:w};
 if(w.end<=w.start)return {rows:[],needsEnd:false,window:w};
 const live=invoices.filter(x=>x&&typeof x.startDate==='string'&&typeof x.endDate==='string');
 const hasStored=Array.isArray(stored)&&stored.length>0;
 const byRow=new Map(live.filter(x=>x.scheduleRowId).map(x=>[x.scheduleRowId,x]));
 const used=new Set(),ids=new Set(),rows=[];
 const newId=start=>{let id=`k${start.replace(/-/g,'')}`,n=1;while(ids.has(id))id=`k${start.replace(/-/g,'')}_${++n}`;return id;};
 const lockFor=(id,start,end)=>{
  let x=byRow.get(id);
  // Invoices from before the table existed (no kỳ id): same dates = this kỳ.
  if(!x)x=live.find(v=>!v.scheduleRowId&&!used.has(v.id)&&v.startDate===start&&v.endDate===end);
  if(x&&!used.has(x.id)){used.add(x.id);return x;}
  return null;
 };
 let cursor=w.start;
 for(const s of hasStored?stored:[]){
  if(!s||typeof s.id!=='string')continue;
  const inv=byRow.get(s.id)??live.find(v=>!v.scheduleRowId&&!used.has(v.id)&&v.startDate===s.start&&v.endDate===s.end);
  if(inv&&!used.has(inv.id)){
   // Invoiced kỳ never move.
   used.add(inv.id);ids.add(s.id);
   // gap: the kỳ before no longer ends where this one starts.
   rows.push({...s,start:inv.startDate,end:inv.endDate,invoice:inv,locked:true,gap:rows.length>0&&inv.startDate!==cursor});
   cursor=inv.endDate>cursor?inv.endDate:cursor;continue;
  }
  if(cursor>=w.end)continue; // past the end now (end date moved / moved out): dropped
  const start=rows.length===0&&s.startEdited&&validDate(s.start)&&s.start>=w.start&&s.start<w.end?s.start:cursor;
  let end=s.datesEdited&&Number.isSafeInteger(s.days)&&s.days>0?addDays(start,s.days):addMonths(start,months);
  const overflow=end>w.end;
  if(overflow)end=w.end;
  ids.add(s.id);
  rows.push({...s,start,end,overflow:overflow&&s.datesEdited===true,locked:false,invoice:null});
  cursor=end;
 }
 while(cursor<w.end&&rows.length<MAX_ROWS){
  const start=cursor,end=addMonths(start,months)<w.end?addMonths(start,months):w.end,id=newId(start);
  ids.add(id);
  const inv=lockFor(id,start,end);
  rows.push({id,start,end,datesEdited:false,startEdited:false,dueEdited:false,amountEdited:false,locked:!!inv,invoice:inv,overflow:false});
  cursor=end;
 }
 // Old invoices (from before the table) that matched no kỳ: listed for clean-up.
 const unmatched=live.filter(x=>!used.has(x.id)&&!x.scheduleRowId).map(x=>x.id);
 rows.forEach((r,i)=>{
  const def=defaultAmount(t,{start:r.start,end:r.end,first:i===0,people,intervals,zone});
  r.defaultMinor=def.totalMinor;r.surchargeMinor=def.surchargeMinor;
  r.due=r.dueEdited&&Number.isSafeInteger(r.dueOffset)?addDays(r.start,r.dueOffset):legacyDue(t,r.start);
  if(r.locked){r.amountMinor=r.invoice.totalMinor;r.rentMinor=null;}
  else if(r.amountEdited&&Number.isSafeInteger(r.amountMinor)){r.rentMinor=r.amountMinor-def.surchargeMinor;}
  else{r.amountMinor=def.totalMinor;r.rentMinor=def.rentMinor;r.amountEdited=false;}
  r.paidMinor=r.invoice?r.invoice.paidMinor??0:0;
  r.leftMinor=Math.max(0,r.amountMinor-r.paidMinor);
  r.wholeMonths=(()=>{for(let k=1;k<=24;k++){const e=addMonths(r.start,k);if(e===r.end)return k;if(e>r.end)return null;}return null;})();
  r.days=daysBetween(r.start,r.end);
 });
 return {rows,needsEnd:false,window:w,unmatched};
}

/** What the lease stores: enough to rebuild the rows. */
const toStored=rows=>rows.map((r,i)=>({id:r.id,start:r.start,end:r.end,
 ...(i===0&&r.startEdited?{startEdited:true}:{}),
 ...(r.datesEdited?{datesEdited:true,days:daysBetween(r.start,r.end)}:{}),
 ...(r.dueEdited?{dueEdited:true,dueOffset:r.dueOffset}:{}),
 ...(r.amountEdited?{amountEdited:true,amountMinor:r.amountMinor,reason:r.reason??null,editedBy:r.editedBy??null,editedAt:r.editedAt??null}:{})}));

class ScheduleError extends Error{}
const no=key=>{throw new ScheduleError(key);};

/**
 * Apply one change to built rows; returns the rows to store (before rebuild).
 * change: {op:'edit',rowId,start?,end?,due?,amountMinor?,reason?}
 *       | {op:'split',rowId,date} | {op:'merge',rowId}
 * The caller rebuilds, then calls checkResult(before, after).
 */
function applyChange(rows,change,{window,by,at}){
 const freshId=start=>{const taken=new Set(rows.map(x=>x.id));let id=`k${start.replace(/-/g,'')}`,n=1;while(taken.has(id))id=`k${start.replace(/-/g,'')}_${++n}`;return id;};
 const i=rows.findIndex(r=>r.id===change.rowId);
 if(i<0)no('schedule_row_not_found');
 const r=rows[i],copy=rows.map(x=>({...x}));
 if(r.locked)no('schedule_row_locked');
 const row=copy[i];
 if(change.op==='edit'){
  if(change.start!==undefined&&change.start!==r.start){
   const s=change.start;
   if(!validDate(s)||s>=r.end)no('schedule_invalid_dates');
   if(i===0){
    if(s<window.start)no('schedule_before_move_in');
    // Kỳ 1 keeps its length and moves (days before it are not billed).
    row.startEdited=s!==window.start;row.start=s;
    if(row.datesEdited)row.days=daysBetween(r.start,r.end);
   }else{
    const prev=copy[i-1];
    if(prev.locked)no('schedule_row_locked');
    if(s<=prev.start)no('schedule_invalid_dates');
    // Moving the line between kỳ n-1 and kỳ n: kỳ n-1 gets another length.
    prev.datesEdited=true;prev.days=daysBetween(prev.start,s);prev.end=s;
   }
  }
  if(change.end!==undefined&&change.end!==r.end){
   if(!validDate(change.end)||change.end<=(change.start??r.start))no('schedule_invalid_dates');
   row.datesEdited=true;row.days=daysBetween(change.start??r.start,change.end);row.end=change.end;
  }
  if(change.due!==undefined&&change.due!==r.due){
   const start=change.start??r.start,end=change.end??r.end;
   if(!validDate(change.due)||change.due<start||change.due>=end)no('schedule_due_outside');
   row.dueEdited=change.due!==start;row.dueOffset=daysBetween(start,change.due);
  }
  if(change.amountMinor!==undefined){
   if(!Number.isSafeInteger(change.amountMinor)||change.amountMinor<=0||change.amountMinor>1e12)no('schedule_invalid_amount');
   if(change.amountMinor===r.defaultMinor){row.amountEdited=false;row.reason=null;}
   else{
    if(change.amountMinor<=r.surchargeMinor)no('schedule_amount_below_surcharges');
    if(typeof change.reason!=='string'||!change.reason.trim())no('schedule_reason_required');
    row.amountEdited=true;row.amountMinor=change.amountMinor;row.reason=change.reason.trim().slice(0,1000);row.editedBy=by;row.editedAt=at;
   }
  }
  return {rows:copy,removed:[]};
 }
 if(change.op==='split'){
  const d=change.date;
  if(!validDate(d)||d<=r.start||d>=r.end)no('schedule_split_outside');
  const left={...row,end:d,datesEdited:true,days:daysBetween(r.start,d)};
  const right={id:freshId(d),start:d,end:r.end,datesEdited:true,days:daysBetween(d,r.end),dueEdited:false,amountEdited:false};
  if(r.amountEdited){
   // A hand-set amount is shared by days.
   const total=r.amountMinor,a=Math.round(total*left.days/(left.days+right.days));
   Object.assign(left,{amountMinor:a});Object.assign(right,{amountEdited:true,amountMinor:total-a,reason:r.reason,editedBy:by,editedAt:at});
  }
  if(r.dueEdited&&daysBetween(r.start,r.due)>=left.days){left.dueEdited=false;}
  copy.splice(i,1,left,right);
  return {rows:copy,removed:[]};
 }
 if(change.op==='merge'){
  if(rows.length<2)no('schedule_merge_only_one');
  const j=i===0?1:i-1,other=copy[j];
  if(other.locked)no('schedule_row_locked');
  const a=i<j?row:other,b=i<j?other:row;
  const merged={...a,end:b.end,datesEdited:true,days:daysBetween(a.start,b.end)};
  if(a.amountEdited||b.amountEdited){merged.amountEdited=true;merged.amountMinor=a.amountMinor+b.amountMinor;merged.reason=[a.reason,b.reason].filter(Boolean).join(' · ')||null;merged.editedBy=by;merged.editedAt=at;}
  copy.splice(Math.min(i,j),2,merged);
  return {rows:copy,removed:[b.id]};
 }
 no('schedule_invalid_change');
}

/** After a change: invoiced kỳ may not move, and nothing may run past the end. */
function checkResult(before,after,removed=[]){
 // Kỳ stay back to back: a change that needs an invoiced kỳ to move is refused.
 if(after.some(r=>r.gap)&&!before.some(r=>r.gap))no('schedule_moves_locked');
 for(const r of before.filter(x=>x.locked)){
  const now=after.find(x=>x.id===r.id);
  if(removed.includes(r.id))no('schedule_row_locked');
  if(!now||now.start!==r.start||now.end!==r.end)no('schedule_moves_locked');
 }
 if(after.some(r=>r.overflow))no('schedule_past_contract_end');
 // A kỳ pushed out entirely (its days now past the contract end).
 const kept=new Set([...after.map(r=>r.id),...removed]);
 if(before.some(r=>(r.datesEdited||r.amountEdited)&&!kept.has(r.id)))no('schedule_past_contract_end');
}

module.exports={leaseWindow,defaultAmount,buildSchedule,toStored,applyChange,checkResult,ScheduleError,addDays,daysBetween};
