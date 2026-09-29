'use strict';
const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const dateKey=v=>typeof v==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(v)&&v>='2000-01-01'&&v<='2199-12-31'&&Number.isFinite(Date.parse(v+'T00:00:00Z'))&&new Date(v+'T00:00:00Z').toISOString().slice(0,10)===v;
const shift=(day,n)=>new Date(Date.parse(day+'T00:00:00Z')+n*86400000).toISOString().slice(0,10);
const weekday=day=>(new Date(day+'T00:00:00Z').getUTCDay()+6)%7;
const windows=(s,day)=>Object.hasOwn(s.exceptions,day)?s.exceptions[day]:s.week[weekday(day)];
function validWindows(rows){
  return Array.isArray(rows)&&rows.length<=6&&rows.every(w=>object(w)&&Object.keys(w).length===2&&Number.isInteger(w.start)&&Number.isInteger(w.end)&&w.start>=0&&w.start<1440&&w.end>=0&&w.end<=1440&&w.start!==w.end);
}
function disjoint(rows){
  rows.sort((a,b)=>a[0]-b[0]);
  return rows.every((v,i)=>i===0||v[0]>=rows[i-1][1]);
}
function daySegments(s,day){
  const result=windows(s,day).map(w=>[w.start,w.end<w.start?1440:w.end]);
  if(!Object.hasOwn(s.exceptions,day))for(const w of windows(s,shift(day,-1)))if(w.end<w.start&&w.end>0)result.push([0,w.end]);
  return result;
}
function validSchedule(s){
  if(!object(s)||Object.keys(s).length!==2||!object(s.week)||Object.keys(s.week).length!==7||!Array.from({length:7},(_,i)=>s.week[i]).every(validWindows)||!object(s.exceptions)||Object.keys(s.exceptions).length>60)return false;
  if(!Object.entries(s.exceptions).every(([day,rows])=>dateKey(day)&&validWindows(rows)))return false;
  // Check recurring week, including Sunday spill into Monday.
  for(let i=0;i<7;i++){
    const segments=s.week[i].map(w=>[w.start,w.end<w.start?1440:w.end]);
    for(const w of s.week[(i+6)%7])if(w.end<w.start&&w.end>0)segments.push([0,w.end]);
    if(!disjoint(segments))return false;
  }
  for(const day of Object.keys(s.exceptions))for(const d of [day,shift(day,1)])if(!disjoint(daySegments(s,d)))return false;
  return true;
}
function withinSchedule(start,end,s,zone){
  if(!validSchedule(s)||!Number.isFinite(start)||!Number.isFinite(end)||end<=start||end-start>26*3600000)return false;
  let fmt;
  try {fmt=new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'});}catch{return false;}
  const local=time=>{
    const p=Object.fromEntries(fmt.formatToParts(time).map(v=>[v.type,v.value]));
    return {day:`${p.year}-${p.month}-${p.day}`,minute:Number(p.hour)*60+Number(p.minute)};
  };
  const first=local(start),candidates=[];
  for(const day of [shift(first.day,-1),first.day])for(const w of windows(s,day))candidates.push({day,...w});
  const inside=(p,w)=>p.day===w.day?p.minute>=w.start&&(w.end<w.start||p.minute<w.end):
    w.end<w.start&&p.day===shift(w.day,1)&&!Object.hasOwn(s.exceptions,p.day)&&p.minute<w.end;
  let active=candidates.filter(w=>inside(first,w)&&inside(local(end-1),w));
  // Repeated DST hours can leave a window even when both endpoints are inside.
  for(let time=Math.floor(start/60000)*60000+60000;active.length&&time<end;time+=60000){
    const p=local(time);active=active.filter(w=>inside(p,w));
  }
  return active.length>0;
}
module.exports={validSchedule,withinSchedule};
