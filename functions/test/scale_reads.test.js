// Scale (2026-10-11, Tom: 100+ buildings, staff and tenants): reads that
// grew with the whole organization now read only what the screen shows.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createLeaseLifecycleHandler}=require('../lease_lifecycle');
const {staffNames,staffChoices,forgetStaff}=require('../staff_directory');

const at=d=>Ts.fromMillis(Date.parse(d+'T00:00:00+07:00'));
const owner={ownerId:'owner',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all',buildingIds:[]};
// Counts the records each collection returns.
const counting=db=>{
 const collection=db.collection,doc=db.doc,returned={};
 const wrap=(name,q)=>({where:(...a)=>wrap(name,q.where(...a)),orderBy:(...a)=>wrap(name,q.orderBy(...a)),limit:n=>wrap(name,q.limit(n)),startAfter:v=>wrap(name,q.startAfter(v)),
  get:async()=>{const r=await q.get();returned[name]=(returned[name]??0)+r.docs.length;return r;}});
 db.collection=name=>wrap(name,collection(name));
 return returned;
};

function moveSetup(){
 Ts.clock=Date.parse('2026-11-20T05:00:00Z');
 const data={'organizations/o':{accessVersion:2},'memberships/owner_o':owner,
  'tenants/t':{organizationId:'o',buildingId:'b1',roomId:'b1r1',isMainTenant:true,status:'active',fullName:'Le Van Chinh',moveInDate:at('2026-10-02'),moveOutDate:null}};
 for(let b=1;b<=20;b++){
  data[`buildings/b${b}`]={organizationId:'o',name:`Toa ${String(b).padStart(2,'0')}`,timeZone:'Asia/Ho_Chi_Minh'};
  for(let r=1;r<=6;r++){
   data[`rooms/b${b}r${r}`]={organizationId:'o',buildingId:`b${b}`,roomNumber:String(100+r)};
   if(r===2)data[`tenants/b${b}m`]={organizationId:'o',buildingId:`b${b}`,roomId:`b${b}r2`,isMainTenant:true,status:'active',fullName:`Main ${b}`,moveOutDate:null};
   if(r===3)data[`tenants/b${b}old`]={organizationId:'o',buildingId:`b${b}`,roomId:`b${b}r3`,isMainTenant:true,status:'moveOut',fullName:`Old ${b}`,moveOutDate:at('2026-01-01')};
  }
 }
 data['buildings/gone']={organizationId:'o',name:'Gone',timeZone:'Asia/Ho_Chi_Minh',deletedAt:at('2026-01-01')};
 data['buildings/x']={organizationId:'other',name:'Not ours',timeZone:'Asia/Ho_Chi_Minh'};
 const db=fakeDb(data),lease=createLeaseLifecycleHandler({db,Timestamp:Ts,HttpsError:CodeError});
 const call=(extra,uid='owner')=>lease({auth:{uid},data:{organizationId:'o',buildingId:'b1',tenantId:'t',action:'destinations',...extra}});
 return {db,call};
}

test('room choices for a move: one building, its current tenants, the list when asked',async()=>{
 const {db,call}=moveSetup();
 const returned=counting(db);
 const own=await call({});
 assert.equal(own.buildingId,'b1');
 assert.deepEqual(own.records.map(r=>r.roomNumber),['102','103','104','105','106'],'the lease\'s own room is not a choice');
 assert.deepEqual(own.records[0].mainTenants,[{id:'b1m',fullName:'Main 1'}]);
 assert.deepEqual(own.records[1].mainTenants,[],'a tenant who moved out is not someone to live with');
 assert.equal(own.buildings,undefined);
 assert(returned.rooms<=6&&returned.tenants<=3,`one building only (${JSON.stringify(returned)})`);
 const other=await call({destinationBuildingId:'b7',list:true});
 assert.deepEqual(other.records.map(r=>r.id),['b7r1','b7r2','b7r3','b7r4','b7r5','b7r6']);
 assert.equal(other.buildings.length,20,'every building of the organization, not deleted or others\'');
 assert.deepEqual(other.buildings.slice(0,2),[{id:'b1',name:'Toa 01'},{id:'b2',name:'Toa 02'}]);
 for(const bad of ['x','gone','missing'])await assert.rejects(call({destinationBuildingId:bad}),e=>e.code==='not-found');
 await assert.rejects(call({destinationBuildingId:'../b2'}),e=>e.code==='invalid-argument');
 await assert.rejects(call({list:'yes'}),e=>e.code==='invalid-argument');
});

test('a member limited to some buildings can only move leases there',async()=>{
 const {db,call}=moveSetup();
 db.store.set('memberships/m_o',{ownerId:'m',organizationId:'o',accessVersion:2,status:'active',role:'manager',buildingScope:'selected',buildingIds:['b1','b2']});
 const r=await call({list:true},'m');
 assert.deepEqual(r.buildings.map(b=>b.id),['b1','b2']);
 await assert.rejects(call({destinationBuildingId:'b3'},'m'),e=>e.code==='permission-denied');
});

test('staff names are read by ID; staff choices are remembered and forgotten after a change',async()=>{
 const db=fakeDb({'staffProfiles/s1':{organizationId:'o',displayName:'Anh'},'staffProfiles/s2':{organizationId:'o',displayName:'Binh',employmentStatus:'inactive'},
  'staffProfiles/s3':{organizationId:'o',displayName:'Chi'},'staffProfiles/x':{organizationId:'other',displayName:'Not ours'}});
 const get=r=>r.get();
 const names=await staffNames(get,db,'o',['s1','x','missing',undefined,'s1']);
 assert.deepEqual([...names],[['s1','Anh'],['x',''],['missing','']]);
 let reads=0;const counted=r=>{reads++;return r.get();};
 assert.deepEqual((await staffChoices(counted,db,'o',1000)).map(s=>s.id),['s1','s3']);
 db.store.set('staffProfiles/s4',{organizationId:'o',displayName:'Dung'});
 await staffChoices(counted,db,'o',20000);
 assert.equal(reads,1,'remembered for 30 s');
 forgetStaff('o');
 assert.deepEqual((await staffChoices(counted,db,'o',20000)).map(s=>s.id),['s1','s3','s4']);
 assert.equal(reads,2);
 assert.deepEqual((await staffChoices(counted,db,'o',60000)).length,3);
 assert.equal(reads,3,'read again after 30 s');
 // Another database (another test or project) never sees this one's copy.
 assert.deepEqual(await staffChoices(get,fakeDb({}),'o',60000),[]);
});
