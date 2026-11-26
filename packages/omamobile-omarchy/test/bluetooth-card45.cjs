// SPDX-License-Identifier: MIT
// Patch 0036: the pure parts of the bar's Bluetooth card's pairing helper
// (its Model.js, patched), loaded as QML loads it.
//   node bluetooth-card45.cjs SHELL_DIR
const fs = require('fs')
const vm = require('vm')
const assert = require('assert/strict')
const path = require('path')

const root = process.argv[2]
assert(root, 'usage: node bluetooth-card45.cjs SHELL')
const scope = { module: { exports: {} } }
vm.createContext(scope)
vm.runInContext(fs.readFileSync(path.join(root, 'plugins/panels/bluetooth/Model.js'), 'utf8'), scope)
const m = scope.module.exports

// The window is the card's to ask for only when Pairable was off as it opened.
assert.deepEqual([...m.helperCommand(false, 120)], ['omamobile-bt-agent', '--pairable-window', '120'])
assert.deepEqual([...m.helperCommand(true, 120)], ['omamobile-bt-agent'])
// And it holds it only when no other panel's helper does (an older helper doesn't say).
const asked = m.helperCommand(false, 120)
assert.equal(m.ownsWindow(asked, { event: 'ready', window: true }), true)
assert.equal(m.ownsWindow(asked, { event: 'ready', window: false }), false)
assert.equal(m.ownsWindow(asked, { event: 'ready' }), true)
assert.equal(m.ownsWindow(m.helperCommand(true, 120), { event: 'ready', window: true }), false)

// Helper lines.
assert.equal(m.parseHelperLine('{"event": "ready"}').event, 'ready')
for (const junk of ['', 'Traceback (most recent call last):', '{"cmd": "pair"}', '{oops', null])
  assert.equal(m.parseHelperLine(junk), null, String(junk))

// What the card asks.
const confirm = m.pairingPrompt({ type: 'confirm', passkey: 4321, label: 'Rental Car', address: '02:00:00:00:00:01' })
assert.equal(confirm.title, 'Pair with Rental Car?')
assert.equal(confirm.code, '004321')
assert.equal(confirm.input, '')
assert.equal(confirm.answer, true)
assert.equal(m.pairingPrompt({ type: 'authorize', address: '02:00:00:00:00:01' }).title, 'Pair with 02:00:00:00:00:01?')
assert.equal(m.pairingPrompt({ type: 'pin', label: 'Car' }).input, 'pin')
assert.equal(m.pairingPrompt({ type: 'passkey', label: 'Keyboard' }).input, 'passkey')
const shown = m.pairingPrompt({ type: 'display-passkey', passkey: 12, entered: 3, label: 'Keyboard' })
assert.equal(shown.code, '000012')
assert.equal(shown.entered, 3)
assert.equal(shown.answer, false)
assert.equal(m.pairingPrompt({ type: 'display-pin', pin: '7788' }).code, '7788')
assert.equal(m.pairingPrompt({ type: 'other' }), null)
assert.equal(m.pairingPrompt(null), null)

// Typed codes, and the replies that carry them.
assert.equal(m.validCode('pin', '0000'), true)
assert.equal(m.validCode('pin', ''), false)
assert.equal(m.validCode('pin', 'x'.repeat(17)), false)
assert.equal(m.validCode('passkey', '123456'), true)
assert.equal(m.validCode('passkey', '1234567'), false)
assert.equal(m.validCode('passkey', '12a'), false)
assert.equal(m.validCode('', ''), true)
assert.equal(JSON.stringify(m.replyCommand({ id: 2, type: 'pin' }, true, '1234')), '{"cmd":"reply","id":2,"accept":true,"value":"1234"}')
assert.equal(JSON.stringify(m.replyCommand({ id: 2, type: 'pin' }, false, '1234')), '{"cmd":"reply","id":2,"accept":false}')
assert.equal(JSON.stringify(m.replyCommand({ id: 3, type: 'confirm' }, true, 'ignored')), '{"cmd":"reply","id":3,"accept":true}')

// The pairing's state.
const car = '02:00:00:00:00:01'
let s = m.pairingStep(null, { event: 'start', address: car })
assert.equal(s.address, car)
s = m.pairingStep(s, { event: 'request', id: 1, type: 'confirm', address: car, passkey: 1 })
assert.equal(s.request.id, 1)
s = m.pairingStep(s, { event: 'answered', accept: true })
assert.equal(s.request, null)
assert.equal(s.address, car)
s = m.pairingStep(s, { event: 'result', op: 'connect', address: car, ok: true })
assert.equal(s.address, car, 'only the pair result ends the pairing')
s = m.pairingStep(s, { event: 'result', op: 'pair', address: car, ok: true })
assert.deepEqual({ ...s }, { address: '', request: null })
// A device pairing to the phone, unasked.
s = m.pairingStep(m.pairingIdle(), { event: 'request', id: 2, type: 'confirm', address: car, passkey: 1 })
assert.equal(s.address, car)
assert.deepEqual({ ...m.pairingStep(s, { event: 'answered', accept: false }) }, { address: '', request: null })
// A shown code stays until the pairing ends or BlueZ cancels.
s = m.pairingStep(m.pairingIdle(), { event: 'request', id: 0, type: 'display-passkey', address: car, passkey: 5 })
s = m.pairingStep(s, { event: 'answered', accept: true })
assert.equal(s.request.type, 'display-passkey')
assert.deepEqual({ ...m.pairingStep(s, { event: 'cancel' }) }, { address: '', request: null })

// Errors.
assert.equal(m.isHarmless('org.bluez.Error.AlreadyConnected'), true)
assert.equal(m.isHarmless('org.bluez.Error.Failed'), false)
assert.equal(m.helperError('pair', 'org.bluez.Error.AuthenticationFailed', ''), 'Pairing failed. Check the code')
assert.equal(m.helperError('pair', 'org.bluez.Error.AuthenticationRejected', ''), 'Pairing rejected')
assert.equal(m.helperError('connect', 'org.bluez.Error.Failed', 'Page Timeout'), 'Out of range')
assert.equal(m.helperError('disconnect', 'org.bluez.Error.Failed', ''), "Couldn't disconnect")
assert.equal(m.helperError('connect', 'org.bluez.Error.Failed', ''), "Couldn't connect")

// Omarchy's own parts are still there.
assert.equal(m.deviceLists([{ name: 'Car', address: car, connected: false, paired: false }]).discovered.length, 1)
console.log('ok - bluetooth card helper model (0036)')
