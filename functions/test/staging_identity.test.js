const {test}=require('node:test'),assert=require('node:assert/strict'),{execFileSync}=require('node:child_process');
test('staging entrypoint refuses other projects',()=>{
 assert.throws(()=>execFileSync(process.execPath,['-e',"require('./staging_index')"],{cwd:require('node:path').join(__dirname,'..'),env:{...process.env,GCLOUD_PROJECT:'wrong-project'},stdio:'pipe'}),e=>e.stderr.toString().includes('Staging project required'));
});
test('staging endpoints use explicit identities and no provider secrets',()=>{
 const result=JSON.parse(execFileSync(process.execPath,['-e',"console.log(JSON.stringify(Object.fromEntries(Object.entries(require('./staging_index')).map(([n,f])=>[n,f.__endpoint]))))"],{cwd:require('node:path').join(__dirname,'..'),env:{...process.env,GCLOUD_PROJECT:'apartment-management-staging'},encoding:'utf8'}));
 // Grouped functions (2026-10-06): app, heavy, the nightly purge and the webhook.
 assert.deepEqual(Object.keys(result).sort(),['app','heavy','purgeClosedOrganizations','revenueCatWebhook']);
 for(const [name,e] of Object.entries(result)){
 const expected='app-functions-runtime';
 assert.equal(e.serviceAccountEmail,`${expected}@apartment-management-staging.iam.gserviceaccount.com`);
 assert(!e.secretEnvironmentVariables?.length);
 }
});
