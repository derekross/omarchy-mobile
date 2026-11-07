// SPDX-License-Identifier: MIT
// Exercise the actual QML JavaScript bindings with representative UPower states.
const assert = require('assert')
const fs = require('fs')
const vm = require('vm')
const path = require('path')

const root = process.argv[2] || path.join(__dirname, '..')
const read = (name) => fs.readFileSync(path.join(root, 'plugins', name), 'utf8')
const home = read('omamobile.home/BatteryWidget.qml')
const bar = read('omamobile.bar/Bar.qml')
const quick = read('omamobile.quicksettings/QuickSettings.qml')
const statusModel = require(path.resolve(root, 'plugins/omamobile.bar/StatusModel.js'))
assert.strictEqual(statusModel.batteryIcon(91, false, true), '󰁹',
  'Full below 100% must use the full battery glyph without a charging bolt')
assert.notStrictEqual(statusModel.batteryIcon(91, true, false), '󰁹',
  'Charging must retain its charging glyph')
function capture(text, pattern, name) {
  const match = text.match(pattern)
  assert(match, `could not find ${name} binding`)
  return match[1]
}
const binding = (text, name) => capture(text, new RegExp(`readonly property (?:bool|real) ${name}: ([^\\n]+)`), name)
const S = { Unknown: 0, Charging: 1, Discharging: 2, Empty: 3, FullyCharged: 4, PendingCharge: 5, PendingDischarge: 6 }
const evaluate = (expr, ctx) => vm.runInNewContext(expr, ctx)
const barCharging = binding(bar, 'charging')
assert.strictEqual(evaluate(barCharging, { hasBattery: true, battery: { state: S.Unknown },
  UPower: { onBattery: false }, UPowerDeviceState: S }), false, 'unknown state must not show charging')
const homeCharging = binding(home, 'charging')
const homeDischarging = binding(home, 'discharging')
const homeSeconds = binding(home, 'seconds')
const homeDetail = capture(home, /readonly property string detail: ([\s\S]*?)\n\n/, 'battery detail')
const duration = capture(home, /(function duration\(s\) \{[\s\S]*?\n  \})/, 'duration')
const quickText = capture(quick, /text: (root\.hasBattery\s*\n\s*\?[^\n]+\n\s*: "")/, 'quick settings battery text')

function state(state, present = true) {
  const battery = present ? { state, percentage: .5, timeToFull: 3600, timeToEmpty: 7200 } : null
  // External power can be present even when the device does not report charging.
  const ctx = { battery, present, hasBattery: present, UPowerDeviceState: S, UPower: { onBattery: false } }
  ctx.charging = evaluate(homeCharging, ctx)
  ctx.discharging = evaluate(homeDischarging, ctx)
  ctx.full = present && state === S.FullyCharged
  ctx.seconds = evaluate(homeSeconds, ctx)
  ctx.duration = evaluate('(' + duration + ')', ctx)
  return {
    homeCharging: ctx.charging,
    barCharging: evaluate(barCharging, ctx),
    text: evaluate(quickText, { ...ctx, root: { hasBattery: present, battery } }),
    detail: evaluate(homeDetail, ctx),
  }
}

for (const [value, text] of [[S.Unknown, 'Charging status unknown'], [S.PendingCharge, 'Waiting to charge'],
  [S.PendingDischarge, 'Waiting to discharge'], [S.Empty, 'Empty'], [S.FullyCharged, 'Full']]) {
  const got = state(value)
  assert.strictEqual(got.homeCharging, false)
  assert.strictEqual(got.barCharging, false)
  assert.strictEqual(got.text, '󰁹 50%')
  assert.strictEqual(got.detail, text)
}
assert.strictEqual(state(S.Charging).detail, 'Full in 1 h 0 min')
assert.strictEqual(state(S.Charging).homeCharging, true)
assert.strictEqual(state(S.Charging).text, '󰂄 50%')
assert.strictEqual(state(S.Charging).barCharging, true)
assert.strictEqual(state(S.Discharging).detail, '2 h 0 min left')
assert.strictEqual(state(S.Unknown, false).detail, 'No battery')
assert.strictEqual(state(S.Unknown, false).text, '')
console.log('ok - explicit battery states in home, bar and quick settings')
