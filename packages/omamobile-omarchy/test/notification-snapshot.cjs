// SPDX-License-Identifier: MIT
const fs = require('fs'), vm = require('vm'), path = require('path'), assert = require('assert'),
      os = require('os');
const root = path.resolve(process.argv[3]);
const source = fs.readFileSync(process.argv[2], 'utf8');
function fn(s, n) {
  const a = s.indexOf('  function ' + n + '(');
  assert(a >= 0, n);
  let i = s.indexOf('{', a) + 1, depth = 1;
  while (depth) {
    if (s[i] === '{')
      depth++;
    if (s[i] === '}')
      depth--;
    i++
  }
  return s.slice(a, i)
}
function lib(name) {
  let s = fs.readFileSync(path.join(root, name + '.js'), 'utf8');
  let c = {console};
  s = s.replace(/^\.import "([^"]+)" as (\w+)\s*$/gm, (_, f, a) => {
         c[a] = lib(f.replace('.js', ''));
         return ''
       }).replace(/^\.pragma.*$/gm, '');
  vm.createContext(c);
  vm.runInContext(s, c);
  return c
}
const Store = lib('Store');
let tests = 0;
function test(name, f) {
  f();
  tests++;
  console.log('PASS', name)
}
function service(ready = true) {
  let files = {live : '', history : ''}, later = [], dismissed = 0;
  let c = {
    Object,
    JSON,
    Date,
    Math,
    Store,
    liveLoaded : ready,
    historyLoaded : ready,
    liveKeys : Object.create(null),
    refs : Object.create(null),
    refsRevision : 0,
    liveEntries : [],
    historyEntries : [],
    held : [],
    leaving : {},
    departures : {},
    bannerHidden : {},
    replyKey : '',
    heights : {},
    fresh : {},
    layoutRevision : 0,
    unsaved : {},
    quietLoaded : true,
    doNotDisturb : true,
    jumping : false,
    saveTimer : {running : false, start() { this.running = true }},
    land() {},
    Qt : {callLater : f => later.push(f)}
  };
  c.service = c;
  c.rows = [];
  c.toasts = {get : i => c.rows[i], remove : i => c.rows.splice(i, 1)};
  Object.defineProperty(c.toasts, 'count', {get : () => c.rows.length});
  c.rowIndexFor = k => c.rows.findIndex(x => x.key === k);
  c.setBannerHidden = (k, v) => {
    if (v)
      c.bannerHidden[k] = true;
    else
      delete c.bannerHidden[k]
  };
  c.liveFile = {setText : t => files.live = t};
  c.historyFile = {setText : t => files.history = t};
  c.quietFile = {setText : () => { throw Error('DND must not be written') }};
  vm.createContext(c);
  vm.runInContext(
      [
        'releaseLive', 'release', 'closeToast', 'closeToasts', 'unmarkLeaving', 'finishClose',
        'finishLeaving', 'forgetNotification', 'forgetAllNotifications', 'storeDrop', 'storeClose',
        'storeRecord', 'saveSoon', 'flushStore'
      ].map(n => fn(source, n))
          .join('\n'),
      c);
  c.add = (k, kind = 'visible') => {
    const row = {
      key : k,
      ts : Date.now() / 1000,
      app : 'Fixture',
      summary : 'Owned notification',
      body : 'body',
      urgency : 1
    };
    if (kind === 'history') {
      c.historyEntries.push({...row, closed_ts : Date.now() / 1000});
      return
    }
    c.liveKeys[k] = {row : null};
    c.liveEntries.push(row);
    if (kind !== 'pending') {
      c.rows.push(row);
      if (kind === 'hidden')
        c.bannerHidden[k] = true
    }
    c.refs[k] = {
      dismiss() { dismissed++ },
      expire() { throw Error('must not expire') },
      invokeAction() { throw Error('must not invoke sender action') }
    }
  };
  c.settle = () => {
    while (later.length)
      later.shift()();
    c.flushStore()
  };
  return {c, files, dismissed : () => dismissed};
}
test('clear snapshot removes visible, hidden, pending and history without rearchive', () => {
  const s = service();
  s.c.add('visible');
  s.c.add('hidden', 'hidden');
  s.c.add('pending', 'pending');
  s.c.add('old', 'history');
  const r = JSON.parse(s.c.forgetAllNotifications());
  assert.equal(r.result, 'ok');
  assert.equal(r.version, 1);
  assert.deepEqual([...r.keys ].sort(), [ 'hidden', 'old', 'pending', 'visible' ]);
  s.c.settle();
  assert.equal(s.c.rows.length, 0);
  assert.equal(s.c.liveEntries.length, 0);
  assert.equal(s.c.historyEntries.length, 0);
  assert.deepEqual(JSON.parse(s.files.live), []);
  assert.deepEqual(JSON.parse(s.files.history), []);
  assert.equal(s.dismissed(), 3);
  assert.equal(s.c.doNotDisturb, true)
});
test('history-only deletion is persisted and cannot return on reload', () => {
  const s = service();
  s.c.add('one', 'history');
  s.c.add('two', 'history');
  assert.equal(s.c.forgetNotification('one'), 'ok');
  s.c.settle();
  assert.deepEqual(Store.parseHistory(s.files.history).map(x => x.key), [ 'two' ]);
  assert.equal(s.dismissed(), 0)
});
test('one hidden live row is dropped from both store and sender reference', () => {
  const s = service();
  s.c.add('one', 'hidden');
  assert.equal(s.c.forgetNotification('one'), 'ok');
  s.c.settle();
  assert.equal(s.c.liveEntries.length, 0);
  assert(!s.c.refs.one);
  assert.equal(s.c.historyEntries.length, 0)
});
test('unloaded stores refuse before mutation instead of resurrecting later load', () => {
  const s = service(false);
  s.c.add('one', 'history');
  assert.equal(s.c.forgetNotification('one'), 'busy');
  assert.equal(JSON.parse(s.c.forgetAllNotifications()).result, 'busy');
  assert.equal(s.c.historyEntries.length, 1);
  assert.equal(Object.keys(s.c.unsaved).length, 0)
});
test('either partially loaded store refuses before mutation', () => {
  for (const partial of ['liveLoaded', 'historyLoaded']) {
    const s = service(false);
    s.c[partial] = true;
    s.c.add('old', 'history');
    assert.equal(s.c.forgetNotification('old'), 'busy');
    const reply = JSON.parse(s.c.forgetAllNotifications());
    assert.equal(reply.version, 1);
    assert.equal(reply.result, 'busy');
    assert.equal(s.c.historyEntries.length, 1);
    assert.equal(Object.keys(s.c.unsaved).length, 0);
  }
});
test('new arrival after clear is retained and not included in acknowledgment', () => {
  const s = service();
  s.c.add('old');
  let r = JSON.parse(s.c.forgetAllNotifications());
  s.c.add('new');
  s.c.settle();
  assert.deepEqual(r.keys, [ 'old' ]);
  assert.deepEqual(s.c.liveEntries.map(x => x.key), [ 'new' ]);
  assert.equal(s.c.historyEntries.length, 0)
});
test('repeated clear is idempotent after deferred closures settle', () => {
  const s = service();
  s.c.add('old');
  s.c.forgetAllNotifications();
  s.c.settle();
  assert.deepEqual(JSON.parse(s.c.forgetAllNotifications()).keys, []);
  s.c.settle();
  assert.equal(s.dismissed(), 1)
});
test('invalid keyed delete performs no arbitrary file operation', () => {
  const s = service();
  s.c.add('old');
  for (const key of ['../quiet.json', '/etc/passwd', 'a/b', ''])
    assert.equal(s.c.forgetNotification(key), 'none');
  assert.equal(s.c.liveEntries.length, 1);
  assert.equal(Object.keys(s.c.unsaved).length, 0)
});
test('already absent key stays idempotent after stores load', () => {
  const s = service();
  assert.equal(s.c.forgetNotification('gone'), 'ok');
  s.c.settle();
  assert.equal(s.dismissed(), 0)
});
console.log('PASS total', tests, 'genuine-source provider cases');
