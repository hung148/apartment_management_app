const {test}=require('node:test');
const assert=require('node:assert/strict');
const {withinHours,validZone}=require('../booking_settings');
const window=(a,b)=>({operatingHoursStartMin:a,operatingHoursEndMin:b});
const fits=(a,b,h,z)=>withinHours(Date.parse(a),Date.parse(b),h,z);
const {validSchedule}=require('../operating_schedule');
const schedule=()=>({week:Object.fromEntries(Array.from({length:7},(_,i)=>[i,[{start:480,end:720},{start:840,end:1320}]])),exceptions:{}});
test('weekly schedules and date exceptions enforce individual windows and restore the recurring day',()=>{
  const s=schedule(),h={operatingSchedule:s},z='Asia/Ho_Chi_Minh';
  s.week[6]=[];
  assert.ok(validSchedule(s));
  assert.ok(fits('2030-01-07T01:00Z','2030-01-07T05:00Z',h,z)); // Monday 08–12
  assert.ok(!fits('2030-01-07T04:00Z','2030-01-07T08:00Z',h,z));
  assert.ok(!fits('2030-01-06T01:00Z','2030-01-06T02:00Z',h,z)); // Sunday closed
  s.exceptions['2030-01-07']=[{start:600,end:1020}];
  assert.ok(!fits('2030-01-07T01:00Z','2030-01-07T02:00Z',h,z));
  assert.ok(fits('2030-01-07T03:00Z','2030-01-07T10:00Z',h,z));
  assert.ok(!fits('2030-01-07T03:00Z','2030-01-07T10:00:00.001Z',h,z));
  s.exceptions['2030-01-07']=[];
  assert.ok(!fits('2030-01-07T03:00Z','2030-01-07T04:00Z',h,z));
  delete s.exceptions['2030-01-07'];
  assert.ok(fits('2030-01-07T01:00Z','2030-01-07T05:00Z',h,z));
});
test('calendar-date exception replaces overnight carry; weekly closed day still permits prior overnight window',()=>{
  const s={week:Object.fromEntries(Array.from({length:7},(_,i)=>[i,[]])),exceptions:{}};
  s.week[6]=[{start:1320,end:360}];
  const h={operatingSchedule:s};
  assert.ok(fits('2030-01-06T22:00Z','2030-01-07T06:00Z',h,'UTC'));
  s.exceptions['2030-01-07']=[];
  assert.ok(!fits('2030-01-06T22:00Z','2030-01-07T06:00Z',h,'UTC'));
  assert.ok(fits('2030-01-06T22:00Z','2030-01-07T00:00Z',h,'UTC'));
  s.exceptions['2030-01-07']=[{start:600,end:1080}];
  assert.ok(!fits('2030-01-07T01:00Z','2030-01-07T02:00Z',h,'UTC'));
  assert.ok(fits('2030-01-07T10:00Z','2030-01-07T18:00Z',h,'UTC'));
});
test('schedule validates malformed dates, bounded windows, duplicates and cross-midnight overlaps',()=>{
  for(const mutate of [s=>delete s.week[6],s=>s.extra=true,s=>s.week[0]=[{start:600,end:600}],s=>s.week[0]=[{start:0,end:1441}],s=>s.week[0]=Array(7).fill({start:1,end:2}),s=>s.week[0]=[{start:480,end:720},{start:600,end:840}],s=>s.exceptions['2030-02-30']=[],s=>s.exceptions['2030-99-99']=[],s=>s.exceptions['2030-01-07']=[{start:1320,end:600}]]){
    const s=schedule();mutate(s);assert.equal(validSchedule(s),false);
  }
  const s=schedule();s.week[6]=[{start:1320,end:600}];assert.equal(validSchedule(s),false);
  s.week[0]=[{start:600,end:720}];assert.ok(validSchedule(s));
  const h={operatingSchedule:{week:null,exceptions:{}}};assert.equal(fits('2030-01-07T00:00Z','2030-01-07T01:00Z',h,'UTC'),false);
});
test('scheduled overnight hours and exceptions handle DST folds, spring skips and year boundaries',()=>{
  const s={week:Object.fromEntries(Array.from({length:7},(_,i)=>[i,[{start:1320,end:360}]])),exceptions:{}};
  const h={operatingSchedule:s};
  assert.ok(fits('2030-03-10T03:00Z','2030-03-10T10:00Z',h,'America/New_York'));
  assert.ok(fits('2030-11-03T02:00Z','2030-11-03T11:00Z',h,'America/New_York'));
  s.exceptions['2030-11-03']=[];
  assert.ok(!fits('2030-11-03T02:00Z','2030-11-03T11:00Z',h,'America/New_York'));
  s.exceptions['2030-11-02']=[{start:1320,end:90}];delete s.exceptions['2030-11-03'];
  assert.ok(!fits('2030-11-03T02:00Z','2030-11-03T06:15Z',h,'America/New_York'));
  assert.ok(fits('2030-12-31T22:00Z','2031-01-01T06:00Z',h,'UTC'));
  s.exceptions['2031-01-01']=[];
  assert.ok(!fits('2030-12-31T22:00Z','2031-01-01T06:00Z',h,'UTC'));
});
test('overnight windows include exact boundaries and early mornings, but never the closed gap',()=>{
  const h=window(1320,360),z='Asia/Ho_Chi_Minh';
  for(const [a,b] of [['2030-12-31T15:00Z','2030-12-31T23:00Z'],['2030-12-31T18:00Z','2030-12-31T23:00Z'],['2030-12-31T15:00Z','2030-12-31T17:00Z']])assert.ok(fits(a,b,h,z));
  for(const [a,b] of [['2030-12-31T14:59:59Z','2030-12-31T23:00Z'],['2030-12-31T15:00Z','2030-12-31T23:00:00.001Z'],['2030-12-31T22:00Z','2031-01-01T16:00Z'],['2030-12-31T23:00Z','2031-01-01T00:00Z']])assert.ok(!fits(a,b,h,z));
  assert.ok(fits('2030-12-31T15:00Z','2030-12-31T17:00Z',window(1320,0),z));
  for(const h of [window(360,360),window(1440,360),window(1320,-1)])assert.ok(!fits('2030-12-31T15:00Z','2030-12-31T16:00Z',h,z));
});
test('overnight DST windows follow local closing time through spring and fall transitions',()=>{
  const z='America/New_York',h=window(1320,360);
  assert.ok(fits('2030-03-10T03:00Z','2030-03-10T10:00Z',h,z));
  assert.ok(fits('2030-11-03T02:00Z','2030-11-03T11:00Z',h,z));
  assert.ok(!fits('2030-11-03T02:00Z','2030-11-03T11:00:00.001Z',h,z));
  // Endpoints are inside, but the first occurrence of 01:30 closes this window.
  assert.ok(!fits('2030-11-03T02:00Z','2030-11-03T06:15Z',window(1320,90),z));
});
test('property-local boundaries, 24:00, multi-day rejection and invalid zones',()=>{
  assert.ok(validZone('Asia/Ho_Chi_Minh'));assert.ok(validZone('America/New_York'));assert.ok(!validZone('Invalid/Zone'));assert.ok(!validZone('+07:00'));
  const hours=window(540,1020),zone='Asia/Ho_Chi_Minh';
  assert.ok(fits('2030-01-01T02:00Z','2030-01-01T10:00Z',hours,zone));
  assert.ok(!fits('2030-01-01T01:59:59Z','2030-01-01T10:00Z',hours,zone));
  assert.ok(!fits('2030-01-01T02:00Z','2030-01-01T10:00:00.001Z',hours,zone));
  assert.ok(!fits('2030-01-01T02:00Z','2030-01-02T03:00Z',hours,zone));
  assert.ok(fits('2030-01-01T16:00Z','2030-01-01T17:00Z',window(0,1440),zone));
  assert.ok(!fits('2030-01-01T02:00Z','2030-01-01T03:00Z',hours,null));
  assert.ok(withinHours(0,1000000000,window(null,null),null));
});
test('DST spring-forward and repeated fall-back hour are evaluated across the whole interval',()=>{
  const zone='America/New_York';
  assert.ok(fits('2030-03-10T06:30Z','2030-03-10T07:30Z',window(60,240),zone));
  // Both endpoints read 01:45 but the clock passes through 01:00 between them.
  assert.ok(!fits('2030-11-03T05:45Z','2030-11-03T06:45Z',window(90,180),zone));
  assert.ok(fits('2030-11-03T05:45Z','2030-11-03T06:45Z',window(60,180),zone));
});
