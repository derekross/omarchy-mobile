// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.quicksettings/BluetoothModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.quicksettings/BluetoothModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

const dev = (address, extra) => Object.assign({ address, name: address.replace(/:/g, "-"), deviceName: "", icon: "",
  connected: false, paired: false, bonded: false, trusted: false, pairing: false, batteryAvailable: false, battery: 0 }, extra)

test("appearance picks the kind first", () => {
  assert.strictEqual(M.kindFromAppearance(0x0941), "headphones") // earbud
  assert.strictEqual(M.kindFromAppearance(0x0943), "headphones") // headphones
  assert.strictEqual(M.kindFromAppearance(0x0841), "speaker")
  assert.strictEqual(M.kindFromAppearance(0x03c1), "keyboard")
  assert.strictEqual(M.kindFromAppearance(0x03c2), "mouse")
  assert.strictEqual(M.kindFromAppearance(0x03c4), "gamepad")
  assert.strictEqual(M.kindFromAppearance(0x0040), "phone")
  assert.strictEqual(M.kindFromAppearance(0x0080), "computer")
  assert.strictEqual(M.kindFromAppearance(0x00c1), "watch")
  assert.strictEqual(M.kindFromAppearance(0), "")
  assert.strictEqual(M.kindFromAppearance(null), "")
})

test("class of device maps major and minor classes", () => {
  assert.strictEqual(M.kindFromClass(0x240404), "headphones") // A/V wearable headset
  assert.strictEqual(M.kindFromClass(0x240418), "headphones") // A/V headphones
  assert.strictEqual(M.kindFromClass(0x240414), "speaker")    // A/V loudspeaker
  assert.strictEqual(M.kindFromClass(0x002540), "keyboard")
  assert.strictEqual(M.kindFromClass(0x002580), "mouse")
  assert.strictEqual(M.kindFromClass(0x002508), "gamepad")
  assert.strictEqual(M.kindFromClass(0x5a020c), "phone")
  assert.strictEqual(M.kindFromClass(0x3c010c), "computer")
  assert.strictEqual(M.kindFromClass(0x000704), "watch")
  assert.strictEqual(M.kindFromClass(0x000600), "")           // imaging
})

test("BlueZ icon names are the fallback, then generic", () => {
  assert.strictEqual(M.deviceKind("audio-headset", null, null), "headphones")
  assert.strictEqual(M.deviceKind("audio-card", null, null), "speaker")
  assert.strictEqual(M.deviceKind("input-keyboard", null, null), "keyboard")
  assert.strictEqual(M.deviceKind("input-mouse", null, null), "mouse")
  assert.strictEqual(M.deviceKind("input-gaming", null, null), "gamepad")
  assert.strictEqual(M.deviceKind("phone", null, null), "phone")
  assert.strictEqual(M.deviceKind("computer", null, null), "computer")
  assert.strictEqual(M.deviceKind("", null, null), "generic")
  assert.strictEqual(M.deviceKind("computer", 0x03c1, null), "keyboard", "appearance beats the icon")
  assert.strictEqual(M.deviceKind("", null, 0x240418), "headphones")
  for (const kind of ["headphones", "speaker", "keyboard", "mouse", "gamepad", "phone", "computer", "watch", "generic"])
    assert.ok(M.kindGlyph(kind).length > 0, kind)
  assert.strictEqual(M.kindGlyph("nonsense"), M.kindGlyph("generic"))
})

test("address-only devices are unnamed; a rename counts as a name", () => {
  let row = M.deviceRow(dev("AA:BB:CC:DD:EE:01"), null)
  assert.strictEqual(row.named, false)
  assert.strictEqual(row.label, "AA:BB:CC:DD:EE:01")
  row = M.deviceRow(dev("AA:BB:CC:DD:EE:02", { name: "Buds", deviceName: "Buds" }), { rssi: -50 })
  assert.strictEqual(row.named, true)
  assert.strictEqual(row.label, "Buds")
  assert.strictEqual(row.rssi, -50)
  row = M.deviceRow(dev("AA:BB:CC:DD:EE:03", { name: "Desk", deviceName: "K380" }), null)
  assert.strictEqual(row.label, "Desk")
  assert.strictEqual(row.rssi, -999)
  assert.strictEqual(M.deviceRow(null, null), null)
})

test("battery is a whole percentage, or -1", () => {
  assert.strictEqual(M.deviceRow(dev("AA:BB:CC:DD:EE:04", { batteryAvailable: true, battery: 0.736 }), null).battery, 74)
  assert.strictEqual(M.deviceRow(dev("AA:BB:CC:DD:EE:05", { battery: 0.5 }), null).battery, -1)
  assert.strictEqual(M.batteryText(74), "74%")
  assert.strictEqual(M.batteryText(-1), "")
})

test("paired: connected first then by name; available by signal; unnamed apart", () => {
  const rows = [
    { address: "1", label: "zeta", named: true, paired: true, connected: false, rssi: -40 },
    { address: "2", label: "Alpha", named: true, paired: true, connected: false, rssi: -90 },
    { address: "3", label: "Buds", named: true, paired: true, connected: true, rssi: -60 },
    { address: "4", label: "Far", named: true, paired: false, connected: false, rssi: -88 },
    { address: "5", label: "Near", named: true, paired: false, connected: false, rssi: -45 },
    { address: "6", label: "Quiet", named: true, paired: false, connected: false, rssi: -999 },
    { address: "7", label: "AA:..:07", named: false, paired: false, connected: false, rssi: -30 },
    { address: "8", label: "AA:..:08", named: false, paired: false, connected: false, rssi: -70 }
  ]
  const lists = M.buildLists(rows)
  assert.deepStrictEqual(lists.paired.map(r => r.label), ["Buds", "Alpha", "zeta"])
  assert.deepStrictEqual(lists.available.map(r => r.label), ["Near", "Far", "Quiet"])
  assert.deepStrictEqual(lists.unnamed.map(r => r.address), ["7", "8"])
})

test("list entries: sections, the unnamed toggle, uniform fields", () => {
  const lists = M.buildLists([
    M.deviceRow(dev("AA:BB:CC:DD:EE:10", { name: "Buds", deviceName: "Buds", paired: true, connected: true }), null),
    M.deviceRow(dev("AA:BB:CC:DD:EE:11", { name: "Speaker", deviceName: "Speaker" }), { rssi: -60 }),
    M.deviceRow(dev("AA:BB:CC:DD:EE:12"), { rssi: -50 })
  ])
  let entries = M.listEntries(lists, false, true)
  assert.deepStrictEqual(entries.map(e => e.kind + ":" + (e.text || e.label)),
    ["header:Paired devices", "device:Buds", "header:Available devices", "device:Speaker", "more:Show 1 unnamed device"])
  entries = M.listEntries(lists, true, true)
  assert.deepStrictEqual(entries.slice(-2).map(e => e.kind + ":" + (e.text || e.label)),
    ["more:Hide 1 unnamed device", "device:AA:BB:CC:DD:EE:12"])
  const keys = Object.keys(entries[0]).sort().join()
  for (const e of entries) assert.strictEqual(Object.keys(e).sort().join(), keys)
  assert.deepStrictEqual(M.listEntries(lists, false, false), [])
  assert.deepStrictEqual(M.listEntries(M.buildLists([]), false, true).map(e => e.kind), ["header", "empty"])
})

test("taps, long-presses and status text", () => {
  const fresh = { paired: false, connected: false, named: true, battery: -1 }
  const paired = { paired: true, connected: false, named: true, battery: -1 }
  const live = { paired: true, connected: true, named: true, battery: 80 }
  assert.strictEqual(M.tapAction(fresh), "pair")
  assert.strictEqual(M.tapAction(paired), "connect")
  assert.strictEqual(M.tapAction(live), "actions")
  assert.deepStrictEqual(M.longPressActions(fresh), [])
  assert.deepStrictEqual(M.longPressActions(paired), ["connect", "rename", "forget"])
  assert.deepStrictEqual(M.longPressActions(live), ["disconnect", "rename", "forget"])
  assert.strictEqual(M.rowStatus(live, "", ""), "Connected · 80%")
  assert.strictEqual(M.rowStatus(paired, "", ""), "Paired")
  assert.strictEqual(M.rowStatus(fresh, "pair", ""), "Pairing…")
  assert.strictEqual(M.rowStatus(fresh, "", "Device out of range"), "Device out of range")
  assert.strictEqual(M.rowStatus(fresh, "", ""), "")
  assert.strictEqual(M.visibilityText(105), "Visible for 1:45")
  assert.strictEqual(M.visibilityText(5), "Visible for 0:05")
})

test("BlueZ errors read as people would say them", () => {
  assert.strictEqual(M.errorMessage("pair", "org.bluez.Error.AuthenticationFailed", ""), "Pairing failed. Check the code")
  assert.strictEqual(M.errorMessage("pair", "org.bluez.Error.AuthenticationCanceled", ""), "Pairing canceled")
  assert.strictEqual(M.errorMessage("pair", "org.bluez.Error.AuthenticationRejected", ""), "Pairing rejected")
  assert.strictEqual(M.errorMessage("pair", "org.bluez.Error.AuthenticationTimeout", ""), "Pairing timed out")
  assert.strictEqual(M.errorMessage("connect", "org.bluez.Error.Failed", "br-connection-page-timeout"), "Device out of range")
  assert.strictEqual(M.errorMessage("pair", "org.bluez.Error.ConnectionAttemptFailed", "Page Timeout"), "Device out of range")
  assert.strictEqual(M.errorMessage("connect", "org.bluez.Error.Failed", "br-connection-refused"), "Connection refused")
  assert.strictEqual(M.errorMessage("connect", "org.bluez.Error.Failed", "br-connection-profile-unavailable"), "Paired. Nothing to connect to")
  assert.strictEqual(M.errorMessage("connect", "org.bluez.Error.NotReady", "Resource Not Ready"), "Bluetooth is off")
  assert.strictEqual(M.errorMessage("pair", "org.bluez.Error.DoesNotExist", ""), "Device out of range")
  assert.strictEqual(M.errorMessage("pair", "org.freedesktop.DBus.Error.NoReply", ""), "Pairing timed out")
  assert.strictEqual(M.errorMessage("connect", "", ""), "Couldn't connect")
  assert.strictEqual(M.isHarmless("org.bluez.Error.AlreadyExists"), true)
  assert.strictEqual(M.isHarmless("org.bluez.Error.Failed"), false)
  assert.strictEqual(M.isHarmless("org.bluez.Error.NotConnected"), true)
  assert.strictEqual(M.errorMessage("disconnect", "org.bluez.Error.Failed", ""), "Couldn't disconnect")
})

test("helper lines parse, junk doesn't", () => {
  assert.deepStrictEqual(M.parseHelperLine('{"event":"ready","adapter":"/org/bluez/hci0"}'), { event: "ready", adapter: "/org/bluez/hci0" })
  assert.strictEqual(M.parseHelperLine("Traceback (most recent call last):"), null)
  assert.strictEqual(M.parseHelperLine("{broken"), null)
  assert.strictEqual(M.parseHelperLine('{"cmd":"pair"}'), null)
  assert.strictEqual(M.parseHelperLine(""), null)
})

test("agent requests become sheets", () => {
  let s = M.requestSheet({ type: "confirm", passkey: 4321, label: "Buds" })
  assert.strictEqual(s.display, "004321")
  assert.strictEqual(s.input, "")
  assert.strictEqual(s.accept, "Pair")
  s = M.requestSheet({ type: "display-passkey", passkey: 123456, entered: 3, label: "K380" })
  assert.strictEqual(s.display, "123456")
  assert.strictEqual(s.entered, 3)
  assert.strictEqual(s.accept, "", "nothing to answer, only cancel")
  assert.strictEqual(M.requestSheet({ type: "pin" }).input, "pin")
  assert.strictEqual(M.requestSheet({ type: "passkey" }).input, "passkey")
  assert.strictEqual(M.requestSheet({ type: "authorize", label: "Phone" }).title, "Pair with Phone?")
  assert.strictEqual(M.requestSheet({ type: "display-pin", pin: "0000" }).display, "0000")
  assert.strictEqual(M.requestSheet({ type: "?" }), null)
})

test("PIN and passkey input checks and replies", () => {
  assert.strictEqual(M.validInput("pin", "0000"), true)
  assert.strictEqual(M.validInput("pin", ""), false)
  assert.strictEqual(M.validInput("pin", "x".repeat(17)), false)
  assert.strictEqual(M.validInput("passkey", "123456"), true)
  assert.strictEqual(M.validInput("passkey", "1234567"), false)
  assert.strictEqual(M.validInput("passkey", "12a"), false)
  assert.deepStrictEqual(JSON.parse(M.replyCommand({ id: 4, type: "pin" }, true, "1234")), { cmd: "reply", id: 4, accept: true, value: "1234" })
  assert.deepStrictEqual(JSON.parse(M.replyCommand({ id: 5, type: "confirm" }, true, "ignored")), { cmd: "reply", id: 5, accept: true })
  assert.deepStrictEqual(JSON.parse(M.replyCommand({ id: 6, type: "pin" }, false, "1234")), { cmd: "reply", id: 6, accept: false })
})

test("pairing state machine: numeric comparison to done", () => {
  let s = M.pairingStep(null, { event: "start", address: "AA" })
  assert.strictEqual(s.phase, "pairing")
  s = M.pairingStep(s, { event: "request", id: 1, type: "confirm", address: "AA", passkey: 1 })
  assert.strictEqual(s.phase, "prompt")
  s = M.pairingStep(s, { event: "answered", accept: true })
  assert.strictEqual(s.phase, "pairing")
  assert.strictEqual(s.request, null)
  s = M.pairingStep(s, { event: "result", op: "pair", address: "AA", ok: true })
  assert.strictEqual(s.phase, "done")
})

test("pairing state machine: keyboard passkey display stays up until the result", () => {
  let s = M.pairingStep(null, { event: "start", address: "KB" })
  s = M.pairingStep(s, { event: "request", id: 0, type: "display-passkey", address: "KB", passkey: 123456, entered: 0 })
  s = M.pairingStep(s, { event: "request", id: 0, type: "display-passkey", address: "KB", passkey: 123456, entered: 4 })
  assert.strictEqual(s.request.entered, 4)
  s = M.pairingStep(s, { event: "answered", accept: true })
  assert.strictEqual(s.phase, "prompt", "a display has nothing to answer")
  s = M.pairingStep(s, { event: "result", op: "pair", address: "KB", ok: false, error: "org.bluez.Error.AuthenticationFailed" })
  assert.strictEqual(s.phase, "failed")
  assert.strictEqual(s.error, "Pairing failed. Check the code")
})

test("pairing state machine: declining, BlueZ cancel, harmless errors, reset", () => {
  let s = M.pairingStep(M.pairingStep(null, { event: "start", address: "AA" }), { event: "request", id: 2, type: "pin", address: "AA" })
  assert.strictEqual(M.pairingStep(s, { event: "answered", accept: false }).error, "Pairing canceled")
  assert.strictEqual(M.pairingStep(s, { event: "cancel" }).phase, "failed")
  assert.strictEqual(M.pairingStep(M.pairingStep(null, { event: "reset" }), { event: "cancel" }).phase, "idle")
  s = M.pairingStep(null, { event: "start", address: "AA" })
  assert.strictEqual(M.pairingStep(s, { event: "result", op: "pair", address: "AA", ok: false, error: "org.bluez.Error.AlreadyExists" }).phase, "done")
  assert.strictEqual(M.pairingStep(s, { event: "result", op: "pair", address: "BB", ok: true }).phase, "pairing", "another device's result")
  assert.strictEqual(M.pairingStep(s, { event: "reset" }).phase, "idle")
  // Someone else pairing to us still gets a prompt.
  s = M.pairingStep(null, { event: "request", id: 3, type: "authorize", address: "CC" })
  assert.strictEqual(s.phase, "prompt")
  assert.strictEqual(s.address, "CC")
})

test("pairing is wanted only while the owner pairs, or while visible with the helper's agent", () => {
  assert.strictEqual(M.pairableWanted(null), false)
  assert.strictEqual(M.pairableWanted({ opened: true }), false, "an open panel alone")
  assert.strictEqual(M.pairableWanted({ opened: true, visible: true, helper: true }), true)
  assert.strictEqual(M.pairableWanted({ opened: true, visible: true, helper: false }), false, "no agent to answer")
  assert.strictEqual(M.pairableWanted({ opened: true, pairing: true }), true, "the owner's own pairing, helper or not")
  assert.strictEqual(M.pairableWanted({ opened: true, pairing: true, helper: true }), true)
  assert.strictEqual(M.pairableWanted({ opened: false, visible: true, pairing: true, helper: true }), false, "never while closed")
})

let failed = 0
for (const [name, fn] of tests) {
  try {
    fn()
    console.log("ok - bluetooth model: " + name)
  } catch (error) {
    failed++
    console.error("not ok - bluetooth model: " + name + "\n  " + String(error && error.message || error).split("\n").join("\n  "))
  }
}
process.exit(failed ? 1 : 0)
