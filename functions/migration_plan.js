'use strict';
// G8: plan for moving one legacy (v1) organization to version 2. Pure: takes a
// snapshot of the organization's records and returns the exact field changes,
// each with the previous values so the change can be undone. Never writes.
// Used by tool/migrate_v2.cjs (plan / apply / undo / rehearse).
const {migrationProposal}=require('./team_access');

const DEFAULT_TIME_ZONE='Asia/Ho_Chi_Minh';
const DEFAULT_CURRENCY='VND';
const MODES=['monthly','hourly','both'];
const validZone=zone=>{
 if(typeof zone!=='string'||!zone)return false;
 try{new Intl.DateTimeFormat('en',{timeZone:zone}).format(0);return true;}catch{return false;}
};
const positive=v=>typeof v==='number'&&v>0;

/**
 * snapshot: {organization:{id,...}, memberships, buildings, rooms, tenants,
 * bookings, payments}: arrays of {id, ...fields}.
 * Returns {organizationId, organizationName, blockers, warnings, changes, summary}.
 * A change is {path, set, previous, missing}: `previous` holds old values of
 * fields that existed, `missing` lists fields that did not exist.
 */
function planMigration(snapshot){
 const org=snapshot.organization;
 const list=name=>Array.isArray(snapshot[name])?snapshot[name]:[];
 const blockers=[],warnings=[],changes=[];
 const change=(path,doc,set)=>{
  const keys=Object.keys(set).filter(k=>!Object.is(doc[k],set[k])&&JSON.stringify(doc[k])!==JSON.stringify(set[k]));
  if(!keys.length)return;
  const previous={},missing=[];
  for(const k of keys){if(Object.hasOwn(doc,k)&&doc[k]!==undefined)previous[k]=doc[k];else missing.push(k);}
  changes.push({path,set:Object.fromEntries(keys.map(k=>[k,set[k]])),previous,missing});
 };
 if(!org?.id)throw Error('Snapshot has no organization');
 if(org.accessVersion===2)blockers.push({reason:'alreadyV2',path:`organizations/${org.id}`});
 if(org.closedAt)blockers.push({reason:'organizationClosed',path:`organizations/${org.id}`});

 // People: owner -> owner, admin -> administrator, everyone else waits for the
 // owner to give them a role (assignmentRequired). Non-active people are suspended.
 const memberships=list('memberships');
 const proposal=migrationProposal(org,memberships);
 for(const issue of proposal.issues)blockers.push({reason:issue.reason,path:issue.membershipId?`memberships/${issue.membershipId}`:`organizations/${org.id}`});
 const people={owner:0,administrator:0,waiting:0,suspended:0,unchanged:0};
 for(const p of proposal.proposals){
  const m=memberships.find(x=>x.id===p.membershipId);
  if(!p.proposed){if(p.action==='unchanged')people.unchanged++;continue;}
  if(m.status!=='active')warnings.push({reason:'inactiveMemberSuspended',path:`memberships/${m.id}`,detail:String(m.status??'')});
  const role=m.ownerId===org.createdBy?'owner':p.proposed.role;
  const proposed={...p.proposed,role};
  if(proposed.status==='suspended')people.suspended++;else if(!role)people.waiting++;else people[role]++;
  change(`memberships/${m.id}`,m,proposed);
 }

 // Properties: bookings and lease dates need a time zone; money needs a currency.
 const buildings=new Map(list('buildings').map(b=>[b.id,b]));
 for(const b of buildings.values()){
  const set={};
  if(b.timeZone==null||b.timeZone==='')set.timeZone=DEFAULT_TIME_ZONE;
  else if(!validZone(b.timeZone))blockers.push({reason:'invalidTimeZone',path:`buildings/${b.id}`,detail:String(b.timeZone)});
  if(!b.currency)set.currency=DEFAULT_CURRENCY;
  else if(!['VND','USD'].includes(b.currency))warnings.push({reason:'unusualCurrency',path:`buildings/${b.id}`,detail:String(b.currency)});
  change(`buildings/${b.id}`,b,set);
 }

 // Rooms: v2 only offers short stays on hourly/both rooms. A room without a mode
 // that has short-stay prices or bookings becomes 'both'; otherwise 'monthly'.
 const bookings=list('bookings');
 const booked=new Set(bookings.map(x=>x.roomId).filter(Boolean));
 const rooms=new Map(list('rooms').map(r=>[r.id,r]));
 const modes={monthly:0,hourly:0,both:0};
 for(const r of rooms.values()){
  const building=buildings.get(r.buildingId);
  if(!building){blockers.push({reason:'roomWithoutProperty',path:`rooms/${r.id}`});continue;}
  const set={};
  let mode=r.rentalMode;
  if(mode==null||mode===''){
   mode=[r.hourlyPrice,r.dailyPrice,r.overnightPrice].some(positive)||booked.has(r.id)?'both':'monthly';
   set.rentalMode=mode;
  }else if(!MODES.includes(mode)){blockers.push({reason:'invalidRentalMode',path:`rooms/${r.id}`,detail:String(mode)});continue;}
  modes[mode]++;
  if(mode==='monthly'&&booked.has(r.id))warnings.push({reason:'bookingsOnMonthlyRoom',path:`rooms/${r.id}`});
  if(mode!=='monthly'&&!positive(r.hourlyPrice))warnings.push({reason:'shortStayRoomWithoutHourlyPrice',path:`rooms/${r.id}`});
  if(!r.currency)set.currency=building.currency||DEFAULT_CURRENCY;
  change(`rooms/${r.id}`,r,set);
 }

 // Old records found through their room may lack organizationId/buildingId,
 // which every v2 screen filters on.
 for(const name of ['tenants','bookings','payments']){
  for(const x of list(name)){
   const set={};
   if(!x.organizationId)set.organizationId=org.id;
   else if(x.organizationId!==org.id){blockers.push({reason:'otherOrganizationRecord',path:`${name}/${x.id}`});continue;}
   if(!x.buildingId){
    const room=rooms.get(x.roomId);
    if(room?.buildingId)set.buildingId=room.buildingId;
    else warnings.push({reason:'recordWithoutProperty',path:`${name}/${x.id}`});
   }else if(!buildings.has(x.buildingId))warnings.push({reason:'unknownProperty',path:`${name}/${x.id}`});
   change(`${name}/${x.id}`,x,set);
  }
 }

 // The switch itself goes last, so nobody sees a half-moved organization as v2.
 change(`organizations/${org.id}`,org,{accessVersion:2});
 return {organizationId:org.id,organizationName:org.name??'',blockers,warnings,changes,
  summary:{people,properties:buildings.size,rooms:modes,tenants:list('tenants').length,bookings:bookings.length,
   payments:list('payments').length,changedRecords:changes.length}};
}

module.exports={planMigration,DEFAULT_TIME_ZONE,DEFAULT_CURRENCY};
