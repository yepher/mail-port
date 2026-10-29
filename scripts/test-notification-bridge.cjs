const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../Sources/MailPortEmbedded/Resources/NotificationBridge.js'), 'utf8');
function page(host = 'calendar.google.com', permission = 'default', mainFrame = true) {
  const sent = []; let serial = 0;
  const window = {navigator:{permissions:{query: async descriptor => ({state:'native-'+descriptor.name})}},webkit:{messageHandlers:{mailPortNotifications:{postMessage: value => sent.push(value)}}}};
  window.top = mainFrame ? window : {};
  const context = vm.createContext({window, location:{protocol:'https:',hostname:host}, crypto:{randomUUID:()=>`id-${++serial}`}, Event, EventTarget, DOMException});
  vm.runInContext(source.replace('__MAILPORT_PERMISSION__', permission), context);
  return {window, sent};
}
test('permission requests resolve from native replies and gate notifications', async () => {
  const {window, sent} = page();
  assert.throws(()=>new window.Notification('Meeting'), {name:'NotAllowedError'});
  let callback;
  const result = window.Notification.requestPermission(value=>callback=value);
  assert.equal(sent[0].kind,'permission');
  window.__mailportNotifications.permissionChanged('granted',sent[0].id);
  assert.equal(await result,'granted'); assert.equal(callback,'granted');
  assert.equal(window.Notification.permission,'granted');
});
test('show, click and close cross the bridge without executing supplied data', () => {
  const {window,sent}=page('calendar.google.com','granted');
  const item=new window.Notification('Meeting',{body:'Starts in 5 minutes',tag:'event1'});
  assert.equal(sent[0].kind,'show'); assert.equal(sent[0].tag,'event1');
  let clicked=0; item.onclick=()=>clicked++;
  window.__mailportNotifications.clicked(sent[0].id); assert.equal(clicked,1);
  const another=new window.Notification('Other'); let closed=0;
  another.onclose=()=>closed++; another.close(); another.close();
  assert.equal(closed,1); assert.equal(sent.filter(x=>x.kind==='close').length,1);
});
test('Google authentication, other hosts and subframes receive no notification shim', () => {
  for (const host of ['accounts.google.com','evil.test','calendar.google.com.evil.test','gemini.google.com']) {
    assert.equal(page(host).window.Notification,undefined);
  }
  assert.equal(page('calendar.google.com','granted',false).window.Notification,undefined);
  assert.ok(page('mail.google.com').window.Notification);
});

test('notification Permissions API matches native permission without changing other permissions', async () => {
  const {window}=page();
  const status=await window.navigator.permissions.query({name:'notifications'});
  assert.equal(status.state,'prompt');
  let changes=0; status.addEventListener('change',()=>changes++);
  window.__mailportNotifications.permissionChanged('granted');
  assert.equal(status.state,'granted'); assert.equal(changes,1);
  window.__mailportNotifications.permissionChanged('granted');
  assert.equal(changes,1);
  assert.equal((await window.navigator.permissions.query({name:'geolocation'})).state,'native-geolocation');
});
