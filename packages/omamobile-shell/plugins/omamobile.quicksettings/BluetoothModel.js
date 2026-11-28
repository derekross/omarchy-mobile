// SPDX-License-Identifier: MIT
// Pure helpers for the Bluetooth panel (BluetoothPanel.qml): device rows,
// sorting, icons, the pairing agent's prompts and error text. Rows are plain
// snapshots, never live BluetoothDevice wrappers (BlueZ churn can destroy
// those under a delegate). Node runs these in test/bluetooth-model.js through
// the module.exports below.

// ---------------------------------------------------------------- icons

var GLYPHS = {
  headphones: "󰋋",
  speaker: "󰓃",
  keyboard: "󰌌",
  mouse: "󰍽",
  gamepad: "󰊗",
  phone: "󰄜",
  computer: "󰌢",
  watch: "󰖉",
  generic: "󰂯"
}

// Bluetooth LE appearance: category is the top 10 bits.
function kindFromAppearance(appearance) {
  var value = Number(appearance)
  if (!isFinite(value) || value <= 0) return ""
  var category = value >> 6
  var sub = value & 0x3f
  if (category === 1) return "phone"
  if (category === 2) return "computer"
  if (category === 3) return "watch"
  if (category === 15) {
    if (sub === 1) return "keyboard"
    if (sub === 2) return "mouse"
    if (sub === 3 || sub === 4) return "gamepad"
    return ""
  }
  if (category === 33) return "speaker"      // audio sink
  if (category === 37) return "headphones"   // wearable audio: earbuds, headsets
  return ""
}

// Classic Class of Device: major class in bits 8-12, minor above bit 2.
function kindFromClass(cls) {
  var value = Number(cls)
  if (!isFinite(value) || value <= 0) return ""
  var major = (value >> 8) & 0x1f
  var minor = (value >> 2) & 0x3f
  if (major === 1) return "computer"
  if (major === 2) return "phone"
  if (major === 4) {
    if (minor === 1 || minor === 2 || minor === 6) return "headphones"
    return "speaker"
  }
  if (major === 5) {
    var peripheral = (value >> 6) & 0x3
    var kind = minor & 0x0f
    if (kind === 1 || kind === 2) return "gamepad"
    if (peripheral === 1 || peripheral === 3) return "keyboard"
    if (peripheral === 2) return "mouse"
    return ""
  }
  if (major === 7 && minor === 1) return "watch"
  return ""
}

// BlueZ's freedesktop icon name, the fallback when neither number is known.
function kindFromIcon(icon) {
  var name = String(icon || "")
  if (/headset|headphone|earbud/.test(name)) return "headphones"
  if (/^audio|speaker|multimedia-player/.test(name)) return "speaker"
  if (/keyboard/.test(name)) return "keyboard"
  if (/mouse|tablet/.test(name)) return "mouse"
  if (/gaming|joystick/.test(name)) return "gamepad"
  if (/phone/.test(name)) return "phone"
  if (/computer|laptop/.test(name)) return "computer"
  if (/watch/.test(name)) return "watch"
  return ""
}

function deviceKind(icon, appearance, cls) {
  return kindFromAppearance(appearance) || kindFromClass(cls) || kindFromIcon(icon) || "generic"
}

function kindGlyph(kind) {
  return GLYPHS[kind] || GLYPHS.generic
}

// ---------------------------------------------------------------- rows

function isAddressLike(value) {
  return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(String(value || "").trim())
}

// A row from a BluetoothDevice-shaped object plus what the agent helper
// reads off D-Bus (rssi, appearance, class). BlueZ's Alias (`name`) is the
// Name, or what a rename set, or the address with dashes when the device
// never sent a name; the address form doesn't count as a name.
function deviceLabel(device) {
  var alias = String(device.name || "").trim()
  if (alias && !isAddressLike(alias)) return alias
  var name = String(device.deviceName || "").trim()
  if (name && !isAddressLike(name)) return name
  return ""
}

function deviceRow(device, extra) {
  if (!device || !device.address) return null
  var more = extra || {}
  var label = deviceLabel(device)
  var rssi = Number(more.rssi)
  return {
    address: String(device.address),
    label: label || String(device.address),
    named: label !== "",
    connected: !!device.connected,
    paired: !!(device.paired || device.bonded),
    trusted: !!device.trusted,
    pairing: !!device.pairing,
    battery: device.batteryAvailable ? Math.max(0, Math.min(100, Math.round(Number(device.battery) * 100))) : -1,
    rssi: more.rssi === null || more.rssi === undefined || !isFinite(rssi) ? -999 : rssi,
    deviceType: deviceKind(device.icon, more.appearance, more["class"])
  }
}

function byLabel(a, b) {
  var x = a.label.toLowerCase(), y = b.label.toLowerCase()
  return x < y ? -1 : x > y ? 1 : 0
}

// Strongest first; unknown signal (-999) last; then by name.
function byRssi(a, b) {
  if (b.rssi !== a.rssi) return b.rssi - a.rssi
  return byLabel(a, b)
}

// rows -> { paired, available, unnamed }. Paired: connected first, then by
// name. Available: named devices by signal. Unnamed: address-only, by signal.
function buildLists(rows) {
  var paired = [], available = [], unnamed = []
  var list = rows || []
  for (var i = 0; i < list.length; i++) {
    var row = list[i]
    if (!row) continue
    if (row.paired || row.connected) paired.push(row)
    else if (row.named) available.push(row)
    else unnamed.push(row)
  }
  paired.sort(function(a, b) {
    if (a.connected !== b.connected) return a.connected ? -1 : 1
    return byLabel(a, b)
  })
  available.sort(byRssi)
  unnamed.sort(byRssi)
  return { paired: paired, available: available, unnamed: unnamed }
}

function entry(kind, fields) {
  var e = { kind: kind, text: "", address: "", label: "", named: false, connected: false, paired: false,
            trusted: false, pairing: false, battery: -1, rssi: -999, deviceType: "generic" }
  for (var key in fields) e[key] = fields[key]
  return e
}

// The panel's one flat list. Every entry has every field.
function listEntries(lists, showUnnamed, enabled) {
  var entries = []
  if (!enabled) return entries
  var value = lists || { paired: [], available: [], unnamed: [] }
  if (value.paired.length > 0) {
    entries.push(entry("header", { text: "Paired devices" }))
    for (var i = 0; i < value.paired.length; i++) entries.push(entry("device", value.paired[i]))
  }
  entries.push(entry("header", { text: "Available devices" }))
  for (var j = 0; j < value.available.length; j++) entries.push(entry("device", value.available[j]))
  if (value.available.length === 0 && (value.unnamed.length === 0 || !showUnnamed))
    entries.push(entry("empty", { text: "Searching for devices…" }))
  if (value.unnamed.length > 0) {
    entries.push(entry("more", { text: (showUnnamed ? "Hide " : "Show ") + value.unnamed.length + " unnamed device" + (value.unnamed.length === 1 ? "" : "s") }))
    if (showUnnamed)
      for (var k = 0; k < value.unnamed.length; k++) entries.push(entry("device", value.unnamed[k]))
  }
  return entries
}

function batteryText(percent) {
  return percent >= 0 ? percent + "%" : ""
}

// What a tap does: connected opens the actions sheet, paired connects,
// anything else pairs.
function tapAction(row) {
  if (!row) return ""
  if (row.connected) return "actions"
  if (row.paired) return "connect"
  return "pair"
}

// Long-press actions for a row, in sheet order.
function longPressActions(row) {
  if (!row || !(row.paired || row.connected)) return []
  return [row.connected ? "disconnect" : "connect", "rename", "forget"]
}

function rowStatus(row, busyKind, failure) {
  if (!row) return ""
  if (failure) return failure
  if (busyKind === "pair" || row.pairing) return "Pairing…"
  if (busyKind === "connect") return "Connecting…"
  if (busyKind === "disconnect") return "Disconnecting…"
  if (busyKind === "forget") return "Forgetting…"
  var battery = batteryText(row.battery)
  if (row.connected) return battery ? "Connected · " + battery : "Connected"
  if (row.paired) return battery ? "Paired · " + battery : "Paired"
  return row.named ? "" : "No name"
}

function visibilityText(seconds) {
  var value = Math.max(0, Math.floor(Number(seconds) || 0))
  var minutes = Math.floor(value / 60)
  var rest = value % 60
  return "Visible for " + minutes + ":" + (rest < 10 ? "0" : "") + rest
}

// ---------------------------------------------------------------- pairing window

// Whether the adapter should accept pairing (BlueZ's Pairable) right now, for
// a panel that owns that setting (it was off when the panel opened): only
// while the owner pairs a device from the panel, or while the phone is
// visible and the helper's agent is there to show the confirmation sheets.
// Never while the panel is closed. Without the helper, visibility alone
// doesn't turn pairing on: nothing could answer a device pairing to us.
function pairableWanted(state) {
  if (!state || !state.opened) return false
  if (state.pairing) return true
  return !!(state.visible && state.helper)
}

// ---------------------------------------------------------------- errors

// BlueZ error name and message (from the agent helper) -> what to show.
function errorMessage(op, name, message) {
  var error = String(name || "")
  var text = String(message || "")
  if (/AuthenticationCanceled/.test(error)) return "Pairing canceled"
  if (/AuthenticationRejected|Rejected$/.test(error)) return "Pairing rejected"
  if (/AuthenticationFailed/.test(error)) return "Pairing failed. Check the code"
  if (/AuthenticationTimeout/.test(error)) return "Pairing timed out"
  if (/page-timeout|Page Timeout|Host is down|DoesNotExist|UnknownObject/i.test(error + " " + text)) return "Device out of range"
  if (/refused/i.test(text)) return "Connection refused"
  if (/profile-unavailable/i.test(text)) return "Paired. Nothing to connect to"
  if (/NotReady|not powered/i.test(error + " " + text)) return "Bluetooth is off"
  if (/InProgress/.test(error)) return "Already in progress"
  if (/NoReply|Timeout/i.test(error)) return op === "pair" ? "Pairing timed out" : "Connection timed out"
  if (/ConnectionAttemptFailed/.test(error)) return "Couldn't connect. Is it in range?"
  if (op === "disconnect") return "Couldn't disconnect"
  return op === "pair" ? "Pairing failed" : "Couldn't connect"
}

// Errors that mean the operation is already done.
function isHarmless(name) {
  return /AlreadyExists|AlreadyConnected|NotConnected/.test(String(name || ""))
}

// ---------------------------------------------------------------- agent

// One JSON line from omamobile-bt-agent, or null.
function parseHelperLine(line) {
  var text = String(line || "").trim()
  if (!text || text[0] !== "{") return null
  try {
    var value = JSON.parse(text)
    return value && typeof value.event === "string" ? value : null
  } catch (error) {
    return null
  }
}

function padPasskey(value) {
  var text = String(Math.max(0, Math.floor(Number(value) || 0)))
  while (text.length < 6) text = "0" + text
  return text
}

// An agent request -> the sheet that answers it. `input` is "" (buttons
// only), "pin" (text) or "passkey" (digits); `display` is a code to show.
function requestSheet(request) {
  var r = request || {}
  switch (r.type) {
  case "confirm":
    return { title: "Pair with " + (r.label || r.address) + "?", body: "Make sure this code shows on both devices.",
             display: padPasskey(r.passkey), input: "", accept: "Pair", answer: true }
  case "authorize":
    return { title: "Pair with " + (r.label || r.address) + "?", body: "It's asking to pair with this phone.",
             display: "", input: "", accept: "Pair", answer: true }
  case "display-passkey":
    return { title: "Pairing with " + (r.label || r.address), body: "Type this code on the keyboard, then press Enter.",
             display: padPasskey(r.passkey), entered: Number(r.entered) || 0, input: "", accept: "", answer: false }
  case "display-pin":
    return { title: "Pairing with " + (r.label || r.address), body: "Enter this PIN on the device.",
             display: String(r.pin || ""), input: "", accept: "", answer: false }
  case "pin":
    return { title: "Pair with " + (r.label || r.address), body: "Enter the device's PIN (often 0000 or 1234).",
             display: "", input: "pin", accept: "Pair", answer: true }
  case "passkey":
    return { title: "Pair with " + (r.label || r.address), body: "Enter the 6-digit passkey shown on the device.",
             display: "", input: "passkey", accept: "Pair", answer: true }
  }
  return null
}

// Whether a typed value can answer a request.
function validInput(type, value) {
  var text = String(value || "")
  if (type === "pin") return text.length >= 1 && text.length <= 16
  if (type === "passkey") return /^[0-9]{1,6}$/.test(text)
  return true
}

// The line sent back to the helper for a request.
function replyCommand(request, accept, value) {
  var reply = { cmd: "reply", id: request ? request.id : -1, accept: !!accept }
  if (accept && request && (request.type === "pin" || request.type === "passkey")) reply.value = String(value || "")
  return JSON.stringify(reply)
}

// The pairing flow as a small state machine over helper events and user
// actions. State: { phase, address, request }. Phases: "idle", "pairing"
// (Pair sent), "prompt" (a sheet is up), "done", "failed".
function pairingStep(state, event) {
  var s = state || { phase: "idle", address: "", request: null, error: "" }
  var e = event || {}
  var next = { phase: s.phase, address: s.address, request: s.request, error: "" }
  if (e.event === "start") return { phase: "pairing", address: e.address, request: null, error: "" }
  if (e.event === "request") {
    // A request for another device (someone pairing to us) still prompts.
    next.phase = "prompt"
    next.request = e
    if (!next.address) next.address = e.address
    return next
  }
  if (e.event === "answered") {
    next.request = s.request && s.request.type && /^display/.test(s.request.type) ? s.request : null
    next.phase = next.request ? "prompt" : "pairing"
    if (!e.accept) return { phase: "failed", address: s.address, request: null, error: "Pairing canceled" }
    return next
  }
  if (e.event === "cancel") {
    return s.phase === "idle" ? s : { phase: "failed", address: s.address, request: null, error: "Pairing canceled" }
  }
  if (e.event === "result" && e.address === s.address) {
    if (e.ok || isHarmless(e.error)) return { phase: "done", address: e.address, request: null, error: "" }
    return { phase: "failed", address: e.address, request: null, error: errorMessage(e.op, e.error, e.message) }
  }
  if (e.event === "reset") return { phase: "idle", address: "", request: null, error: "" }
  return s
}

if (typeof module !== "undefined") {
  module.exports = {
    kindFromAppearance: kindFromAppearance,
    kindFromClass: kindFromClass,
    kindFromIcon: kindFromIcon,
    deviceKind: deviceKind,
    kindGlyph: kindGlyph,
    isAddressLike: isAddressLike,
    deviceLabel: deviceLabel,
    deviceRow: deviceRow,
    buildLists: buildLists,
    listEntries: listEntries,
    batteryText: batteryText,
    tapAction: tapAction,
    longPressActions: longPressActions,
    rowStatus: rowStatus,
    visibilityText: visibilityText,
    pairableWanted: pairableWanted,
    errorMessage: errorMessage,
    isHarmless: isHarmless,
    parseHelperLine: parseHelperLine,
    padPasskey: padPasskey,
    requestSheet: requestSheet,
    validInput: validInput,
    replyCommand: replyCommand,
    pairingStep: pairingStep
  }
}
