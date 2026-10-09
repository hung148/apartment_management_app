const {test}=require('node:test');
const assert=require('node:assert/strict');
const {normalizeRates,convertMinor,readReferenceRates,convertCalculation}=require('../reference_rates');
const {fakeDb}=require('./fake_firestore');
const {Ts,CodeError}=require('./fake_firestore');
const {createOrganizationCurrencyHandler}=require('../organization_currency');
test('reference snapshot identity is deterministic and conversion uses exact minor units',()=>{
 const rates=normalizeRates([{base:'USD',quote:'VND',rate:25000,date:'2026-10-08'}]);
 assert.equal(convertMinor(5000001,'VND','USD',rates),20000);
 assert.equal(convertMinor(20125,'USD','VND',rates),5031250);
 assert.equal(convertMinor(125,'VND','USD',rates),1);
 assert.equal(convertMinor(-125,'VND','USD',rates),-1);
 assert.equal(normalizeRates([{base:'USD',quote:'VND',rate:25000,date:'2026-10-08'}]).id,rates.id);
 assert.notEqual(normalizeRates([{base:'USD',quote:'VND',rate:25001,date:'2026-10-08'}]).id,rates.id);
 assert.throws(()=>convertMinor(1,'VND','USD',{}),/rates_unavailable/);
 assert.throws(()=>convertMinor(1.5,'USD','VND',rates),/invalid_amount/);
 assert.throws(()=>convertMinor(1e12,'USD','VND',rates),/invalid_amount/);
 for(const rate of [0,-1,NaN,Infinity,'25000'])assert.throws(()=>normalizeRates([{base:'USD',quote:'VND',rate,date:'2026-10-08'}]));
});
test('rate lookup authenticates before fetching, caches snapshots, and rechecks revoked access',async()=>{
 const db=fakeDb({'organizations/org':{accessVersion:2},'memberships/u_org':{accessVersion:2,organizationId:'org',ownerId:'u',status:'active',role:'owner',buildingScope:'all'}});
 let fetches=0;
 const api=createOrganizationCurrencyHandler({db,Timestamp:Ts,HttpsError:CodeError,fetchRates:async()=>{fetches++;return [{base:'USD',quote:'VND',rate:25000,date:'2026-10-08'}];}});
 const request={auth:{uid:'u'},data:{action:'readRates',organizationId:'org'}};
 await assert.rejects(api({...request,auth:{uid:'other'}}),e=>e.code==='permission-denied');
 assert.equal(fetches,0);
 const result=await api(request);assert.deepEqual(await api(request),result);assert.equal(fetches,1);
 assert.deepEqual(db.store.get(`referenceExchangeRates/${result.id}`),result);
 db.store.get('memberships/u_org').status='revoked';
 await assert.rejects(api(request),e=>e.code==='permission-denied');
 db.store.get('memberships/u_org').status='active';db.store.delete('referenceExchangeRateCache/latest');
 const revoking=createOrganizationCurrencyHandler({db,Timestamp:Ts,HttpsError:CodeError,fetchRates:async()=>{
  db.store.get('memberships/u_org').status='revoked';return [{base:'USD',quote:'VND',rate:26000,date:'2026-10-08'}];
 }});
 await assert.rejects(revoking(request),e=>e.code==='permission-denied');
 assert.equal([...db.store.keys()].filter(k=>k.startsWith('referenceExchangeRates/')).length,1);
});
test('billing resolves only persisted snapshot identifiers',async()=>{
 const rates=normalizeRates([{base:'USD',quote:'VND',rate:25000,date:'2026-10-08'}]);
 const db=fakeDb({[`referenceExchangeRates/${rates.id}`]:rates}),tx={get:ref=>ref.get()};
 assert.deepEqual(await readReferenceRates(tx,db,rates.id),rates);
 await assert.rejects(readReferenceRates(tx,db,{perUsd:{VND:'1'}}),/rates_required/);
 await assert.rejects(readReferenceRates(tx,db,'a'.repeat(64)),/rates_required/);
});

test('converted line totals reconcile while quantities and original calculations remain exact',()=>{
 const rates=normalizeRates([{base:'USD',quote:'VND',rate:25000,date:'2026-10-08'}]);
 const original={currency:'VND',amountMinor:250,periodDays:31,months:[1,1],lines:[
  {amountMinor:125,quantityMilli:1000,days:15},{amountMinor:125,quantityMilli:2000,days:16},
 ],terms:{rateMinor:125,includedPeople:2,rule:{mode:'steps',steps:[{minDays:15,percent:50}]}}};
 const before=structuredClone(original),result=convertCalculation(original,'USD',rates);
 assert.equal(result.amountMinor,2,'sum of rounded billable lines is the charged total');
 assert.deepEqual(result.lines.map(l=>l.amountMinor),[1,1]);
 assert.deepEqual(result.lines.map(l=>l.quantityMilli),[1000,2000]);
 assert.deepEqual(result.months,[1,1]);assert.equal(result.periodDays,31);
 assert.deepEqual(result.terms.rule,original.terms.rule);assert.equal(result.terms.includedPeople,2);
 assert.deepEqual(result.sourceCalculation,before);assert.deepEqual(original,before);
 assert.throws(()=>convertCalculation({currency:'VND',amountMinor:1},'USD',rates),/amount_too_small/);
});
