// Prints where each project's Firestore database and functions run
// (2026-10-06, speed plan). Read-only. Run: node tool/where_is_data.cjs
const base='../functions/node_modules/firebase-tools/lib/';
async function main(){
 for(const project of ['apartment-management-staging','apartment-management-app-776b9']){
  try{
   await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
   const headers={Authorization:'Bearer '+await require(base+'apiv2').getAccessToken(),'x-goog-user-project':project};
   const get=async url=>{const r=await fetch(url,{headers,signal:AbortSignal.timeout(60000)});const v=await r.json();if(!r.ok)throw Error(`${r.status} ${v.error?.message}`);return v;};
   const db=await get(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)`);
   const fns=await get(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/-/functions?pageSize=200`);
   const regions=[...new Set((fns.functions??[]).map(f=>f.name.split('/')[3]))];
   console.log(JSON.stringify({project,firestore:db.locationId,functions:regions,count:(fns.functions??[]).length}));
  }catch(e){console.log(JSON.stringify({project,error:e.message}));}
 }
}
main();
