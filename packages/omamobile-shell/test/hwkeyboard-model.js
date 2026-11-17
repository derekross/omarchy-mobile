// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.quicksettings/HwKeyboardModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.quicksettings/HwKeyboardModel.js"))

const dell = { id: "00:00:5e:00:53:01", name: "Dell Keybd Keyboard", uniq: "00:00:5e:00:53:01", bus: "bluetooth" }
const usb = { id: "usb-1", name: "USB Keyboard", uniq: "", bus: "usb" }

let s = M.parse(JSON.stringify({ keyboards: [dell, usb], mode: "show" }))
assert.strictEqual(s.mode, "show")
assert.deepStrictEqual(s.keyboards.map(k => [k.name, k.bluetooth, k.canDisconnect]),
  [["Dell Keybd Keyboard", true, true], ["USB Keyboard", false, false]])
assert.strictEqual(M.rowText(s.keyboards[0]), "Dell Keybd Keyboard connected")
assert.strictEqual(M.accessibleName(s.keyboards), "2 keyboards connected")
assert.strictEqual(M.accessibleName(s.keyboards.slice(0, 1)), "Dell Keybd Keyboard connected")
assert.deepStrictEqual(M.disconnectCommand(s.keyboards[0]), ["omamobile-osk-guard", "--disconnect", "00:00:5e:00:53:01"])
assert.strictEqual(M.disconnectCommand(s.keyboards[1]), null)
console.log("ok - rows per keyboard, Disconnect only with a Bluetooth address")

// A Bluetooth keyboard without a usable uniq: no Disconnect
s = M.parse(JSON.stringify({ keyboards: [{ name: "", uniq: "", bus: "bluetooth" }, { name: "X", uniq: "x; reboot", bus: "bluetooth" }] }))
assert.deepStrictEqual(s.keyboards.map(k => [k.name, k.canDisconnect]), [["Keyboard", false], ["X", false]])
assert.strictEqual(s.mode, "auto")
console.log("ok - no or a bad uniq hides Disconnect; a nameless keyboard is 'Keyboard'")

// Missing, empty or broken file: no card
for (const t of ["", "null", "{", "[]", JSON.stringify({ keyboards: "x", mode: "weird" })]) {
  assert.deepStrictEqual(M.parse(t), { keyboards: [], mode: "auto" })
}
assert.strictEqual(M.accessibleName([]), "")
assert.deepStrictEqual(M.modeCommand("show"), ["omamobile-osk-guard", "--mode", "show"])
assert.deepStrictEqual(M.modeCommand("hide"), ["omamobile-osk-guard", "--mode", "hide"])
console.log("ok - a missing or broken file shows no card; the mode buttons' commands")
