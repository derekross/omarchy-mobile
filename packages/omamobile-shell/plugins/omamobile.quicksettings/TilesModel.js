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
//
// The user's own tiles (TILES.md, one file each in ~/.config/omamobile/tiles)
// are "user:<id>" in the layout. Any well-formed one is known, whether or not
// its file is there, so the layout keeps it before user-tiles.py has listed
// them and while its file is away; the sheet shows a missing one as
// unavailable.

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
  { id: "dictation", label: "Dictation" }
]

// The first four are the collapsed sheet's row, as on Android: the toggles
// reached for most. Clipboard and Dictation close the second page: Omarchy
// reaches them only by keyboard shortcut, so a tile is their touch path
// (TOUCH-PLAN 1.12), and appending them leaves the first page as it was.
var DEFAULT_LAYOUT = [
  "wifi", "bluetooth", "dnd", "torch",
  "mobile-data", "rotation-lock", "airplane", "location",
  "battery-saver", "dark-theme", "night-light", "nfc",
  "fingerprint", "keyboard", "clipboard", "dictation"
]

var QUICK_COUNT = 4
var PAGE_SIZE = 8

// Must match user-tiles.py's ID_RE.
var USER_PREFIX = "user:"
var USER_ID_RE = /^[a-z0-9-]+$/
// A user tile's icon when its file gives none (user-tiles.py's DEFAULT_ICON).
var USER_ICON = String.fromCodePoint(0xF0D2A)

function builtIn(id) {
  for (var i = 0; i < CATALOG.length; i++)
    if (CATALOG[i].id === id) return true
  return false
}

function isUser(id) {
  return typeof id === "string" && id.indexOf(USER_PREFIX) === 0 && USER_ID_RE.test(id.slice(USER_PREFIX.length))
}

// "user:<id>" for a bare user tile id or one that has its prefix; "" for
// anything else.
function userTileId(id) {
  var text = String(id === undefined || id === null ? "" : id)
  var full = text.indexOf(USER_PREFIX) === 0 ? text : USER_PREFIX + text
  return isUser(full) ? full : ""
}

function known(id) {
  return builtIn(id) || isUser(id)
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
  if (value === "" || !/^[a-z0-9:, -]*$/.test(value)) return null
  return sanitize(value.split(/[\s,]+/).filter(function(id) { return id.length > 0 }))
}

function serialize(layout) {
  return JSON.stringify({ version: VERSION, tiles: sanitize(layout) }, null, 2) + "\n"
}

// Catalog order, then the user's own tiles in the order given (bare ids or
// "user:" ones), minus what the layout already shows.
function available(layout, userIds) {
  var shown = {}
  var list = sanitize(layout)
  for (var i = 0; i < list.length; i++) shown[list[i]] = true
  var out = []
  for (var j = 0; j < CATALOG.length; j++)
    if (!shown[CATALOG[j].id]) out.push(CATALOG[j].id)
  var extra = Array.isArray(userIds) ? userIds : []
  for (var k = 0; k < extra.length; k++) {
    var id = userTileId(extra[k])
    if (id === "" || shown[id]) continue
    shown[id] = true
    out.push(id)
  }
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

// `user-tiles.py list` -> its tiles, each with every field in its type, so
// the sheet never meets a missing one: { id, label, icon, status, active,
// choices: [{ value, label }], hasChoices, hasAction, error }. Entries with
// a bad id are dropped; anything that isn't a list is no tiles.
function parseUserTiles(text) {
  var raw = null
  try { raw = JSON.parse(String(text || "")) } catch (error) { return [] }
  if (!Array.isArray(raw)) return []
  var out = []
  var seen = {}
  for (var i = 0; i < raw.length; i++) {
    var t = raw[i]
    if (!t || typeof t !== "object" || typeof t.id !== "string" || !USER_ID_RE.test(t.id) || seen[t.id]) continue
    seen[t.id] = true
    var choices = []
    var list = Array.isArray(t.choices) ? t.choices : []
    for (var j = 0; j < list.length; j++) {
      var c = list[j]
      if (!c || typeof c.value !== "string" || c.value === "") continue
      choices.push({ value: c.value, label: typeof c.label === "string" && c.label !== "" ? c.label : c.value })
    }
    out.push({
      id: t.id,
      label: typeof t.label === "string" && t.label !== "" ? t.label : t.id,
      icon: typeof t.icon === "string" && t.icon !== "" ? t.icon : USER_ICON,
      status: typeof t.status === "string" ? t.status : "",
      active: t.active === true,
      choices: choices,
      hasChoices: t.hasChoices === true,
      hasAction: t.hasAction === true,
      error: typeof t.error === "string" ? t.error : ""
    })
  }
  return out
}

function findUserTile(tiles, id) {
  var bare = userTileId(id).slice(USER_PREFIX.length)
  var list = Array.isArray(tiles) ? tiles : []
  for (var i = 0; i < list.length; i++)
    if (list[i].id === bare) return list[i]
  return null
}

// What a tap on a user tile does: "choose" (open its chooser), "run" (its
// action) or "" (a broken tile, or one that only shows a status).
function userTap(tile) {
  if (!tile || tile.error) return ""
  if (tile.hasChoices) return "choose"
  if (tile.hasAction) return "run"
  return ""
}

// The chooser marks the row whose value or label is the tile's status, so
// a status that shows the current choice marks it with no extra command.
function currentChoice(tile) {
  if (!tile || !tile.status) return ""
  for (var i = 0; i < tile.choices.length; i++) {
    var c = tile.choices[i]
    if (c.value === tile.status || c.label === tile.status) return c.value
  }
  return ""
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

function themeName(name) {
  return String(name || "").split("-").filter(function(part) { return part.length > 0 })
    .map(function(part) { return part.charAt(0).toUpperCase() + part.slice(1) }).join(" ")
}

// The Mobile data tile's icon: signal bars from tile-state.sh's data_signal
// (0-100 while registered, -1 or missing with no network), the same glyphs
// as the bar's StatusModel.cellularIcon, where 0 is the empty bars
// (registered, no reading yet). Crossed out only with no modem, mobile data
// off, or no network.
function dataSignal(value) {
  var text = String(value === undefined || value === null ? "" : value).trim()
  if (!/^-?[0-9]+$/.test(text)) return -1
  var n = parseInt(text, 10)
  return n < 0 ? -1 : Math.min(100, n)
}

function dataIcon(available, enabled, signal) {
  var strength = dataSignal(signal)
  if (!available || !enabled || strength < 0) return String.fromCodePoint(0xF0783)
  var bars = [0xF08BF, 0xF08BC, 0xF08BD, 0xF08BE]
  return String.fromCodePoint(bars[Math.max(0, Math.min(3, Math.floor(strength / 25.01)))])
}

if (typeof module !== "undefined") {
  module.exports = {
    VERSION: VERSION,
    CATALOG: CATALOG,
    DEFAULT_LAYOUT: DEFAULT_LAYOUT,
    QUICK_COUNT: QUICK_COUNT,
    PAGE_SIZE: PAGE_SIZE,
    USER_PREFIX: USER_PREFIX,
    USER_ID_RE: USER_ID_RE,
    USER_ICON: USER_ICON,
    builtIn: builtIn,
    isUser: isUser,
    userTileId: userTileId,
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
    parseUserTiles: parseUserTiles,
    findUserTile: findUserTile,
    userTap: userTap,
    currentChoice: currentChoice,
    parseProbe: parseProbe,
    powerStatus: powerStatus,
    dictationStatus: dictationStatus,
    themeName: themeName,
    dataSignal: dataSignal,
    dataIcon: dataIcon
  }
}
