'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
test('all exported callables pass through the common security boundary',()=>{
 const source=fs.readFileSync(path.join(__dirname,'../index.js'),'utf8');
 assert.equal(/functions\.https\.onCall\(/.test(source),false,
  'Direct callable registration bypasses shared App Check and abuse limits');
 assert.match(source,/createCallableGroups/);
});
test('provider failures do not copy private response bodies into broad logs',()=>{
 const source=fs.readFileSync(path.join(__dirname,'../index.js'),'utf8');
 assert.equal(source.includes('await response.text()'),false,'Provider response may echo private prompts or data');
});
test('the Firestore transport is a deliberate choice and the server uses no listeners',()=>{
 const dir=path.join(__dirname,'..');
 const source=fs.readFileSync(path.join(dir,'index.js'),'utf8');
 assert.match(source,/const FIRESTORE_OVER_REST=false;/,'gRPC measured faster for warm calls (2026-10-10)');
 // A snapshot listener would quietly bring gRPC (and its cold-start cost) back.
 for(const file of fs.readdirSync(dir).filter(f=>f.endsWith('.js')))
  assert.equal(fs.readFileSync(path.join(dir,file),'utf8').includes('.onSnapshot('),false,file);
});
