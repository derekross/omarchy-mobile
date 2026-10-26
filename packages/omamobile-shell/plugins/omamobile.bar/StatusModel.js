// SPDX-License-Identifier: MIT
// Pure helpers for the phone status bar. The glyph sets match Omarchy's own
// network (panels/network/Model.js) and power (panels/power/Model.js) panels,
// so the phone reads the same as the desktop bar.

function findDevice(devices, type) {
  var list = devices || []
  var fallback = null
  for (var i = 0; i < list.length; i++) {
    var device = list[i]
    if (!device || device.type !== type) continue
    if (device.connected) return device
    if (!fallback) fallback = device
  }
  return fallback
}

function connectedNetwork(networks) {
  var list = networks || []
  for (var i = 0; i < list.length; i++)
    if (list[i] && list[i].connected) return list[i]
  return null
}

function wifiIcon(strength) {
  var icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
  var index = Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1))
  return icons[index]
}

// kind: "wifi" | "ethernet" | "off" | "disconnected"
function networkIcon(kind, strength) {
  if (kind === "wifi") return wifiIcon(strength)
  if (kind === "ethernet") return "󰈀"
  if (kind === "off") return "󰤭"
  return "󰤮"
}

function cellularIcon(strength) {
  if (strength < 0) return "󰞃"
  var icons = ["󰢿", "󰢼", "󰢽", "󰢾"]
  return icons[Math.max(0, Math.min(3, Math.floor(strength / 25.01)))]
}

// The mobile network, from bin/omamobile-cell-watch's line: "" hides it.
// Strength -1 (registered, no reading yet) is the empty bars, not "off".
function cellGlyph(cell) {
  if (!cell || !cell.modem || cell.state === "none") return ""
  switch (cell.state) {
  case "off": return String.fromCodePoint(0xF001D)
  case "no-sim": case "locked": case "failed": return String.fromCodePoint(0xF0783)
  case "searching": return String.fromCodePoint(0xF08BF)
  }
  if (cell.strength < 0) return String.fromCodePoint(0xF08BF)
  return cellularIcon(cell.strength)
}

// The words beside it: the SIM's trouble, or the network type (and "R"
// when roaming) once registered.
function cellText(cell) {
  if (!cell || !cell.modem) return ""
  if (cell.state === "no-sim") return "No SIM"
  if (cell.state === "locked") return "SIM locked"
  if (cell.state === "registered" || cell.state === "connected")
    return (cell.tech || "") + (cell.roaming ? (cell.tech ? " R" : "R") : "")
  return ""
}

function parseCell(line) {
  var v
  try { v = JSON.parse(String(line || "")) } catch (e) { return null }
  if (!v || typeof v !== "object") return null
  return { modem: v.modem === true, state: String(v.state || "none"), strength: Number(v.strength),
           tech: String(v.tech || ""), roaming: v.roaming === true }
}

// The call chip: the elapsed time of the call in progress, "" for none.
// Calls as bin/omamobile-call-watch reports them.
function callChip(line, nowMs) {
  var v
  try { v = JSON.parse(String(line || "")) } catch (e) { return null }
  if (!v || !v.agent || !Array.isArray(v.calls)) return ""
  var order = ["active", "held", "dialing", "ringing-out"]
  for (var o = 0; o < order.length; o++)
    for (var i = 0; i < v.calls.length; i++) {
      var c = v.calls[i]
      if (!c || c.state !== order[o]) continue
      if (c.state === "active" && Number(c.answeredMs) > 0) return elapsed(nowMs - Number(c.answeredMs))
      return c.state === "held" ? "On hold" : "Calling"
    }
  return ""
}

function elapsed(ms) {
  var t = Math.max(0, Math.floor((Number(ms) || 0) / 1000))
  var h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60
  var ss = (s < 10 ? "0" : "") + s
  return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss
}

// Unread notifications: Omarchy's history files are named
// <timestamp>-<id>.json (milliseconds since the epoch), and quick settings
// records the newest one its shade has shown. 0 for a name without one.
function stampOf(name) {
  var match = /^(\d+)-/.exec(String(name || ""))
  return match ? Number(match[1]) : 0
}

function parseStamp(text) {
  var value = Number(String(text === undefined || text === null ? "" : text).trim())
  return isFinite(value) && value > 0 ? value : 0
}

function unreadCount(names, seen) {
  var list = names || []
  var since = parseStamp(seen)
  var count = 0
  for (var i = 0; i < list.length; i++)
    if (/\.json$/.test(String(list[i])) && stampOf(list[i]) > since) count++
  return count
}

function batteryIcon(percent, charging, full) {
  if (percent < 0) return ""
  if (full) return "󰂅"
  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(percent / 10)))
  return charging ? chargingIcons[index] : defaultIcons[index]
}

if (typeof module !== "undefined") {
  module.exports = {
    findDevice: findDevice, connectedNetwork: connectedNetwork, wifiIcon: wifiIcon, networkIcon: networkIcon,
    cellularIcon: cellularIcon, cellGlyph: cellGlyph, cellText: cellText, parseCell: parseCell,
    callChip: callChip, elapsed: elapsed, batteryIcon: batteryIcon,
    stampOf: stampOf, parseStamp: parseStamp, unreadCount: unreadCount
  }
}
