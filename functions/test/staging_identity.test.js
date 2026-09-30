const {test}=require('node:test'),assert=require('node:assert/strict'),{execFileSync}=require('node:child_process');
test('staging entrypoint refuses other projects',()=>{
 assert.throws(()=>execFileSync(process.execPath,['-e',"require('./staging_index')"],{cwd:require('node:path').join(__dirname,'..'),env:{...process.env,GCLOUD_PROJECT:'wrong-project'},stdio:'pipe'}),e=>e.stderr.toString().includes('Staging project required'));
});
test('staging endpoints use explicit identities and no provider secrets',()=>{
 const result=JSON.parse(execFileSync(process.execPath,['-e',"console.log(JSON.stringify(Object.fromEntries(Object.entries(require('./staging_index')).map(([n,f])=>[n,f.__endpoint]))))"],{cwd:require('node:path').join(__dirname,'..'),env:{...process.env,GCLOUD_PROJECT:'apartment-management-staging'},encoding:'utf8'}));
 assert.equal(Object.keys(result).length,34);
 for(const [name,e] of Object.entries(result)){
 const expected=['aiChat','aiImportPreview'].includes(name)?'app-ai-runtime':['aiSyncSubscription','revenueCatWebhook'].includes(name)?'app-billing-runtime':'app-functions-runtime';
 assert.equal(e.serviceAccountEmail,`${expected}@apartment-management-staging.iam.gserviceaccount.com`);
 assert(!e.secretEnvironmentVariables?.length);
 }
});
