'use strict';
// Minimal in-memory Firestore for unit tests: transactions, batches, paged and
// 'in'/range queries, subcollections, listCollections and recursiveDelete.
class CodeError extends Error {constructor(code,message){super(message);this.code=code;}}
class Ts {constructor(ms){this.ms=ms;} toMillis(){return this.ms;} toDate(){return new Date(this.ms);}
  static now(){return new Ts(Ts.clock);} static fromMillis(ms){return new Ts(ms);}}
Ts.clock=Date.parse('2026-09-28T12:00:00Z');
// Field-delete sentinel for update(): removes the key.
const DELETE=Symbol('delete');
const cmp=(a,b)=>{const x=a?.toMillis?a.toMillis():a,y=b?.toMillis?b.toMillis():b;return x<y?-1:x>y?1:0;};
function fakeDb(seed={}){
  const store=new Map(Object.entries(seed).map(([k,v])=>[k,{...v}]));
  const db={store,calls:0};let autoId=0;
  const ref=path=>({path,id:path.split('/').pop(),collection:name=>collection(`${path}/${name}`),
    listCollections:async()=>[...new Set([...store.keys()].filter(p=>p.startsWith(path+'/')&&p.split('/').length===path.split('/').length+2).map(p=>p.split('/')[path.split('/').length]))].map(id=>({id,get:async()=>collection(`${path}/${id}`).get()})),
    get:async()=>snap(ref(path)),update:async v=>apply([['update',ref(path),v]]),
    set:async(v,o)=>apply([[o?.merge?'update-or-set':'set',ref(path),v]]),delete:async()=>apply([['delete',ref(path)]])});
  const snap=r=>{const d=store.get(r.path);return {ref:r,id:r.id,exists:d!==undefined,data:()=>d&&{...d},updateTime:{seconds:0,nanoseconds:0}};};
  // Range filters skip missing and null fields, as Firestore does (2026-10-10).
  const has=a=>a!==undefined&&a!==null;
  const ops={'==':(a,b)=>a!==undefined&&cmp(a,b)===0,'<=':(a,b)=>a!==undefined&&cmp(a,b)<=0,'<':(a,b)=>has(a)&&cmp(a,b)<0,'>':(a,b)=>has(a)&&cmp(a,b)>0,'>=':(a,b)=>has(a)&&cmp(a,b)>=0,'in':(a,b)=>b.includes(a)};
  function collection(name){
    const depth=name.split('/').length+1;
    const make=state=>({
      doc:id=>ref(`${name}/${id??`auto${++autoId}`}`),
      where:(f,op,v)=>make({...state,filters:[...state.filters,[f,op,v]]}),
      orderBy:(f,dir)=>make({...state,order:f,desc:dir==='desc'}),
      limit:n=>make({...state,max:n}),
      startAfter:doc=>make({...state,after:typeof doc==='string'?{id:doc,data:()=>({})}:doc}),
      get:async()=>{
        let docs=[...store.keys()].filter(p=>p.startsWith(name+'/')&&p.split('/').length===depth).map(p=>snap(ref(p)))
          .filter(s=>state.filters.every(([f,op,v])=>ops[op](s.data()[f],v)));
        const key=s=>state.order&&state.order!=='__name__'?s.data()[state.order]:s.id;
        // Ordering by a field leaves out records without it, as Firestore does.
        if(state.order&&state.order!=='__name__')docs=docs.filter(s=>s.data()[state.order]!==undefined);
        const order=(a,b)=>(state.desc?-1:1)*(cmp(key(a),key(b))||cmp(a.id,b.id));
        docs.sort(order);
        if(state.after)docs=docs.filter(s=>order(s,state.after)>0);
        docs=docs.slice(0,state.max);
        return {docs,size:docs.length,empty:!docs.length};
      }});
    return make({filters:[],order:null,max:Infinity,after:null});
  }
  function apply(writes){
    // Firestore commits atomically: check all existence preconditions first.
    const present=new Set(store.keys());
    for(const [m,r] of writes){
      if(m==='create'&&present.has(r.path))throw new CodeError('already-exists','create');
      if(m==='update'&&!present.has(r.path))throw new CodeError('not-found','update');
      if(m==='delete')present.delete(r.path);else present.add(r.path);
    }
    for(const [m,r,v] of writes){
    if(m==='create'&&store.has(r.path))throw new CodeError('already-exists','create');
    if(m==='update'&&!store.has(r.path))throw new CodeError('not-found','update');
    if(m==='delete'){store.delete(r.path);continue;}
    if(m==='update-or-set'){store.set(r.path,{...(store.get(r.path)??{}),...v});continue;}
    const next=m==='update'?{...store.get(r.path),...v}:{...v};
    for(const k of Object.keys(next))if(next[k]===DELETE)delete next[k];
    store.set(r.path,next);}}
  Object.assign(db,{
    collection,doc:path=>ref(path),
    batch(){const w=[];return {create:(r,v)=>w.push(['create',r,v]),set:(r,v)=>w.push(['set',r,v]),update:(r,v)=>w.push(['update',r,v]),delete:r=>w.push(['delete',r]),commit:async()=>{db.calls++;apply(w);}};},
    async runTransaction(fn){const w=[];const tx={get:async r=>r.get(),
      create:(r,v)=>w.push(['create',r,v]),update:(r,v)=>w.push(['update',r,v]),set:(r,v)=>w.push(['set',r,v]),delete:r=>w.push(['delete',r])};
      const out=await fn(tx);apply(w);return out;},
    async listCollections(){return [...new Set([...store.keys()].map(p=>p.split('/')[0]))].map(id=>({id}));},
    bulkWriter(){const w=[];return {create:(r,v)=>{w.push(['create',r,v]);},close:async()=>apply(w)};},
    async recursiveDelete(r){for(const p of [...store.keys()])if(p===r.path||p.startsWith(r.path+'/'))store.delete(p);},
  });
  return db;
}
module.exports={fakeDb,Ts,CodeError,DELETE};
