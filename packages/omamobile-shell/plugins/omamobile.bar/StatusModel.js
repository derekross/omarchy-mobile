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

// ------------------------------------------------------------ camera cutout
// The front camera's hole in the panel: a zone of the bar no item may reach,
// `center` as a fraction of the bar's width and `width` in logical px.
// Every phone Omarchy Mobile supports has its hole centred at the top. The
// Pixel 9a's stock cutout is a circle 83 panel px across centred at x 540 of
// 1080 (Android's cutoutSpec "m 581.5,86 a 41.5,41.5 ..."), and Android keeps
// a box 112 px wide clear for it (its boundingRect 484-596): 37.3 logical px
// at the monitor scale of 3, 42 at 8/3, where the hole itself is 27.7 and
// 31.1. 40 keeps that box at scale 3 and 4 px either side of the hole at 8/3;
// the Pixel 7 Pro's and 8 Pro's holes are smaller on wider panels.
var CUTOUT_DEFAULT = { center: 0.5, width: 40 }

// One cutout description over another: false for none, an object with
// either key (the other from `fallback`), anything else leaves `fallback`.
// A width of 0 is none too.
function readCutout(value, fallback) {
  if (value === false) return null
  if (!value || typeof value !== "object" || Array.isArray(value)) return fallback
  var base = fallback || CUTOUT_DEFAULT
  var c = numberIn(value.center, 0, 1, base.center)
  var w = numberIn(value.width, 0, Infinity, base.width)
  return w > 0 ? { center: c, width: w } : null
}

function numberIn(value, low, high, fallback) {
  if (value === undefined || value === null || value === "" || typeof value === "boolean") return fallback
  var n = Number(value)
  return isFinite(n) && n >= low && n <= high ? n : fallback
}

// The cutout the bar keeps clear: shell.json's bar.cutout, over the device
// package's /usr/share/omamobile/bar-cutout.json (the same keys), over the
// default. null for none.
function cutout(config, deviceText) {
  var device = CUTOUT_DEFAULT
  var text = String(deviceText === undefined || deviceText === null ? "" : deviceText).trim()
  if (text !== "") {
    try { device = readCutout(JSON.parse(text), CUTOUT_DEFAULT) } catch (e) { device = CUTOUT_DEFAULT }
  }
  var c = config && typeof config === "object" ? config.cutout : undefined
  return readCutout(c, device)
}

// The zone in the bar's own x, or null. Upright (or upside down: the bar
// can't tell the two apart, and keeping the middle clear there costs only
// room) the hole is in the bar; on its side it is at a short edge, halfway
// down, and the bar has the whole width. A screen of no known size yet
// keeps the zone.
function cutoutZone(spec, barWidth, screenWidth, screenHeight) {
  var w = Number(barWidth)
  if (!spec || !(w > 0)) return null
  if (Number(screenHeight) > 0 && Number(screenWidth) > Number(screenHeight)) return null
  var middle = spec.center * w
  return { left: middle - spec.width / 2, right: middle + spec.width / 2 }
}

// What the bar sheds, first to last, when a side doesn't fit beside the
// cutout. Right: the words first, as the glyph beside each says the same
// (the bars, the battery's fill); then Bluetooth, which changes nothing the
// owner would miss, before do-not-disturb, which silences calls and
// messages; then Wi-Fi before the signal, the one that says whether a call
// can reach the phone. The battery always stays. Left: the unread count
// before the call in progress (the shade has the count; the chip is the way
// back to the call); the clock always stays.
var RIGHT_SHED = ["cellText", "batteryText", "bluetooth", "dnd", "wifi", "cell"]
var LEFT_SHED = ["unread", "call"]

// A row's width with the items in `hidden` taken out. Each item is
// { id, w, attach }: w 0 is not there, and an attached item is part of the
// one before it (the words beside a glyph, their own gap in w), so it adds
// no spacing and goes with it.
function rowWidth(items, hidden, spacing) {
  var total = 0
  var count = 0
  var baseShown = false
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    var shown = item.w > 0 && !hidden[item.id]
    if (item.attach) {
      if (shown && baseShown) total += item.w
      continue
    }
    baseShown = shown
    if (!shown) continue
    total += item.w
    count++
  }
  return total + Math.max(0, count - 1) * (Number(spacing) || 0)
}

// Sheds items in `order` until the row fits `room`. { show: { id: bool },
// width, fits }; what isn't in `order` stays, fit or not.
function fitRow(items, room, spacing, order) {
  var list = items || []
  var hidden = {}
  var width = rowWidth(list, hidden, spacing)
  for (var i = 0; i < order.length && width > room; i++) {
    hidden[order[i]] = true
    width = rowWidth(list, hidden, spacing)
  }
  var show = {}
  var baseShown = false
  for (var j = 0; j < list.length; j++) {
    var shown = list[j].w > 0 && !hidden[list[j].id]
    if (list[j].attach) shown = shown && baseShown
    else baseShown = shown
    show[list[j].id] = shown
  }
  return { show: show, width: width, fits: width <= room }
}

// The bar's two groups: the left (clock, call chip, unread count) from the
// left margin, the right (the status row) up to the right margin, each kept
// off the cutout zone (bar x) and off each other. Without a zone over the
// content the right row keeps room for what it never sheds, and the left
// group fits in the rest. { show, left, right, leftRoom, rightRoom, fits, zone }.
function fitBar(o) {
  var width = Number(o.width) || 0
  var margin = Number(o.margin) || 0
  var gap = Number(o.groupGap) || 0
  var inner = Math.max(0, width - 2 * margin)
  var zone = o.zone && o.zone.right > margin && o.zone.left < width - margin ? o.zone : null
  var leftRoom, rightRoom, left, right
  if (zone) {
    leftRoom = Math.max(0, zone.left - margin)
    rightRoom = Math.max(0, width - margin - zone.right)
    left = fitRow(o.left, leftRoom, o.leftSpacing, LEFT_SHED)
    right = fitRow(o.right, rightRoom, o.rightSpacing, RIGHT_SHED)
  } else {
    var keep = {}
    for (var i = 0; i < RIGHT_SHED.length; i++) keep[RIGHT_SHED[i]] = true
    leftRoom = Math.max(0, inner - gap - rowWidth(o.right || [], keep, o.rightSpacing))
    left = fitRow(o.left, leftRoom, o.leftSpacing, LEFT_SHED)
    rightRoom = Math.max(0, inner - gap - left.width)
    right = fitRow(o.right, rightRoom, o.rightSpacing, RIGHT_SHED)
  }
  var show = {}
  for (var a in left.show) show[a] = left.show[a]
  for (var b in right.show) show[b] = right.show[b]
  return { show: show, left: left.width, right: right.width, leftRoom: leftRoom, rightRoom: rightRoom,
           fits: left.fits && right.fits, zone: zone }
}

if (typeof module !== "undefined") {
  module.exports = {
    findDevice: findDevice, connectedNetwork: connectedNetwork, wifiIcon: wifiIcon, networkIcon: networkIcon,
    cellularIcon: cellularIcon, cellGlyph: cellGlyph, cellText: cellText, parseCell: parseCell,
    callChip: callChip, elapsed: elapsed, batteryIcon: batteryIcon,
    batteryStyle: batteryStyle, iconShown: iconShown, boltGlyph: boltGlyph, batteryLow: batteryLow,
    CUTOUT_DEFAULT: CUTOUT_DEFAULT, RIGHT_SHED: RIGHT_SHED, LEFT_SHED: LEFT_SHED,
    readCutout: readCutout, cutout: cutout, cutoutZone: cutoutZone, rowWidth: rowWidth, fitRow: fitRow, fitBar: fitBar,
    BATTERY_STYLES: BATTERY_STYLES, STATUS_ICONS: STATUS_ICONS,
    stampOf: stampOf, parseStamp: parseStamp, unreadCount: unreadCount, unreadStored: unreadStored
  }
}
