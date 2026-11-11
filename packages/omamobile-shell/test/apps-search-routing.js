#!/usr/bin/env node
// SPDX-License-Identifier: MIT
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const plugin = path.join(__dirname, '../plugins/omamobile.launcher');
const launcher = fs.readFileSync(path.join(plugin, 'Launcher.qml'), 'utf8');
function body(name) {
  const match = launcher.match(new RegExp('function ' + name + '\\([^)]*\\) \\{([\\s\\S]*?)\\n  \\}'));
  assert.ok(match, 'actual ' + name + ' function');
  return match[1];
}
let actions = [];
const native = vm.createContext({settings: {}, openSearch(text) { actions.push('search:' + text); }, expand() { actions.push('library'); }});
vm.runInContext('function activateDock() {' + body('activateDock') + '}', native);
native.activateDock(); assert.deepEqual(actions, ['library']);
native.settings.nativeSearch = false; native.activateDock(); assert.deepEqual(actions, ['library', 'library']);
native.settings.nativeSearch = true; native.activateDock(); assert.deepEqual(actions, ['library', 'library', 'search:']);
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
