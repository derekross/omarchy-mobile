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
  // Mobile data off: the crossed-out bars, as quick settings' Mobile data
  // tile shows it (calls and texts still work; the card says so).
  if (cell.data === false) return String.fromCodePoint(0xF0783)
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
           tech: String(v.tech || ""), roaming: v.roaming === true,
           data: v.data === true ? true : (v.data === false ? false : null) }
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

// Omarchy 4.5 keeps its history in one file, history.json: a JSON array of
// rows, each with `ts`, when it arrived, in seconds. The shade's mark is in
// milliseconds, rounded as its NotificationsModel.storeEntry rounds them.
function unreadStored(text, seen) {
  var rows = null
  try { rows = JSON.parse(String(text === undefined || text === null ? "" : text)) } catch (error) { return 0 }
  if (!Array.isArray(rows)) return 0
  var since = parseStamp(seen)
  var count = 0
  for (var i = 0; i < rows.length; i++) {
    var ts = rows[i] && typeof rows[i] === "object" ? Number(rows[i].ts) : 0
    if (isFinite(ts) && ts > 0 && Math.round(ts * 1000) > since) count++
  }
  return count
}

function batteryIcon(percent, charging, full) {
  if (percent < 0) return ""
  if (full) return "󰁹"
  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(percent / 10)))
  return charging ? chargingIcons[index] : defaultIcons[index]
}

// The bar's own keys in shell.json's bar object (batteryStyle, statusIcons).
var BATTERY_STYLES = ["icon", "percent", "icon-percent", "horizontal", "horizontal-percent"]
var STATUS_ICONS = ["bluetooth", "wifi", "cell", "dnd", "unread"]

// bar.batteryStyle, one of BATTERY_STYLES. Without one (or an unknown one)
// the older bar.showBatteryPercent decides, as it did before: false is the
// icon alone, anything else the icon and the number.
function batteryStyle(config) {
  var c = config && typeof config === "object" ? config : {}
  var s = c.batteryStyle
  if (typeof s === "string" && BATTERY_STYLES.indexOf(s) >= 0) return s
  return c.showBatteryPercent === false ? "icon" : "icon-percent"
}

// bar.statusIcons.<name>: only an explicit false hides an icon.
function iconShown(config, name) {
  var c = config && typeof config === "object" ? config : {}
  var icons = c.statusIcons && typeof c.statusIcons === "object" ? c.statusIcons : {}
  return icons[name] !== false
}

// The bolt shown beside the styles whose glyph has none (BatteryIndicator:
// the icon styles use the charging glyphs, which carry one).
function boltGlyph() { return String.fromCodePoint(0xF140B) }

function batteryLow(percent, charging) {
  return percent >= 0 && percent <= 10 && charging !== true
}

// A device's camera-hole insets from bar-cutout.json ({"left": n,
// "right": n}, logical px). Anything unreadable or not a positive number is
// left out, so the bar keeps its stock inset on that side.
function parseCutout(text) {
  var v
  try { v = JSON.parse(String(text || "")) } catch (e) { return {} }
  var out = {}
  if (!v || typeof v !== "object") return out
  ;["left", "right"].forEach(function(side) {
    var n = Number(v[side])
    if (typeof v[side] === "number" && isFinite(n) && n > 0) out[side] = n
  })
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    findDevice: findDevice, connectedNetwork: connectedNetwork, wifiIcon: wifiIcon, networkIcon: networkIcon,
    cellularIcon: cellularIcon, cellGlyph: cellGlyph, cellText: cellText, parseCell: parseCell,
    callChip: callChip, elapsed: elapsed, batteryIcon: batteryIcon,
    batteryStyle: batteryStyle, iconShown: iconShown, boltGlyph: boltGlyph, batteryLow: batteryLow,
    BATTERY_STYLES: BATTERY_STYLES, STATUS_ICONS: STATUS_ICONS,
    stampOf: stampOf, parseStamp: parseStamp, unreadCount: unreadCount, unreadStored: unreadStored,
    parseCutout: parseCutout
  }
}
