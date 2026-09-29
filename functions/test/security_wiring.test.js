'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
test('all exported callables pass through the common security boundary',()=>{
 const source=fs.readFileSync(path.join(__dirname,'../index.js'),'utf8');
 assert.equal(/functions\.https\.onCall\(/.test(source),false,
  'Direct callable registration bypasses shared App Check and abuse limits');
 assert.match(source,/createSecureCallable/);
});
test('provider failures do not copy private response bodies into broad logs',()=>{
 const source=fs.readFileSync(path.join(__dirname,'../index.js'),'utf8');
 assert.equal(source.includes('await response.text()'),false,'Provider response may echo private prompts or data');
});
