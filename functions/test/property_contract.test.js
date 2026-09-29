const {test}=require('node:test');
const assert=require('node:assert/strict');
const {validContract,validDate}=require('../property_contract');
const sample=()=>({direction:'rentIn',status:'active',partyName:'Landlord',partyPhone:'0901',amountMinor:12345,dueDay:31,startDate:'2030-01-01',endDate:null,notes:''});
test('contract validates both directions, money bounds and calendar dates without host timezone',()=>{
  assert.ok(validContract(sample()));assert.ok(validContract({...sample(),direction:'rentOut',status:'ended',endDate:'2030-12-31'}));
  for(const patch of [{direction:'rented'},{status:'deleted'},{partyName:' '},{partyPhone:'x'.repeat(81)},{amountMinor:0},{amountMinor:1.1},{amountMinor:1e12+1},{dueDay:0},{dueDay:32},{dueDay:1.5},{startDate:'2030-02-30'},{endDate:'2029-12-31'},{status:'ended'},{notes:'x'.repeat(2001)},{createdAt:0}])assert.equal(validContract({...sample(),...patch}),false,JSON.stringify(patch));
  assert.ok(validDate('2032-02-29'));for(const d of ['2030-02-29','2030-99-99','1999-01-01','2200-01-01','2030-1-01'])assert.equal(validDate(d),false);
});
