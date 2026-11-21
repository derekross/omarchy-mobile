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

// The keyboard layout label, the way Omarchy 4.5's own bar widget makes it
// (shell/plugins/bar/widgets/KeyboardLayoutModel.js): xkb's short code
// ("brief", from `xkbcli list`) for the layout's description, else the first
// word of the description, capped at 3 characters.
function layoutBriefs(text) {
  var briefs = {}
  var brief = ""
  String(text || "").split("\n").forEach(function(line) {
    if (/^\s*- /.test(line)) brief = ""
    var field = line.match(/^  (brief|description): (.*)$/)
    if (!field) return
    if (field[1] === "brief") brief = field[2].replace(/^'|'$/g, "")
    else if (brief) { briefs[field[2]] = brief; brief = "" }
  })
  return briefs
}
function shortLabel(description, briefs) {
  if (!description) return ""
  var brief = (briefs || {})[description]
  var label = typeof brief === "string" && brief ? brief.split("-")[0] : String(description).split(/\s+/)[0]
  return label.substring(0, 3).toUpperCase()
}
// Keyboards nobody types on: squeekboard's virtual keyboard and pseudo ones.
var untypedKeyboards = /^hl-virtual-keyboard|consumer-control|power-button|sleep-button|lid-switch|video-bus|radio-control|gpio-keys/
function typedKeyboard(name) {
  name = String(name || "")
  return name !== "" && !untypedKeyboards.test(name)
}
// Hyprland's activelayout event is "keyboard,description": the layout is read
// from the event itself, no `hyprctl` per switch. `fields` is event.parse(2)
// where Quickshell has it (a description can hold a comma), else the raw
// data split at the first comma. null for a keyboard nobody types on
// (squeekboard sends these while the on-screen keyboard is used). With
// `real` (the names of the real keyboards from the last read) a keyboard
// not among them is null too, the same rule as the devices read (#866's
// bus/key check), so a phone key device the name list misses never sets it.
function eventFields(fields) {
  if (Array.isArray(fields)) return fields.length >= 2 ? [String(fields[0]), String(fields[1])] : null
  var s = String(fields || "")
  var i = s.indexOf(",")
  return i < 0 ? null : [s.slice(0, i), s.slice(i + 1)]
}
function eventLayout(fields, real) {
  var f = eventFields(fields)
  if (!f || !typedKeyboard(f[0])) return null
  if (Array.isArray(real) && real.indexOf(f[0]) < 0) return null
  return f[1]
}
// Hyprland's device names: the kernel's name lowercased, with space, ',' and
// newline as '-' (deviceNameToInternalString).
function hyprName(name) {
  return String(name || "").toLowerCase().replace(/[ ,\n]/g, "-")
}
// Two input devices with one name get "-1", "-2", ... appended by Hyprland.
function isRealName(real, name) {
  var n = String(name)
  return real.some(function(r) {
    return n === r || (n.length > r.length + 1 && n.indexOf(r + "-") === 0 && /^[0-9]+$/.test(n.slice(r.length + 1)))
  })
}
// The bar's one read: `omamobile-keyboards` (the real keyboards, #866's
// bus/key rule), a separator line, then `hyprctl -j devices`. When
// omamobile-keyboards is missing or fails, the read has `keyboardsFailed`
// in place of names: no keyboard counts (the phone's keys must never show
// the label) and `failed` is true so the bar can say why in its log.
var readSeparator = "--hyprctl--"
var keyboardsFailed = "--keyboards-failed--"
function splitRead(text) {
  var s = String(text || "")
  var i = s.indexOf(readSeparator + "\n")
  if (i < 0) return null
  var lines = s.slice(0, i).split("\n").filter(function(l) { return l !== "" })
  var failed = lines.indexOf(keyboardsFailed) >= 0
  var real = failed ? [] : lines.map(hyprName)
  return { real: real, failed: failed, devices: s.slice(i + readSeparator.length + 1) }
}
// From `hyprctl -j devices` (at start, after a config reload, for a keyboard
// not seen before, and every few seconds while the label shows):
// {count, description, names} of the keyboard furthest along its list, the
// one being typed on (Omarchy's rule). With `real` (hyprName'd names from
// omamobile-keyboards) only those count, so the phone's own key devices
// never do, whatever they are called; without it the name list decides.
function layoutState(text, real) {
  var kbs
  try { kbs = (JSON.parse(text) || {}).keyboards } catch (e) { return null }
  if (!Array.isArray(kbs)) return null
  var typed = kbs.filter(function(k) {
    return k && typedKeyboard(k.name) && (!Array.isArray(real) || isRealName(real, k.name))
  })
  var names = typed.map(function(k) { return String(k.name) })
  if (!typed.length) return { count: 0, description: "", names: names }
  var kb = typed.reduce(function(a, k) { return (k.active_layout_index || 0) > (a.active_layout_index || 0) ? k : a }, typed[0])
  var count = String(kb.layout || "").split(",").filter(function(l) { return l !== "" }).length
  return { count: count, description: String(kb.active_keymap || ""), names: names }
}
// Whether a Hyprland event means `hyprctl -j devices` must be read again:
// a config reload, or an activelayout from a typed keyboard not seen in the
// last read (one plugged in or paired later; Hyprland has no device-added
// event on its socket). The bar also calls it with the real keyboards as
// `known`, for a device it saw but didn't count (read again, throttled).
function needsDeviceRead(name, fields, known) {
  if (name === "configreloaded") return true
  if (name !== "activelayout") return false
  var f = eventFields(fields)
  return !!f && typedKeyboard(f[0]) && (known || []).indexOf(f[0]) < 0
}

if (typeof module !== "undefined") {
  module.exports = {
    findDevice: findDevice, connectedNetwork: connectedNetwork, wifiIcon: wifiIcon, networkIcon: networkIcon,
    cellularIcon: cellularIcon, cellGlyph: cellGlyph, cellText: cellText, parseCell: parseCell,
    callChip: callChip, elapsed: elapsed, batteryIcon: batteryIcon,
    stampOf: stampOf, parseStamp: parseStamp, unreadCount: unreadCount, unreadStored: unreadStored,
    layoutBriefs: layoutBriefs, shortLabel: shortLabel, eventLayout: eventLayout, layoutState: layoutState,
    needsDeviceRead: needsDeviceRead, eventFields: eventFields, hyprName: hyprName, splitRead: splitRead,
    readSeparator: readSeparator, keyboardsFailed: keyboardsFailed
  }
}
