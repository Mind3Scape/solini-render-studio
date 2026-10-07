// Behavioural contract of the unchanged pages/connect.js, executed in a node:vm sandbox.
// Run: node --test tests/pages_connect.test.mjs
// No real invitation, endpoint or visitor key is used; network and timers are fakes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../pages/connect.js', import.meta.url), 'utf8');
const INVITE = 'TEST-INVITE-NOT-A-SECRET';
const HEALTHY = 'https://calm-river-1234.trycloudflare.com/';

function response(body, ok = true) {
  return { ok, json: async () => body };
}

function element(id) {
  return { id, textContent: '', hidden: id === 'open', disabled: false, href: '', style: {}, onclick: null };
}

function load({ fetch, storage = 'ok', stored = null, hash = `#invite=${INVITE}` } = {}) {
  const elements = Object.fromEntries(['status', 'detail', 'dot', 'retry', 'open'].map(id => [id, element(id)]));
  elements.status.textContent = 'Подключение к студии…';
  const calls = [];
  const timers = [];
  const replaced = [];
  const memory = new Map(stored ? [['salini-visitor-key', stored]] : []);
  const sandbox = {
    document: { getElementById: id => elements[id] },
    location: { hash, replace: url => replaced.push(url) },
    URL, URLSearchParams, AbortSignal, btoa,
    crypto: { getRandomValues: bytes => bytes.map((_, i) => (i * 37 + 11) % 256) },
    fetch: (url, options) => { calls.push({ url: String(url), options }); return fetch(String(url), options); },
    setTimeout: (fn, ms) => { timers.push({ fn, ms }); return timers.length; },
    clearTimeout: () => {},
  };
  if (storage === 'ok') {
    sandbox.localStorage = { getItem: key => memory.get(key) ?? null, setItem: (key, value) => memory.set(key, value) };
  } else {
    // Safari private mode / blocked site data: touching storage throws.
    Object.defineProperty(sandbox, 'localStorage', { get() { throw new Error('SecurityError'); } });
  }
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { filename: 'pages/connect.js' });
  return { elements, calls, timers, replaced, memory };
}

const settle = async () => { for (let i = 0; i < 20; i++) await new Promise(resolve => setImmediate(resolve)); };

function assertOffline({ elements, replaced, timers }) {
  assert.equal(elements.status.textContent, 'Обработчик сейчас недоступен');
  assert.match(elements.detail.textContent, /через 30 секунд/);
  assert.equal(elements.open.hidden, true, 'no fake "open" link while offline');
  assert.equal(elements.retry.disabled, false);
  assert.equal(elements.dot.style.background, '#b89d69');
  assert.deepEqual(replaced, []);
  assert.equal(timers.at(-1).ms, 30000, 'automatic re-check is scheduled');
}

test('unavailable: no published endpoint stays offline and schedules a re-check', async () => {
  const run = load({ fetch: async url => (url.startsWith('./connection.json?v=') ? response({ url: null }) : assert.fail(url)) });
  await settle();
  assertOffline(run);
  assert.equal(run.calls.length, 1);
  assert.equal(run.calls[0].options.cache, 'no-store');
});

test('unavailable: network failure and unhealthy service are reported as offline', async () => {
  for (const health of [null, response({ app: 'salini-online', online: false }), response({}, false),
                        response({ app: 'something-else', online: true })]) {
    const run = load({
      fetch: async url => {
        if (url.startsWith('./connection.json')) return response({ url: HEALTHY });
        if (!health) throw new TypeError('network');
        return health;
      },
    });
    await settle();
    assertOffline(run);
  }
});

test('healthy: redirects once with invitation and visitor in the fragment only', async () => {
  const run = load({
    fetch: async (url, options) => {
      if (url.startsWith('./connection.json')) return response({ url: HEALTHY });
      assert.equal(url, `${HEALTHY}health`);
      assert.equal(options.credentials, 'omit');
      return response({ app: 'salini-online', online: true });
    },
  });
  await settle();
  assert.equal(run.replaced.length, 1);
  const target = new URL(run.replaced[0]);
  assert.equal(target.origin + target.pathname, HEALTHY);
  assert.equal(target.search, '', 'secrets never go into the query string');
  const fragment = new URLSearchParams(target.hash.slice(1));
  assert.equal(fragment.get('invite'), INVITE);
  assert.match(fragment.get('visitor'), /^[A-Za-z0-9_-]{43}$/);
  assert.equal(run.elements.status.textContent, 'Студия готова');
  assert.equal(run.elements.open.hidden, false);
  assert.equal(run.elements.open.href, run.replaced[0]);
  assert.equal(run.elements.dot.style.background, '#618a65');
  assert.equal(run.timers.length, 0);
});

test('invalid endpoints are refused before any health request', async () => {
  for (const url of ['http://calm-river-1234.trycloudflare.com/', 'https://example.com/',
                     'https://calm-river-1234.trycloudflare.com/studio', 'https://calm-river-1234.trycloudflare.com:8443/',
                     'https://user:pass@calm-river-1234.trycloudflare.com/', 'https://a.b.trycloudflare.com/',
                     'javascript:alert(1)']) {
    const run = load({ fetch: async u => (u.startsWith('./connection.json') ? response({ url }) : assert.fail(`health fetched for ${url}`)) });
    await settle();
    assertOffline(run);
    assert.equal(run.calls.length, 1, url);
  }
});

test('retry: re-checks on demand, ignores double taps while checking, then redirects', async () => {
  let online = false;
  let release;
  const run = load({
    fetch: async url => {
      if (url.startsWith('./connection.json')) {
        if (online) await new Promise(resolve => { release = resolve; });
        return response({ url: online ? HEALTHY : null });
      }
      return response({ app: 'salini-online', online: true });
    },
  });
  await settle();
  assertOffline(run);
  online = true;
  run.elements.retry.onclick();
  await settle();
  assert.equal(run.elements.retry.disabled, true, 'button is disabled while checking');
  assert.equal(run.elements.open.hidden, true);
  run.elements.retry.onclick();
  await settle();
  assert.equal(run.calls.filter(c => c.url.startsWith('./connection.json')).length, 2, 'second tap ignored');
  release();
  await settle();
  assert.equal(run.replaced.length, 1);
  assert.equal(run.elements.retry.disabled, false);
});

test('visitor key: blocked storage still connects with a generated key', async () => {
  const run = load({
    storage: 'blocked',
    fetch: async url => response(url.startsWith('./connection.json') ? { url: HEALTHY } : { app: 'salini-online', online: true }),
  });
  await settle();
  assert.equal(run.replaced.length, 1);
  assert.match(new URLSearchParams(new URL(run.replaced[0]).hash.slice(1)).get('visitor'), /^[A-Za-z0-9_-]{43}$/);
});

test('visitor key: an existing key is reused and a new one is persisted', async () => {
  const healthy = async url => response(url.startsWith('./connection.json') ? { url: HEALTHY } : { app: 'salini-online', online: true });
  const existing = load({ stored: 'existing-visitor-key', fetch: healthy });
  await settle();
  assert.equal(new URLSearchParams(new URL(existing.replaced[0]).hash.slice(1)).get('visitor'), 'existing-visitor-key');
  const fresh = load({ fetch: healthy });
  await settle();
  assert.match(fresh.memory.get('salini-visitor-key'), /^[A-Za-z0-9_-]{43}$/);
});

test('no invitation in the link: still connects, with an empty invite field', async () => {
  const run = load({ hash: '', fetch: async url => response(url.startsWith('./connection.json') ? { url: HEALTHY } : { app: 'salini-online', online: true }) });
  await settle();
  assert.equal(new URLSearchParams(new URL(run.replaced[0]).hash.slice(1)).get('invite'), '');
});
