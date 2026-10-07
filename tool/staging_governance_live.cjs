'use strict';
// Disposable synthetic identities; only the fixed staging project is reachable.
// Never prints credentials. Browser UI verification is separate from these
// callable tests (which use a temporary registered App Check debug token).
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const project='apartment-management-staging',base='../functions/node_modules/firebase-tools/lib/';
const dep=require('node:module').createRequire(path.resolve('functions/package.json'));
async function main(){
 await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
 const access=await require(base+'apiv2').getAccessToken();
 const adminHeaders={Authorization:'Bearer '+access,'Content-Type':'application/json','x-goog-user-project':project};
 const api=async(url,method='GET',body,headers=adminHeaders)=>{const r=await fetch(url,{method,headers,...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(60000)});let data={};try{data=await r.json();}catch{}return {status:r.status,data};};
 const {initializeApp,deleteApp}=dep('firebase-admin/app'),{getAuth}=dep('firebase-admin/auth'),{getFirestore}=dep('firebase-admin/firestore');
 const app=initializeApp({projectId:project,credential:{getAccessToken:async()=>({access_token:access,expires_in:1800})}}),auth=getAuth(app);
 const {Firestore}=dep('@google-cloud/firestore');
 const gaxRequire=require('node:module').createRequire(dep.resolve('google-gax',{paths:[path.dirname(dep.resolve('@google-cloud/firestore'))]}));
 const {OAuth2Client}=gaxRequire('google-auth-library');
 const authClient=new OAuth2Client();authClient.setCredentials({access_token:access,expiry_date:Date.now()+50*60000});
 const db=new Firestore({projectId:project,authClient});
 const config=JSON.parse(fs.readFileSync('.dart_tool/staging-web-config.json','utf8'));
 const suffix=crypto.randomBytes(6).toString('hex'),users={},orgs=[],results=[];let debugName;
 const controls={manageCoOwners:'joint',shareStaff:'joint',closeOrganization:'joint',transferOwnership:'joint'};
 try{
  const debugToken=crypto.randomUUID(),appPath=`projects/933030543017/apps/${config.appId}`;
  const debug=await api(`https://firebaseappcheck.googleapis.com/v1/${appPath}/debugTokens`,'POST',{displayName:'Temporary agreement verification',token:debugToken});assert.equal(debug.status,200);debugName=debug.data.name;
  const attestation=await api(`https://firebaseappcheck.googleapis.com/v1/${appPath}:exchangeDebugToken?key=${config.apiKey}`,'POST',{debugToken},{'Content-Type':'application/json'});assert.equal(attestation.status,200);
  for(const role of ['source','destination','partner','employee']){
   const uid=`agreements_${suffix}_${role}`,email=uid+'@example.invalid',password=crypto.randomBytes(24).toString('base64url');
   await auth.createUser({uid,email,password,emailVerified:true});users[role]={uid,email};
   const login=await api(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${config.apiKey}`,'POST',{email,password,returnSecureToken:true},{'Content-Type':'application/json'});assert.equal(login.status,200);users[role].token=login.data.idToken;
  }
  let seq=0;
  const invoke=async(role,name,data,ok=true)=>{
   const r=await api(`https://${require('../functions/region').REGION}-${project}.cloudfunctions.net/${name==='importSheet'?'heavy':'app'}`,'POST',{data:{fn:name,data}},{Authorization:'Bearer '+users[role].token,'Content-Type':'application/json','X-Firebase-AppCheck':attestation.data.token});
   console.log(JSON.stringify({check:name,action:data.action??'read',status:r.status}));
   if(ok)assert.equal(r.status,200,`${name}/${data.action}: ${JSON.stringify(r.data.error??{})}`);else assert.ok(r.status>=400,`${name} must deny`);
   return r.data.result??r.data.error;
  };
  const write=(role,name,data,ok=true)=>invoke(role,name,{operationId:`live_${suffix}_${++seq}`,...data},ok);
  if(process.argv.includes('--retired-ai')){
   for(const name of ['aiChat','aiUsage','aiImportPreview','aiImportCommit','aiSyncSubscription']){
    const error=await invoke('source',name,{draftId:'historical-draft',records:[]},false);
    assert.equal(error.message,'feature_retired');results.push(name+' is retired');
   }
   const webhook=await api(`https://${require('../functions/region').REGION}-${project}.cloudfunctions.net/revenueCatWebhook`,'POST',{event:{id:'synthetic-retired-event'}},{'Content-Type':'application/json'});
   assert.equal(webhook.status,410);assert.equal(webhook.data.error,'feature_retired');results.push('webhook is retired');
   fs.writeFileSync('.dart_tool/ai-removal-live-report.json',JSON.stringify({project,results,checkedAt:new Date().toISOString()},null,2));console.log(JSON.stringify({project,passed:results.length}));return;
  }
  const fields=name=>({name,address:'',phone:'',email:'',taxCode:'',bankName:'',bankAccountNumber:'',bankAccountName:''});
  const source=(await write('source','organizationSettings',{action:'create',fields:fields('Synthetic agreement source')})).organizationId;orgs.push(source);
  if(process.argv.includes('--utilities')){
   const buildingId='utility_b_'+suffix,roomId='utility_r_'+suffix,tenantId='utility_t_'+suffix;
   const {Timestamp}=dep('firebase-admin/firestore');
   await db.doc('buildings/'+buildingId).set({organizationId:source,name:'Synthetic utility property',currency:'VND',timeZone:'Asia/Ho_Chi_Minh'});
   await db.doc('rooms/'+roomId).set({organizationId:source,buildingId,roomNumber:'Utility test 101'});
   await db.doc('tenants/'+tenantId).set({organizationId:source,buildingId,roomId,isMainTenant:true,fullName:'Synthetic utility tenant',currency:'VND',moveInDate:Timestamp.fromDate(new Date('2026-08-01T00:00:00Z'))});
   const scope={organizationId:source,buildingId,roomId,kind:'electricity'};
   const meter=d=>write('source','utilityReadings',{...scope,reason:'Synthetic verification',...d});
   await meter({action:'record',revision:0,date:'2026-09-01',readingMilli:100000});
   await meter({action:'tariff',revision:1,propertyRevision:0,tariffScope:'property',effectiveDate:'2026-09-01',tariff:{currency:'VND',bands:[{throughMilli:10000,priceMinor:3000},{throughMilli:null,priceMinor:4000}]}});
   const measured=await meter({action:'record',revision:2,date:'2026-10-01',readingMilli:125000});assert.equal(measured.calculation.amountMinor,90000);results.push('property tiered price produces exact measured charge');
   const payload={organizationId:source,buildingId,roomId,kind:'utility',tenantId,readingId:measured.readingId,chargeType:'electricity',startDate:'2026-09-01',endDate:'2026-10-01',dueDate:'2026-10-02',feesMinor:{internetFee:0,cableTVFee:0,hotWaterFee:0,lateFee:0,taxAmount:0},reason:'Synthetic meter invoice'};
   const quote=await invoke('source','invoices',{action:'quote',...payload});assert.equal(quote.record.totalMinor,90000);
   const created=await write('source','invoices',{action:'create',...payload,quoteRevision:quote.record.quoteRevision});assert.ok(created.invoiceId);results.push('invoice uses saved meter calculation');
   const denied=await invoke('source','invoices',{action:'quote',...payload},false);assert.equal(denied.message,'utility_already_billed');results.push('duplicate meter billing denied');
   const outsider=await invoke('employee','utilityReadings',{action:'read',...scope},false);assert.equal(outsider.status,'PERMISSION_DENIED');results.push('outsider cannot read meter history');
   const view=await invoke('source','utilityReadings',{action:'read',...scope});assert.equal(view.records.find(x=>x.id===measured.readingId).invoiceId,created.invoiceId);results.push('history retains invoice link');
   fs.writeFileSync('.dart_tool/utility-live-report.json',JSON.stringify({project,results,attestation:'Temporary debug token; separate from browser verification',checkedAt:new Date().toISOString()},null,2));console.log(JSON.stringify({project,passed:results.length}));return;
  }
  const destination=(await write('destination','organizationSettings',{action:'create',fields:fields('Synthetic agreement destination')})).organizationId;orgs.push(destination);
  const grant={role:'receptionist',buildingScope:'all',buildingIds:[],permissionOverrides:{}};
  const add=(role,org,ok=true)=>write(role,'mutateTeam',{organizationId:org,action:'addStaff',profile:{displayName:'Synthetic employee',email:users.employee.email},access:grant},ok);
  await add('source',source);await invoke('employee','claimMyInvitations',{});
  assert.match((await add('destination',destination,false)).message,/team_other_employer/);results.push('unapproved cross-company invitation refused');
  const ownerAgreement=await write('source','ownershipAgreements',{organizationId:source,action:'propose',kind:'coOwner',recipientEmail:users.partner.email,grants:{readBookings:'all',readOwnActivity:'all'},controls});
  assert.equal((await invoke('partner','ownershipAgreements',{action:'list'})).records.some(r=>r.id===ownerAgreement.agreementId),true);
  await write('partner','ownershipAgreements',{action:'approve',agreementId:ownerAgreement.agreementId});
  const own=(await invoke('partner','readTeam',{organizationId:source,view:'myAccess'})).record;assert.equal(own.role,'coOwner');assert.equal(own.grants.manageTeam,undefined);results.push('co-owner explicitly accepted only offered grants');
  assert.match((await write('source','organizationSettings',{organizationId:source,action:'close',confirmName:'Synthetic agreement source'},false)).message,/agreement_joint_required/);results.push('ordinary closure cannot bypass joint consent');
  const share=await write('source','ownershipAgreements',{organizationId:source,action:'propose',kind:'shareStaff',targetOrganizationId:destination,staffEmail:users.employee.email,durationDays:30});
  assert.equal((await write('destination','ownershipAgreements',{action:'approve',agreementId:share.agreementId})).status,'pending');
  await add('destination',destination,false);
  assert.equal((await write('partner','ownershipAgreements',{action:'approve',agreementId:share.agreementId})).status,'active');
  await add('destination',destination);await invoke('employee','claimMyInvitations',{});
  const directory=await invoke('employee','listMyOrganizations',{});assert.equal(directory.accountPolicy.mode,'staff');assert.equal(directory.records.length,2);results.push('all owners consent before staff can join both companies');
  await write('partner','ownershipAgreements',{action:'revokeShare',agreementId:share.agreementId});
  const remaining=await invoke('employee','listMyOrganizations',{});assert.deepEqual(remaining.records.map(r=>r.id),[source]);results.push('ending sharing preserves source employment and blocks destination');
  const close=await write('source','ownershipAgreements',{organizationId:source,action:'propose',kind:'closeOrganization',confirmName:'Synthetic agreement source'});
  await write('partner','ownershipAgreements',{action:'approve',agreementId:close.agreementId});await write('source','ownershipAgreements',{action:'execute',agreementId:close.agreementId});results.push('joint approved closure executes');
  fs.writeFileSync('.dart_tool/governance-live-report.json',JSON.stringify({project,results,attestation:'Temporary debug token; browser UI checked separately',checkedAt:new Date().toISOString()},null,2));
  console.log(JSON.stringify({project,passed:results.length}));
 }catch(error){console.error('Live assertion: '+error.message);throw error;}finally{
  // Exact synthetic IDs only. This never enumerates or deletes real users.
  const collections=await db.listCollections();
  for(const collection of collections){
   const docs=new Map();
   const queries=[...orgs.flatMap(org=>['organizationId','orgId','sourceOrganizationId','targetOrganizationId'].map(field=>collection.where(field,'==',org))),...Object.values(users).flatMap(u=>['ownerId','actorId'].map(field=>collection.where(field,'==',u.uid)))];
   for(const rows of await Promise.all(queries.map(query=>query.get())))for(const d of rows.docs)docs.set(d.id,d);
   for(const d of docs.values())await db.recursiveDelete(d.ref);
  }
  for(const org of orgs)await db.doc('organizations/'+org).delete();
  for(const u of Object.values(users)){
   for(const key of ['uid:'+u.uid,'email:'+u.email])await db.doc('accountPolicyLocks/'+crypto.createHash('sha256').update(key).digest('hex')).delete();
   await auth.deleteUser(u.uid);
  }
  if(debugName)await api('https://firebaseappcheck.googleapis.com/v1/'+debugName,'DELETE');
  await db.terminate();await deleteApp(app);
 }
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
