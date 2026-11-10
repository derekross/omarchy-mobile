#!/usr/bin/env node
// SPDX-License-Identifier: MIT
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const plugin = path.join(__dirname, '../plugins/omamobile.launcher');
const link = fs.readFileSync(path.join(plugin, 'AppsSearchLink.js'), 'utf8').replace(/^\.pragma library\s*$/m, '');
const ctx = vm.createContext({}); vm.runInContext(link, ctx);
assert.equal(ctx.close(), false);
let closed = 0;
const old = {searchOpened: true, closeSearch() { closed++; this.searchOpened = false; }};
const current = {searchOpened: true, closeSearch() { closed++; this.searchOpened = false; }};
ctx.publish(old); ctx.publish(current); ctx.clear(old);
assert.equal(ctx.close(), true); assert.equal(closed, 1); assert.equal(current.searchOpened, false);
assert.equal(ctx.close(), false);
ctx.clear(current); assert.equal(ctx.close(), false);
const back = fs.readFileSync(path.join(plugin, '../omamobile.back/Back.qml'), 'utf8');
const action = back.match(/function back\(\) \{([\s\S]*?)\n  \}/)[1];
let fallback = 0;
const receiver = vm.createContext({AppsSearchLink: ctx, Quickshell: {execDetached() { fallback++; }}, BackModel: {ESCAPE_ARGV: ['escape-fixture']}});
vm.runInContext('function back() {' + action + '}', receiver);
ctx.publish({searchOpened: true, closeSearch() { this.searchOpened = false; }});
assert.equal(receiver.back(), 'search'); assert.equal(fallback, 0);
assert.equal(receiver.back(), 'ok'); assert.equal(fallback, 1);
let stepped = 0;
const conversation = {searchOpened: true, backSearch() { stepped++; }, closeSearch() { this.searchOpened = false; }};
ctx.publish(conversation);
assert.equal(receiver.back(), 'search'); assert.equal(stepped, 1); assert.equal(conversation.searchOpened, true);
assert.equal(ctx.close(), true); assert.equal(conversation.searchOpened, false);
console.log('ok - native Back steps out of chat; Home closes the entire Search; stale registrations stay isolated');

const launcher = fs.readFileSync(path.join(plugin, 'Launcher.qml'), 'utf8');
function body(name) {
  const match = launcher.match(new RegExp('function ' + name + '\\([^)]*\\) \\{([\\s\\S]*?)\\n  \\}'));
  assert.ok(match, 'actual ' + name + ' function');
  return match[1];
}
let actions = [];
const native = vm.createContext({settings: {}, openSearch(text) { actions.push('search:' + text); }, expand() { actions.push('library'); }});
vm.runInContext('function activateDock() {' + body('activateDock') + '}', native);
native.activateDock(); assert.deepEqual(actions, ['search:']);
native.settings.nativeSearch = false; native.activateDock(); assert.deepEqual(actions, ['search:', 'library']);
native.settings.nativeSearch = true; native.activateDock(); assert.deepEqual(actions, ['search:', 'library', 'search:']);
actions = [];
const home = vm.createContext({searchOpened: true, closeSearch() { actions.push('close'); }, Quickshell: {execDetached() { actions.push('home'); }}});
vm.runInContext('function goHome() {' + body('goHome') + '}', home);
home.goHome(); assert.equal(actions[0], 'close'); assert.equal(actions.filter(x => x === 'home').length, 2);
console.log('ok - dock preference retains App Library; Home closes native Search before screen changes');

let summoned = 0;
const lockOpen = vm.createContext({sessionLocked: true, pluginId: 'fixture', shell: {summon() { summoned++; }}});
vm.runInContext('function openSearch(text) {' + body('openSearch') + '}', lockOpen);
lockOpen.openSearch('blocked'); assert.equal(summoned, 0);
lockOpen.sessionLocked = false; lockOpen.openSearch('fresh'); assert.equal(summoned, 1);
assert.match(launcher, /sessionLocked: root.sessionLocked/);
assert.match(body('open'), /if \(sessionLocked\) \{ appsSearch.close\(\); return \}/);
console.log('ok - known lock blocks launcher requests and is bound into native Search');
