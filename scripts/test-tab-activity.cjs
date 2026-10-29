const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname,'../Sources/MailPortEmbedded/Resources/TabActivity.js'),'utf8');
const {unreadNumber,inboxTitle,eventWindow} = require('../Sources/MailPortEmbedded/Resources/TabActivity.js');

test('Gmail counts use Inbox only and support thousands and zero',()=>{
  assert.equal(inboxTitle('Inbox (1,234) - user@example.com - Gmail'),1234);
  assert.equal(inboxTitle('Inbox (0) - Gmail'),0);
  assert.equal(inboxTitle('Inbox - user@example.com - Workspace Mail'),0);
  assert.equal(inboxTitle('Search (45) - Gmail'),null);
  assert.equal(inboxTitle('A subject with (45) - Gmail'),null);
  assert.equal(unreadNumber('1\u00a0234'),1234);
  assert.equal(unreadNumber('12 emails'),null);
});
test('Calendar labels produce exact boundaries in the displayed time zone',()=>{
  const result=eventWindow('12pm to 1pm, Example, Chris, No location, October 28, 2026',-300);
  assert.equal(result.start,Date.parse('2026-10-28T12:00:00-05:00'));
  assert.equal(result.end,Date.parse('2026-10-28T13:00:00-05:00'));
  const overnight=eventWindow('11pm to 1am, Example, October 31, 2026',-300);
  assert.equal(overnight.end-overnight.start,2*3600000);
  assert.equal(eventWindow('11 to 1pm, Example, October 28, 2026',-300).start,Date.parse('2026-10-28T11:00:00-05:00'));
  assert.equal(eventWindow('20:00 to 21:00, Example, October 28, 2026',-300).start,Date.parse('2026-10-28T20:00:00-05:00'));
  assert.equal(eventWindow('8pm to 9pm, Follow-up on October 1, 2026, October 28, 2026',-300).start,Date.parse('2026-10-28T20:00:00-05:00'));
});
test('all-day, declined, ambiguous, zero-duration and invalid labels are excluded',()=>{
  for(const label of ['All day, Example, October 28, 2026','1pm to 2pm, Example, Declined, October 28, 2026','Example at 1pm to 2pm, October 28, 2026','1 to 2, Example, October 28, 2026','1pm to 1pm, Example, October 28, 2026','1pm to 2pm, Example, February 31, 2026']) assert.equal(eventWindow(label),null,label);
});
function observe(host, title, labels=[], count=null) {
  const sent=[]; let refresh;
  const row={querySelector:()=>count===null?null:{textContent:String(count)},getAttribute:()=>null,innerText:'Inbox'};
  const link={closest:()=>row,getAttribute:()=>null,textContent:'Inbox'};
  const nodes=labels.map(label=>({getAttribute:name=>name==='aria-label'?label:null,innerText:label}));
  const document={title,body:{innerText:'GMT-05\n'},documentElement:{},addEventListener(){},getElementById(){},querySelector:()=>host==='mail.google.com'?link:null,querySelectorAll:()=>nodes};
  const window={webkit:{messageHandlers:{mailPortActivity:{postMessage:value=>sent.push(value)}}}}; window.top=window;
  vm.runInNewContext(source,{window,document,location:{protocol:'https:',hostname:host},MutationObserver:class{observe(){}},setTimeout(){},clearTimeout(){},setInterval(fn){refresh=fn;}});
  return {sent,refresh,document,row};
}
test('page observer reports count changes without message contents',()=>{
  const page=observe('mail.google.com','Subject - Gmail',[],5);
  assert.equal(page.sent[0].count,5);
  page.row.querySelector=()=>({textContent:'0'}); page.refresh();
  assert.equal(page.sent.at(-1).count,0);
  assert.deepEqual(Object.keys(page.sent[0]).sort(),['count','kind']);
});
test('Calendar observer deduplicates labels and sends times without titles',()=>{
  const label='8pm to 9pm, Private title, October 28, 2026';
  const page=observe('calendar.google.com','Google Calendar',[label,label,'All day, PTO, October 28, 2026']);
  assert.equal(page.sent[0].events.length,1);
  assert.ok(!JSON.stringify(page.sent).includes('Private title'));
});
test('authentication and other Google services do not send activity',()=>{
  for(const host of ['accounts.google.com','gemini.google.com','calendar.google.com.evil.test']) assert.equal(observe(host,'Calendar').sent.length,0);
});
