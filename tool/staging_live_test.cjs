const fs=require('node:fs'),crypto=require('node:crypto'),assert=require('node:assert/strict'),base='../functions/node_modules/firebase-tools/lib/';
const project='apartment-management-staging';
const dep=require('node:module').createRequire(require('node:path').resolve('functions/package.json'));
async function main(){
await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
const access=await require(base+'apiv2').getAccessToken();
const headers={Authorization:'Bearer '+access,'Content-Type':'application/json','x-goog-user-project':project};
async function api(url,method='GET',body,h=headers){const r=await fetch(url,{headers:h,method,...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)});const text=await r.text();let data;try{data=JSON.parse(text);}catch{data={};}return {status:r.status,data};}
const {initializeApp,deleteApp}=dep('firebase-admin/app'),{getAuth}=dep('firebase-admin/auth');
const app=initializeApp({projectId:project,credential:{getAccessToken:async()=>({access_token:access,expires_in:1800})}}),auth=getAuth(app);
const baseDoc=`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/`;
const value=v=>typeof v==='string'?{stringValue:v}:typeof v==='number'?{integerValue:String(v)}:typeof v==='boolean'?{booleanValue:v}:Array.isArray(v)?{arrayValue:{values:v.map(value)}}:{mapValue:{fields:Object.fromEntries(Object.entries(v).map(([k,x])=>[k,value(x)]))}};
const db={doc:path=>({set:async data=>{const r=await api(baseDoc+path,'PATCH',{fields:Object.fromEntries(Object.entries(data).map(([k,v])=>[k,value(v)]))});assert.equal(r.status,200,'fixture write');}}),batch:()=>{const paths=[];return {delete:path=>paths.push(path),commit:async()=>{for(const path of paths){const r=await api(baseDoc+path,'DELETE');assert([200,404].includes(r.status),'fixture cleanup');}}};},terminate:async()=>{}};
for(const user of (await auth.listUsers(100)).users.filter(u=>/^security_[a-f0-9]{10}$/.test(u.uid)&&u.email===`${u.uid}@example.invalid`))await auth.deleteUser(user.uid);
const config=JSON.parse(fs.readFileSync('.dart_tool/staging-web-config.json'));
const suffix=crypto.randomBytes(5).toString('hex'),uid='security_'+suffix,org='security_'+suffix,a=org+'_a',b=org+'_b',password=crypto.randomBytes(24).toString('base64url'),email=`${uid}@example.invalid`;
const docs=[`organizations/${org}`,`memberships/${uid}_${org}`,`buildings/${a}`,`buildings/${b}`],results=[];let debugName;
try{
 await auth.createUser({uid,email,password,emailVerified:true});
 const login=await api(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${config.apiKey}`,'POST',{email,password,returnSecureToken:true},{'Content-Type':'application/json'});assert.equal(login.status,200,'test sign-in');
 const idToken=login.data.idToken,debugToken=crypto.randomUUID(),appPath=`projects/933030543017/apps/${config.appId}`;
 const debug=await api(`https://firebaseappcheck.googleapis.com/v1/${appPath}/debugTokens`,'POST',{displayName:'Temporary restricted-IAM acceptance',token:debugToken});assert.equal(debug.status,200,'debug registration');debugName=debug.data.name;
 const exchange=await api(`https://firebaseappcheck.googleapis.com/v1/${appPath}:exchangeDebugToken?key=${config.apiKey}`,'POST',{debugToken},{'Content-Type':'application/json'});assert.equal(exchange.status,200,'App Check exchange');
 const appToken=exchange.data.token;
 const invoke=(name,data,attestation=appToken)=>api(`https://us-central1-${project}.cloudfunctions.net/${name}`,'POST',{data},{Authorization:'Bearer '+idToken,'Content-Type':'application/json',...(attestation?{'X-Firebase-AppCheck':attestation}:{})});
 await db.doc(docs[0]).set({name:'Temporary security acceptance',accessVersion:2,createdBy:uid});
 for(const id of [a,b])await db.doc(`buildings/${id}`).set({organizationId:org,name:'Synthetic property',timeZone:'Asia/Ho_Chi_Minh'});
 const member=(role,status='active')=>db.doc(docs[1]).set({ownerId:uid,organizationId:org,accessVersion:2,role,status,buildingScope:'selected',buildingIds:[a]});
 await member('owner');
 for(const token of [null,'invalid-token']){const r=await invoke('listMyOrganizations',{},token);assert.equal(r.status,401);results.push({case:token?'invalid-AppCheck':'missing-AppCheck',status:r.status});}
 const directory=await invoke('listMyOrganizations',{});assert.equal(directory.status,200);assert(directory.data.result.records.some(r=>r.id===org));results.push({case:'valid-auth-and-AppCheck',status:200});
 for(const role of ['owner','administrator','manager','receptionist','housekeeper','accountant','viewer']){
  await member(role);
  const own=await invoke('readWorkspace',{organizationId:org,view:'properties'});assert.equal(own.status,200);assert.deepEqual(own.data.result.records.map(r=>r.id),[a]);
  const financial=await invoke('readWorkspace',{organizationId:org,buildingId:a,view:'financial'});assert.equal(financial.status,['receptionist','housekeeper'].includes(role)?403:200);
  const foreign=await invoke('readWorkspace',{organizationId:org,buildingId:b,view:'financial'});assert.equal(foreign.status,403);
  results.push({case:'role-and-property-scope',role,own:own.status,financial:financial.status,otherProperty:foreign.status});
 }
 for(const state of ['suspended','revoked']){await member('owner',state);const r=await invoke('readWorkspace',{organizationId:org,view:'properties'});assert.equal(r.status,403);results.push({case:state+'-existing-token',status:r.status});}
 await member('member');assert.equal((await invoke('readWorkspace',{organizationId:org,view:'properties'})).status,403);results.push({case:'legacy-role-denied',status:403});
 await member('owner');
 const direct=await api(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/payments/${org}`,'PATCH',{fields:{organizationId:{stringValue:org}}},{Authorization:'Bearer '+idToken,'X-Firebase-AppCheck':appToken,'Content-Type':'application/json'});assert.equal(direct.status,403);results.push({case:'direct-financial-write-denied',status:403});
 fs.writeFileSync('.dart_tool/staging-live-acceptance.json',JSON.stringify({project,attestation:'temporary debug token; genuine browser attestation not tested',results},null,2));
 console.log(JSON.stringify({project,passed:results.length}));
}finally{
 if(debugName){const r=await api('https://firebaseappcheck.googleapis.com/v1/'+debugName,'DELETE');if(r.status!==200)throw Error('Debug-token cleanup failed');}
 const batch=db.batch();for(const path of docs)batch.delete(path);await batch.commit();
 await auth.deleteUser(uid);await db.terminate();await deleteApp(app);
}
}main().catch(e=>{console.error(e.name+': '+e.message);process.exitCode=1;});



