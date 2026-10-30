// SPDX-License-Identifier: MIT
// The quick-settings tile layout: which tiles the sheet shows, in what order,
// and the tiles the edit mode offers to add. Pure functions over arrays of
// tile ids, so QuickSettings.qml can rebuild its views from a plain list and
// Node can test the rules in test/tiles-model.js through module.exports.
//
// The layout is per user, in ~/.config/omamobile/quicksettings.json:
//   { "version": 1, "tiles": ["wifi", "bluetooth", ...] }
// Unknown ids (a tile a later version dropped) and duplicates are skipped;
// a missing or unreadable file means the default layout.

var VERSION = 1

// Every tile the sheet knows, in the order the "available" list shows them.
var CATALOG = [
  { id: "wifi", label: "Wi-Fi" },
  { id: "bluetooth", label: "Bluetooth" },
  { id: "mobile-data", label: "Mobile data" },
  { id: "airplane", label: "Airplane mode" },
  { id: "hotspot", label: "Hotspot" },
  { id: "dnd", label: "Do not disturb" },
  { id: "torch", label: "Torch" },
  { id: "rotation-lock", label: "Rotation lock" },
  { id: "location", label: "Location" },
  { id: "nfc", label: "NFC" },
  { id: "battery-saver", label: "Battery saver" },
  { id: "dark-theme", label: "Dark theme" },
  { id: "night-light", label: "Night light" },
  { id: "stay-awake", label: "Stay awake" },
  { id: "mic", label: "Microphone" },
  { id: "screenshot", label: "Screenshot" },
  { id: "screen-record", label: "Screen record" },
  { id: "fingerprint", label: "Fingerprint" },
  { id: "keyboard", label: "Keyboard" },
  { id: "clipboard", label: "Clipboard" },
  { id: "dictation", label: "Dictation" },
  { id: "reminder", label: "Reminder" }
]

// The first four are the collapsed sheet's row, as on Android: the toggles
// reached for most. Clipboard and Dictation close the second page and
// Reminder opens a third: Omarchy reaches them only by keyboard shortcut,
// so a tile is their touch path (TOUCH-PLAN 1.12), and appending them
// leaves the earlier pages as they were.
var DEFAULT_LAYOUT = [
  "wifi", "bluetooth", "dnd", "torch",
  "mobile-data", "rotation-lock", "airplane", "location",
  "battery-saver", "dark-theme", "night-light", "nfc",
  "fingerprint", "keyboard", "clipboard", "dictation",
  "reminder"
]

var QUICK_COUNT = 4
var PAGE_SIZE = 8

function known(id) {
  for (var i = 0; i < CATALOG.length; i++)
    if (CATALOG[i].id === id) return true
  return false
}

function label(id) {
  for (var i = 0; i < CATALOG.length; i++)
    if (CATALOG[i].id === id) return CATALOG[i].label
  return String(id)
}

function defaults() {
  return DEFAULT_LAYOUT.slice()
}

// Known ids only, each once, in the given order. Anything that isn't an
// array falls back to the default; an empty array stays empty (the user
// removed every tile, which edit mode allows).
function sanitize(layout) {
  if (!Array.isArray(layout)) return defaults()
  var seen = {}
  var out = []
  for (var i = 0; i < layout.length; i++) {
    var id = layout[i]
    if (typeof id !== "string" || !known(id) || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out
}

function parseConfig(text) {
  var data = null
  try { data = JSON.parse(String(text || "")) } catch (error) { return defaults() }
  if (!data || typeof data !== "object" || !Array.isArray(data.tiles)) return defaults()
  return sanitize(data.tiles)
}

// A layout from the command line: a JSON array, or ids separated by spaces
// or commas. Null for anything else.
function parseList(text) {
  var value = String(text === undefined || text === null ? "" : text).trim()
  if (value.charAt(0) === "[") {
    var list = null
    try { list = JSON.parse(value) } catch (error) { return null }
    return Array.isArray(list) ? sanitize(list) : null
  }
  if (value === "" || !/^[a-z, -]*$/.test(value)) return null
  return sanitize(value.split(/[\s,]+/).filter(function(id) { return id.length > 0 }))
}

function serialize(layout) {
  return JSON.stringify({ version: VERSION, tiles: sanitize(layout) }, null, 2) + "\n"
}

// Catalog order, minus what the layout already shows.
function available(layout) {
  var shown = {}
  var list = sanitize(layout)
  for (var i = 0; i < list.length; i++) shown[list[i]] = true
  var out = []
  for (var j = 0; j < CATALOG.length; j++)
    if (!shown[CATALOG[j].id]) out.push(CATALOG[j].id)
  return out
}

function indexOf(layout, id) {
  for (var i = 0; i < layout.length; i++)
    if (layout[i] === id) return i
  return -1
}

// Move the tile at `from` so it ends up at `to`; out-of-range indices clamp.
function move(layout, from, to) {
  var list = sanitize(layout)
  if (from < 0 || from >= list.length) return list
  var target = Math.max(0, Math.min(list.length - 1, to))
  var item = list.splice(from, 1)[0]
  list.splice(target, 0, item)
  return list
}

// Append (or insert at `at`) a known tile that isn't shown yet.
function add(layout, id, at) {
  var list = sanitize(layout)
  if (!known(id) || indexOf(list, id) >= 0) return list
  var index = (typeof at === "number" && at >= 0 && at <= list.length) ? at : list.length
  list.splice(index, 0, id)
  return list
}

function remove(layout, id) {
  return sanitize(layout).filter(function(item) { return item !== id })
}

function sameLayout(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false
  for (var i = 0; i < a.length; i++)
    if (a[i] !== b[i]) return false
  return true
}

function isDefault(layout) {
  return sameLayout(sanitize(layout), DEFAULT_LAYOUT)
}

function quickRow(layout, count) {
  return sanitize(layout).slice(0, typeof count === "number" ? count : QUICK_COUNT)
}

// The expanded grid's pages; always at least one, so an empty layout still
// has a page to show the "no tiles" hint on.
function pages(layout, size) {
  var per = Math.max(1, size || PAGE_SIZE)
  var list = sanitize(layout)
  var out = []
  for (var i = 0; i < list.length; i += per) out.push(list.slice(i, i + per))
  if (out.length === 0) out.push([])
  return out
}

// The state probe (tile-state.sh) prints key=value lines; later lines win.
function parseProbe(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var eq = line.indexOf("=")
    if (eq <= 0) continue
    var key = line.slice(0, eq).trim()
    if (!/^[a-z_]+$/.test(key)) continue
    out[key] = line.slice(eq + 1).trim()
  }
  return out
}

// Status lines for the probed tiles, from parseProbe's object.
function powerStatus(profile) {
  if (profile === "power-saver") return "On"
  if (profile === "performance") return "Off · performance"
  if (profile === "balanced") return "Off"
  return "No power profiles"
}

// The Dictation tile's status from tile-state.sh's dictation key: voxtype
// missing, installed but its daemon not running, idle, recording, or
// transcribing what was recorded.
function dictationStatus(state) {
  if (state === "on") return "Listening"
  if (state === "busy") return "Transcribing…"
  if (state === "off") return "Off"
  if (state === "down") return "Not running"
  return "Not installed"
}

// The Reminder tile (TOUCH-PLAN 1.12) runs Omarchy's own omarchy-reminder.
// Minutes are whole and above zero, as Omarchy's flow checks them; 0 for
// anything else.
function validMinutes(text) {
  var s = String(text === undefined || text === null ? "" : text).trim()
  return /^[0-9]+$/.test(s) && Number(s) > 0 ? Number(s) : 0
}

// `omarchy-reminder <minutes> [message]`, or null for bad minutes. The
// message is plain text in argv, as Omarchy's binding sends it.
function reminderArgv(minutes, message) {
  var n = validMinutes(minutes)
  if (!n) return null
  var argv = ["omarchy-reminder", String(n)]
  var text = String(message === undefined || message === null ? "" : message).trim()
  if (text) argv.push(text)
  return argv
}

// What `omarchy-reminder show --json` lists: each pending reminder's
// label, the time it fires and what is left, in its order.
function parseReminders(text) {
  var data = null
  try { data = JSON.parse(String(text || "")) } catch (error) { return [] }
  if (!data || typeof data !== "object" || !Array.isArray(data.reminders)) return []
  return data.reminders.map(function(r) {
    r = r && typeof r === "object" ? r : {}
    return { label: String(r.label || ""), atTime: String(r.atTime || ""), remaining: String(r.remaining || "") }
  })
}

// The tile's status from tile-state.sh's reminders key: the count of
// pending timers, or none without omarchy-reminder.
function reminderStatus(probe) {
  if (probe === undefined || probe === "" || probe === "none") return "Not installed"
  var n = parseInt(probe, 10)
  if (!(n > 0)) return "None set"
  return n === 1 ? "1 set" : n + " set"
}

function themeName(name) {
  return String(name || "").split("-").filter(function(part) { return part.length > 0 })
    .map(function(part) { return part.charAt(0).toUpperCase() + part.slice(1) }).join(" ")
}

if (typeof module !== "undefined") {
  module.exports = {
    VERSION: VERSION,
    CATALOG: CATALOG,
    DEFAULT_LAYOUT: DEFAULT_LAYOUT,
    QUICK_COUNT: QUICK_COUNT,
    PAGE_SIZE: PAGE_SIZE,
    known: known,
    label: label,
    defaults: defaults,
    sanitize: sanitize,
    parseConfig: parseConfig,
    parseList: parseList,
    serialize: serialize,
    available: available,
    indexOf: indexOf,
    move: move,
    add: add,
    remove: remove,
    sameLayout: sameLayout,
    isDefault: isDefault,
    quickRow: quickRow,
    pages: pages,
    parseProbe: parseProbe,
    powerStatus: powerStatus,
    dictationStatus: dictationStatus,
    validMinutes: validMinutes,
    reminderArgv: reminderArgv,
    parseReminders: parseReminders,
    reminderStatus: reminderStatus,
    themeName: themeName
  }
}
