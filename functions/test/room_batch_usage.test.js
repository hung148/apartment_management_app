const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createPropertyDetailsHandler}=require('../property_details');
const {createBulkRoomsHandler}=require('../bulk_rooms');
const room=i=>({roomNumber:'N'+i,roomType:'Studio',area:25,ratesMinor:{roomPrice:null,nightlyPrice:null,hourlyPrice:null}});
for(const kind of ['property','bulk']) test(`${kind}: 200 rooms use no redundant target reads and retry writes once`,async()=>{
 const db=fakeDb({'organizations/org':{accessVersion:2},'memberships/owner_org':{organizationId:'org',ownerId:'owner',accessVersion:2,role:'owner',status:'active',buildingScope:'all'},'buildings/b':{organizationId:'org',currency:'VND'}});
 const readPaths=[];const original=db.runTransaction;
 db.runTransaction=fn=>original(tx=>fn({...tx,get:ref=>{readPaths.push(ref.path??'query');return tx.get(ref);}}));
 const deps={db,Timestamp:Ts,HttpsError:CodeError};
 const api=kind==='property'?createPropertyDetailsHandler(deps):createBulkRoomsHandler(deps);
 const data={organizationId:'org',buildingId:kind==='property'?'new':'b',operationId:'op',rooms:Array.from({length:200},(_,i)=>room(i)),...(kind==='property'?{action:'create',name:'New',address:'',timeZone:'UTC',currency:'VND'}:{action:'createBulk'})};
 const run=()=>api({auth:{uid:'owner'},data});await run();await run();
 assert.equal([...db.store.keys()].filter(k=>k.startsWith('rooms/')).length,200);
 assert.equal(readPaths.filter(p=>p.startsWith('rooms/')).length,0);
 assert.equal([...db.store.keys()].filter(k=>k.startsWith('teamActivity/')).length,kind==='property'?201:200);
});
