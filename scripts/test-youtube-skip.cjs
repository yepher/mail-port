const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../Sources/MailPortEmbedded/Resources/YouTubeSkipAds.js'), 'utf8');
function page({ host = 'www.youtube.com', protocol = 'https:', frame = true, ad = true, visible = true, disabled = false, hidden = false, ariaDisabled = false, hiddenFirst = false, enabled = false } = {}) {
  let tick, clicks = 0, clears = 0;
  const window = {}; window.top = frame ? window : {};
  const button = { disabled, getAttribute: () => ariaDisabled ? 'true' : null, closest: () => hidden ? {} : null,
    getClientRects: () => visible ? [1] : [], getBoundingClientRect: () => ({left: 10, top: 10, width: 100, height: 40}), contains: node => node === button, click: () => { throw new Error('Synthetic clicks must not be used'); } };
  const stale = { ...button, getClientRects: () => [] };
  const player = { querySelectorAll: () => ad ? (hiddenFirst ? [stale, button] : [button]) : [] };
  const context = vm.createContext({ window, location: { protocol, hostname: host },
    innerWidth: 800, innerHeight: 600, document: { querySelector: () => player, elementFromPoint: () => button }, getComputedStyle: () => ({visibility: 'visible', display: 'block'}),
    setInterval: fn => { tick = fn; return 1; }, clearInterval: () => clears++ });
  const install = (on) => { const result = vm.runInContext(source.replace('/*__MAILPORT_SKIP_ENABLED__*/false', String(on)), context); if (result) clicks++; return result; };
  install(enabled);
  return { context, install, tick: () => { const result = context.__mailportSkipNow?.(); if (result) clicks++; return result; }, clicks: () => clicks, clears: () => clears };
}
test('off by default; native opt-in applies immediately without a page-load callback', () => {
  const p = page(); p.tick(); assert.equal(p.clicks(), 0);
  p.install(true); assert.equal(p.clicks(), 1);
  p.tick(); assert.equal(p.clicks(), 2);
  p.install(false); p.tick(); assert.equal(p.clicks(), 2);
  assert.equal(p.clears(), 0);
});
test('new documents inherit the enabled setting and hidden stale controls do not block live ones', () => {
  const p = page({enabled: true, hiddenFirst: true}); assert.equal(p.clicks(), 1);
});
test('no interaction outside top-level HTTPS YouTube or without an available skip button', () => {
  for (const options of [{ host: 'evil.test' }, { protocol: 'http:' }, { frame: false }, { ad: false }, { visible: false }, { disabled: true }, { hidden: true }, { ariaDisabled: true }]) {
    const p = page({...options, enabled: true}); p.tick(); assert.equal(p.clicks(), 0);
  }
});
test('CSS visibility hides controls even when they have layout rectangles', () => {
  const p = page(); p.context.getComputedStyle = () => ({visibility: 'hidden', display: 'block'});
  p.install(true); p.tick(); assert.equal(p.clicks(), 0);
});

test('returns viewport geometry for native input, never a synthetic click', () => {
  const p = page();
  assert.deepEqual(JSON.parse(JSON.stringify(p.install(true))), {x: 60, y: 30, width: 800, height: 600});
});
