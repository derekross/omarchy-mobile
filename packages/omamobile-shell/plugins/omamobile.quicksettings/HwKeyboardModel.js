// SPDX-License-Identifier: MIT
// Pure helpers for the shade's keyboard card (KeyboardCard.qml): the
// hardware keyboards omamobile-osk-guard lists in
// ~/.local/state/omamobile/osk-hwkbd.json, one row each, and the commands of
// the card's buttons. Node runs these in test/hwkeyboard-model.js through the
// module.exports below.

var MAC = /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i

// The guard's file text -> { keyboards: [{ name, uniq, bluetooth, canDisconnect }], mode }
function parse(text) {
  var s = null
  try { s = JSON.parse(String(text || "")) } catch (e) { s = null }
  var out = { keyboards: [], mode: "auto" }
  if (!s || typeof s !== "object") return out
  if (s.mode === "show" || s.mode === "hide") out.mode = s.mode
  var list = Array.isArray(s.keyboards) ? s.keyboards : []
  for (var i = 0; i < list.length; i++) {
    var k = list[i]
    if (!k || typeof k !== "object") continue
    var name = String(k.name || "").trim() || "Keyboard"
    var uniq = String(k.uniq || "")
    var bluetooth = k.bus === "bluetooth"
    out.keyboards.push({ name: name, uniq: uniq, bluetooth: bluetooth, canDisconnect: bluetooth && MAC.test(uniq) })
  }
  return out
}

function rowText(row) {
  return row.name + " connected"
}

function accessibleName(keyboards) {
  var n = keyboards.length
  if (n === 0) return ""
  if (n === 1) return rowText(keyboards[0])
  return n + " keyboards connected"
}

function modeCommand(mode) {
  return ["omamobile-osk-guard", "--mode", mode === "show" ? "show" : "hide"]
}

// null for a keyboard the card can't disconnect (no Bluetooth address)
function disconnectCommand(row) {
  if (!row || !row.canDisconnect) return null
  return ["omamobile-osk-guard", "--disconnect", row.uniq]
}

if (typeof module !== "undefined") {
  module.exports = {
    parse: parse,
    rowText: rowText,
    accessibleName: accessibleName,
    modeCommand: modeCommand,
    disconnectCommand: disconnectCommand
  }
}
