'use strict';
// Minimal in-memory Firestore for unit tests: transactions, batches, paged and
// 'in'/range queries, subcollections, listCollections and recursiveDelete.
class CodeError extends Error {constructor(code,message){super(message);this.code=code;}}
class Ts {constructor(ms){this.ms=ms;} toMillis(){return this.ms;} toDate(){return new Date(this.ms);}
  static now(){return new Ts(Ts.clock);} static fromMillis(ms){return new Ts(ms);}}
Ts.clock=Date.parse('2026-09-28T12:00:00Z');
const cmp=(a,b)=>{const x=a?.toMillis?a.toMillis():a,y=b?.toMillis?b.toMillis():b;return x<y?-1:x>y?1:0;};
function fakeDb(seed={}){
  const store=new Map(Object.entries(seed).map(([k,v])=>[k,{...v}]));
  const db={store,calls:0};
  const ref=path=>({path,id:path.split('/').pop(),collection:name=>collection(`${path}/${name}`),
    get:async()=>snap(ref(path)),update:async v=>apply([['update',ref(path),v]]),
    set:async(v,o)=>apply([[o?.merge?'update-or-set':'set',ref(path),v]]),delete:async()=>apply([['delete',ref(path)]])});
  const snap=r=>{const d=store.get(r.path);return {ref:r,id:r.id,exists:d!==undefined,data:()=>d&&{...d}};};
  const ops={'==':(a,b)=>a!==undefined&&cmp(a,b)===0,'<=':(a,b)=>a!==undefined&&cmp(a,b)<=0,'in':(a,b)=>b.includes(a)};
  function collection(name){
    const depth=name.split('/').length+1;
    const make=state=>({
      doc:id=>ref(`${name}/${id}`),
      where:(f,op,v)=>make({...state,filters:[...state.filters,[f,op,v]]}),
      orderBy:f=>make({...state,order:f}),
      limit:n=>make({...state,max:n}),
      startAfter:doc=>make({...state,after:doc}),
      get:async()=>{
        let docs=[...store.keys()].filter(p=>p.startsWith(name+'/')&&p.split('/').length===depth).map(p=>snap(ref(p)))
          .filter(s=>state.filters.every(([f,op,v])=>ops[op](s.data()[f],v)));
        const key=s=>state.order&&state.order!=='__name__'?s.data()[state.order]:s.id;
        docs.sort((a,b)=>cmp(key(a),key(b))||cmp(a.id,b.id));
        if(state.after)docs=docs.filter(s=>cmp(key(s),key(state.after))>0||(cmp(key(s),key(state.after))===0&&s.id>state.after.id));
        docs=docs.slice(0,state.max);
        return {docs,size:docs.length,empty:!docs.length};
      }});
    return make({filters:[],order:null,max:Infinity,after:null});
  }
  function apply(writes){for(const [m,r,v] of writes){
    if(m==='create'&&store.has(r.path))throw new CodeError('already-exists','create');
    if(m==='update'&&!store.has(r.path))throw new CodeError('not-found','update');
    if(m==='delete'){store.delete(r.path);continue;}
    if(m==='update-or-set'){store.set(r.path,{...(store.get(r.path)??{}),...v});continue;}
    store.set(r.path,m==='update'?{...store.get(r.path),...v}:{...v});}}
  Object.assign(db,{
    collection,doc:path=>ref(path),
    batch(){const w=[];return {set:(r,v)=>w.push(['set',r,v]),update:(r,v)=>w.push(['update',r,v]),delete:r=>w.push(['delete',r]),commit:async()=>{db.calls++;apply(w);}};},
    async runTransaction(fn){const w=[];const tx={get:async r=>r.get(),
      create:(r,v)=>w.push(['create',r,v]),update:(r,v)=>w.push(['update',r,v]),set:(r,v)=>w.push(['set',r,v])};
      const out=await fn(tx);apply(w);return out;},
    async listCollections(){return [...new Set([...store.keys()].map(p=>p.split('/')[0]))].map(id=>({id}));},
    bulkWriter(){return {close:async()=>{}};},
    async recursiveDelete(r){for(const p of [...store.keys()])if(p===r.path||p.startsWith(r.path+'/'))store.delete(p);},
  });
  return db;
}
module.exports={fakeDb,Ts,CodeError};
