// SPDX-License-Identifier: MIT
const fs = require('fs')
const vm = require('vm')
const assert = require('assert/strict')
const path = require('path')

const root = process.argv[2]
assert(root, 'usage: node notification-store45.cjs SHELL')

function load(file, extras = {}) {
  const scope = { module: { exports: {} }, ...extras }
  vm.createContext(scope)
  const source = fs.readFileSync(file, 'utf8').replace(/^\.(?:pragma|import).*$/mg, '')
  vm.runInContext(source, scope)
  return scope
}

const logic = load(path.join(root, 'plugins/notifications/NotificationLogic.js')).module.exports
const glance = load(path.join(root, 'plugins/lock/LockGlance.js'), { NotificationLogic: logic, Date })
const now = Date.now()
const notification = {
  key: 'nSynthetic1', ts: now / 1000, originalId: 1, app: 'Fixture',
  summary: 'Synthetic summary', body: 'Synthetic body',
  image: 'file:///tmp/synthetic.png', urgency: 1,
}
const history = [
  { ...notification, summary: 'older copy', ts: notification.ts - 1 },
  { ...notification, key: 'nSynthetic2', originalId: 2, ts: notification.ts - 2 },
]
const raw = JSON.stringify([notification]) + '\n' + JSON.stringify(history) + '\n' + JSON.stringify({ dnd: false })
const rows = logic.historyRows(raw, [], 1, 10)
assert.equal(rows.length, 2)
assert.equal(rows[0].key, 'nSynthetic1')
assert.equal(rows[0].timestamp, now)
assert.equal(logic.popupFileName(rows[0]), 'nSynthetic1')
assert.equal(rows[0].summary, notification.summary)
assert.equal(glance.cards(raw, now, false, false).length, 2)

const hidden = glance.cards(raw, now, true, false)[0]
assert.equal(hidden.summary, 'Fixture')
assert.equal(hidden.body, 'Unlock to read')
assert.equal(hidden.image, '')
assert.equal(hidden.file, 'nSynthetic1')
assert.equal(glance.cards(raw, now, false, true).length, 0)
assert.equal(glance.doNotDisturb('{"dnd":true}'), true)
assert.equal(logic.historyRows(JSON.stringify([{ ...notification, key: '../bad' }]), [], 1, 10).length, 0)
assert.equal(logic.historyRows(JSON.stringify([{ ...notification, ts: 'bad' }]), [], 1, 10).length, 0)
assert.equal(logic.historyRows('{"dnd":true}\n', [], 1, 10).length, 0)

const legacy = { originalId: 8, timestamp: now, app: 'Fixture', summary: 'Legacy synthetic' }
const legacyRow = logic.historyRows(JSON.stringify(legacy) + '\n', [], 1, 10)[0]
assert.equal(logic.popupFileName(legacyRow), String(now) + '-8.json')
console.log('PASS 4.5 store/lock-glance: merge, dedupe, timestamp, privacy/DND, malformed rows and legacy records')
