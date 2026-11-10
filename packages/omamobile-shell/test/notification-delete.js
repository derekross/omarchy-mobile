// SPDX-License-Identifier: MIT
const fs = require('fs'), path = require('path'), vm = require('vm'), assert = require('assert'),
      os = require('os'), cp = require('child_process');
const root = __dirname,
      source = fs.readFileSync(path.join(root, '../plugins/omamobile.quicksettings/QuickSettings.qml'), 'utf8'),
      M = require(process.argv[2] ? path.resolve(process.argv[2])
                                  : '../plugins/omamobile.quicksettings/NotificationsModel.js');
function block(s, start) {
  const begin = s.indexOf('{', start);
  let depth = 1, end = begin + 1;
  while (depth) {
    depth += (s[end] === '{') - (s[end] === '}');
    end++
  }
  return s.slice(begin, end)
}
function fn(name) {
  const start = source.indexOf('  function ' + name + '(');
  assert(start >= 0);
  return source.slice(start, source.indexOf('{', start)) + block(source, start)
}
function handler(id) {
  let start = source.indexOf('id: ' + id + '\n');
  start = source.indexOf('onExited: function(code)', start);
  return '(function(code) ' + block(source, start) + ')'
}
let n = 0;
function test(name, cb) {
  cb();
  n++;
  console.log('PASS', name)
}
function context() {
  let later = [];
  const c = {
    NotificationsModel : M,
    Date,
    JSON,
    Object,
    Quickshell : {shellDir : 'fixture-shell'},
    notifications : [ {key : 'old', file : 'old'}, {key : 'new', file : 'new'} ],
    hiddenNotifications : {},
    forgetQueue : [],
    pendingForget : null,
    pendingClearKeys : [],
    notificationDeleteError : '',
    failedKeys : [],
    notificationForgetFailed(key) { this.failedKeys.push(key) },
    forgetProc : {running : false},
    clearProc : {running : false},
    forgetResult : {text : ''},
    clearResult : {text : ''},
    notificationsDir : 'fixture',
    notificationsLater : {restart() {}},
    Qt : {callLater : fn => later.push(fn)}
  };
  c.root = c;
  vm.createContext(c);
  vm.runInContext(
      [ 'acknowledgeNotifications', 'forgetNotification', 'runForget', 'clearAllNotifications' ]
          .map(fn)
          .join('\n'),
      c);
  c.forgetDone = vm.runInContext(handler('forgetProc'), c);
  c.clearDone = vm.runInContext(handler('clearProc'), c);
  c.settle = () => {
    while (later.length)
      later.shift()()
  };
  return c
}
test('single delete does not hide until exact successful ACK', () => {
  const c = context();
  assert(c.forgetNotification(c.notifications[0]));
  assert.equal(c.notifications.length, 2);
  assert.deepEqual(Object.keys(c.hiddenNotifications), []);
  assert.deepEqual(
      [...c.forgetProc.command ],
      [ 'qs', 'ipc', '-p', 'fixture-shell', 'call', 'notifications', 'forget', 'old' ]);
  c.forgetProc.running = false;
  c.forgetResult.text = 'busy';
  c.forgetDone(0);
  c.settle();
  assert.equal(c.notifications.length, 2);
  assert(c.notificationDeleteError);
});
test('single successful ACK suppresses only captured key', () => {
  const c = context();
  c.forgetNotification(c.notifications[0]);
  c.forgetProc.running = false;
  c.forgetResult.text = 'ok\n';
  c.forgetDone(0);
  c.settle();
  assert.deepEqual(c.notifications.map(x => x.key), [ 'new' ]);
  assert.deepEqual(Object.keys(c.hiddenNotifications), [ 'old' ]);
});
test('failed malformed old-version busy replies never clear visible rows', () => {
  for (const text
           of ['', 'ok', '{"result":"ok","keys":["old"]}',
               '{"version":true,"result":"ok","keys":["old"]}',
               '{"version":1,"result":"busy","keys":[]}',
               '{"version":1,"result":"ok","keys":["../bad"]}',
               JSON.stringify({version : 1, result : 'ok', keys : Array(301).fill('old')})]) {
    const c = context();
    c.clearResult.text = text;
    c.clearDone(0);
    c.settle();
    assert.equal(c.notifications.length, 2);
    assert.equal(Object.keys(c.hiddenNotifications).length, 0);
    assert(c.notificationDeleteError)
  }
});
test('nonzero IPC exit cannot acknowledge valid-looking data', () => {
  const c = context();
  c.clearResult.text = '{"version":1,"result":"ok","keys":["old"]}';
  c.clearDone(1);
  c.settle();
  assert.equal(c.notifications.length, 2);
  assert.equal(Object.keys(c.hiddenNotifications).length, 0);
  assert(c.notificationDeleteError);
});
test('bulk acknowledgment retains arrivals and in-flight stale reads', () => {
  const c = context();
  c.clearResult.text = '{"version":1,"result":"ok","keys":["old"]}';
  c.clearDone(0);
  c.settle();
  assert.deepEqual(c.notifications.map(x => x.key), [ 'new' ]);
  const raw = JSON.stringify(
      [ {key : 'old', ts : 1, summary : 'Old'}, {key : 'new', ts : 2, summary : 'New'} ]);
  assert.deepEqual(M.shown(raw, c.hiddenNotifications, Date.now()).entries.map(x => x.key),
                   [ 'new' ]);
  assert.deepEqual(M.shown(JSON.stringify([ {key : 'new', ts : 2, summary : 'New'} ]),
                           c.hiddenNotifications, Date.now())
                       .hidden,
                   {})
});
test('arrival between ACK and deferred delegate removal survives', () => {
  const c = context();
  c.clearResult.text = '{"version":1,"result":"ok","keys":["old"]}';
  c.clearDone(0);
  c.notifications.push({key: 'later', file: 'later'});
  c.settle();
  assert.deepEqual(c.notifications.map(entry => entry.key), ['new', 'later']);
});
test('dictionary-like keys deduplicate and retain safe own tombstones', () => {
  const result = M.clearResult(
      JSON.stringify(
          {version : 1, result : 'ok', keys : [ '__proto__', 'hasOwnProperty', '__proto__' ]}),
      0);
  assert.deepEqual(result.keys, [ '__proto__', 'hasOwnProperty' ]);
  const state = M.acknowledge([ {key : '__proto__'}, {key : 'new'} ], {}, result.keys, 10);
  assert.equal(Object.getPrototypeOf(state.hidden), null);
  assert.deepEqual(state.entries, [ {key : 'new'} ]);
  const raw = JSON.stringify([
    {key : '__proto__', ts : 1, summary : 'Proto'},
    {key : 'hasOwnProperty', ts : 2, summary : 'Own'}, {key : 'new', ts : 3, summary : 'New'}
  ]);
  assert.deepEqual(M.shown(raw, state.hidden, 11).entries.map(x => x.key), [ 'new' ])
});
test('legacy success hides only the rows captured before the call', () => {
  const c = context();
  c.clearAllNotifications();
  assert.deepEqual([...c.pendingClearKeys], ['old', 'new']);
  c.notifications.push({key: 'arrival', file: 'arrival'});
  assert.equal(c.notifications.length, 3, 'no optimistic removal before the reply');
  c.clearResult.text = '{"version":1,"result":"legacy"}';
  c.clearDone(0);
  c.settle();
  assert.deepEqual(c.notifications.map(entry => entry.key), ['arrival']);
  assert.deepEqual(Object.keys(c.hiddenNotifications), ['old', 'new']);
  assert.deepEqual([...c.pendingClearKeys], []);
  assert.equal(c.notificationDeleteError, '');
});
test('failed legacy clear retains the snapshot and new arrivals', () => {
  const c = context();
  c.clearAllNotifications();
  c.notifications.push({key: 'arrival', file: 'arrival'});
  c.clearResult.text = '{"version":1,"result":"legacy"}';
  c.clearDone(1);
  c.settle();
  assert.equal(c.notifications.length, 3);
  assert.deepEqual(Object.keys(c.hiddenNotifications), []);
  assert.deepEqual([...c.pendingClearKeys], []);
  assert(c.notificationDeleteError);
});
test('single delete refused during clear leaves rows and reports busy', () => {
  const c = context();
  c.clearProc.running = true;
  assert.equal(c.forgetNotification(c.notifications[0]), false);
  assert.equal(c.notifications.length, 2);
  assert.equal(c.forgetQueue.length, 0);
  assert(c.notificationDeleteError);
});
test('actual bulk command uses one keyed IPC and preserves legacy flow', () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'notification-ipc-'));
  try {
    const bin = path.join(d, 'bin');
    fs.mkdirSync(bin);
    fs.symlinkSync('/bin/sh', path.join(bin, 'sh'));
    const log = path.join(d, 'log');
    fs.writeFileSync(
        path.join(bin, 'qs'),
        '#!/bin/sh\nprintf "%s\\n" "$*" >> "$NOTIFY_LOG"\ncase "$*" in\n*forgetAll) [ "$NOTIFY_CAP" != old ] || exit 23; printf "%s" "$NOTIFY_ACK";;\n*dismissAll|*clear) printf "ok\\n";;\n*) exit 24;;\nesac\n',
        {mode : 0o755});
    const c = context();
    c.notificationsDir = d;
    c.clearAllNotifications();
    assert.equal(c.notifications.length, 2);
    let env = {
      ...process.env,
      PATH : bin,
      NOTIFY_LOG : log,
      NOTIFY_ACK : '{"version":1,"result":"ok","keys":["old"]}'
    };
    fs.writeFileSync(path.join(d, 'live.json'), '[]');
    let r = cp.spawnSync(c.clearProc.command[0], c.clearProc.command.slice(1),
                         {env, encoding : 'utf8'});
    assert.equal(r.status, 0);
    assert(M.clearResult(r.stdout, r.status).ok);
    assert.equal(fs.readFileSync(log, 'utf8').trim().split('\n').length, 1);
    assert(fs.readFileSync(log, 'utf8').includes('forgetAll'));
    r = cp.spawnSync(c.clearProc.command[0], c.clearProc.command.slice(1),
                     {env : {...env, NOTIFY_CAP : 'old'}, encoding : 'utf8'});
    assert.equal(r.status, 23);
    assert(!M.clearResult(r.stdout, r.status).ok);
    fs.unlinkSync(path.join(d, 'live.json'));
    fs.writeFileSync(log, '');
    r = cp.spawnSync(c.clearProc.command[0], c.clearProc.command.slice(1),
                     {env, encoding : 'utf8'});
    assert.equal(r.status, 0);
    assert(M.clearResult(r.stdout, 0).legacy);
    assert.equal(fs.readFileSync(log, 'utf8').trim().split('\n').length, 2);
  } finally {
    fs.rmSync(d, {recursive : true, force : true})
  }
});
test('async refusal identifies only the rejected key and continues the queue', () => {
  const c = context();
  assert(c.forgetNotification(c.notifications[0]));
  c.forgetProc.running = true;
  assert(c.forgetNotification(c.notifications[1]));
  c.forgetProc.running = false;
  c.forgetResult.text = 'busy';
  c.forgetDone(1);
  assert.deepEqual(c.failedKeys, ['old']);
  assert.equal(c.pendingForget.key, 'new');
  assert.equal(c.notifications.length, 2);
  c.forgetProc.running = false;
  c.forgetResult.text = 'ok';
  c.forgetDone(0);
  c.settle();
  assert.deepEqual(c.failedKeys, ['old']);
  assert.deepEqual(c.notifications.map(entry => entry.key), ['old']);
});
console.log('PASS total', n, 'actual source consumer cases; no real daemon/notification operation');
