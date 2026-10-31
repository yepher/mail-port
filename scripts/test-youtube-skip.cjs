const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../Sources/MailPortEmbedded/Resources/YouTubeSkipAds.js'), 'utf8');
function page({ host = 'www.youtube.com', frame = true, ad = true, visible = true, disabled = false } = {}) {
  let tick, clicks = 0;
  const window = {}; window.top = frame ? window : {};
  const button = { disabled, getClientRects: () => visible ? [1] : [], click: () => clicks++ };
  const player = { querySelector: () => button };
  const context = vm.createContext({ window, location: { protocol: 'https:', hostname: host },
    document: { querySelector: () => ad ? player : null }, setInterval: fn => { tick = fn; return 1; }, clearInterval: () => {} });
  vm.runInContext(source, context);
  return { context, tick: () => tick?.(), clicks: () => clicks };
}
test('off by default; enabling clicks an available skip button, disabling stops it', () => {
  const p = page(); p.tick(); assert.equal(p.clicks(), 0);
  p.context.__mailportSkipEnabled = true; p.tick(); assert.equal(p.clicks(), 1);
  p.context.__mailportSkipEnabled = false; p.tick(); assert.equal(p.clicks(), 1);
});
test('no interaction outside top-level YouTube or without an available skip button', () => {
  for (const options of [{ host: 'evil.test' }, { frame: false }, { ad: false }, { visible: false }, { disabled: true }]) {
    const p = page(options); p.context.__mailportSkipEnabled = true; p.tick(); assert.equal(p.clicks(), 0);
  }
});
