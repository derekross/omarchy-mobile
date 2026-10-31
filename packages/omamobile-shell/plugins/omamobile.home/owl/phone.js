.pragma library
.import "values.js" as V
// SPDX-License-Identifier: MIT
// How an OWL widget fits this phone (docs/WIDGET-INTEROP-PLAN.md §3, §4):
// the palette from Omarchy's theme, the card's own colours, dp and the size
// conversion between Omalauncher's 6-column grid and ours, the tile
// variables, the capabilities derived from the compiler's commands list,
// the risk flags, and the limits the phone puts on sources. Pure JS.

// ---------------------------------------------------------------- palette

// colors.toml lines like `accent = "#7aa2f7"` -> { accent: ARGB }.
function parseColorsToml(text) {
  var out = {}
  String(text || "").split("\n").forEach(function(line) {
    var m = /^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?)\b/.exec(line)
    if (m) out[m[1]] = V.parseHex(m[2])
  })
  return out
}

// Every theme name OWL knows, from what an Omarchy theme defines. Names a
// theme doesn't carry are derived (SPEC-NOTES N20): the terminal colours
// stand in for the named hues, and the rest are mixes of background,
// foreground and the hues.
function palette(named) {
  function first() {
    for (var i = 0; i < arguments.length; i++) if (named[arguments[i]] !== undefined) return named[arguments[i]]
    return null
  }
  function or(v, fallback) { return v === null ? fallback : v }
  var p = {}
  p.background = or(first("background", "color0"), V.parseHex("#101315"))
  p.foreground = or(first("foreground", "color7"), V.parseHex("#cacccc"))
  p.accent = or(first("accent", "blue", "color4"), p.foreground)
  p.muted = or(first("muted", "color8", "dark_foreground"), p.foreground)
  var hues = ["red", "green", "yellow", "blue", "magenta", "cyan"]
  hues.forEach(function(h, i) { p[h] = first(h, "color" + (i + 1)) })
  hues.forEach(function(h, i) { p["bright_" + h] = first("bright_" + h, "color" + (i + 9), h, "color" + (i + 1)) })
  hues.forEach(function(h) { if (p[h] === null) p[h] = p.foreground })
  hues.forEach(function(h) { if (p["bright_" + h] === null) p["bright_" + h] = p[h] })
  p.orange = or(first("orange"), V.mixArgb(p.red, p.yellow, 0.5))
  p.brown = or(first("brown"), V.mixArgb(p.orange, p.background, 0.5))
  p.purple = or(first("purple", "magenta"), p.magenta)
  p.bright_foreground = first("bright_foreground", "color15", "light_foreground", "foreground")
  p.dark_foreground = or(first("dark_foreground"), V.mixArgb(p.foreground, p.background, 0.4))
  p.lighter_background = or(first("lighter_background"), V.mixArgb(p.background, p.foreground, 0.08))
  p.dark_background = or(first("dark_background"), V.mixArgb(p.background, 0xFF000000, 0.25))
  p.selection = or(first("selection", "selection_background"), V.mixArgb(p.background, p.accent, 0.3))
  p.cursor = or(first("cursor"), p.bright_foreground)
  p.surface = p.lighter_background
  p.border = or(first("border"), V.mixArgb(p.background, p.foreground, 0.2))
  p.white = or(first("white"), p.bright_foreground)
  p.black = or(first("black"), p.dark_background)
  var terminal = ["background", "red", "green", "yellow", "blue", "magenta", "cyan", "foreground",
    "muted", "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan", "bright_foreground"]
  for (var c = 0; c < 16; c++) p["color" + c] = or(first("color" + c), p[terminal[c]])
  return p
}

// On our card, the names that must read come from the shell (plan §4.1):
// the card's text colours, its background, Omarchy's accent and urgent.
// `shell` holds ARGB values: foreground, dimForeground, background, border,
// accent, urgent.
function cardPalette(base, shell) {
  var p = {}
  Object.keys(base).forEach(function(k) { p[k] = base[k] })
  if (!shell) return p
  if (shell.foreground !== undefined) p.foreground = shell.foreground
  if (shell.dimForeground !== undefined) p.muted = shell.dimForeground
  if (shell.background !== undefined) {
    p.background = shell.background
    p.surface = V.mixArgb(shell.background, p.foreground, 0.08)
  }
  if (shell.border !== undefined) p.border = shell.border
  if (shell.accent !== undefined) p.accent = shell.accent
  if (shell.urgent !== undefined && base.red === undefined) p.red = shell.urgent
  return p
}

// ---------------------------------------------------------------- size

var OWL_COLUMNS = 6
var OWL_CELL_DP = 69

// One OWL dp in logical pixels: the phone's width split into Omalauncher's
// 6 columns of 69 dp, whatever our own grid is (plan §4.3).
function dpFor(gridWidth) { return gridWidth / OWL_COLUMNS / OWL_CELL_DP }

// An OWL size (columns x rows of Omalauncher's grid) in our cells.
// `cellHeight` and `dp` are in logical pixels.
function cellsFor(owlSize, grid, cellHeight, dp, roundUp) {
  var pitch = OWL_CELL_DP * dp
  var r = roundUp ? Math.ceil : Math.round
  var w = r(owlSize[0] * grid.columns / OWL_COLUMNS - (roundUp ? 1e-9 : 0))
  var h = r(owlSize[1] * pitch / cellHeight - (roundUp ? 1e-9 : 0))
  return [Math.max(1, Math.min(grid.columns, w)), Math.max(1, Math.min(grid.rows, h))]
}

// A home-screen spec (HomeModel's REGISTRY shape) for a compiled widget.
function homeSpec(program, grid, cellHeight, dp) {
  var size = program.size || [3, 2]
  var want = cellsFor(size, grid, cellHeight, dp, false)
  var least = cellsFor(program.minSize || [1, 1], grid, cellHeight, dp, true)
  least = [Math.min(least[0], want[0]), Math.min(least[1], want[1])]
  return { size: want, min: least, max: [grid.columns, grid.rows] }
}

// The tile variables a widget reads (in dp), for a card of cardW x cardH
// logical pixels. `corners` from the shell's corner radius (plan §4.2).
function tileVars(cardW, cardH, dp, screenW, screenH, cornerRadius) {
  var pitch = OWL_CELL_DP * dp
  return {
    cols: Math.max(1, Math.round(cardW / pitch)),
    rows: Math.max(1, Math.round(cardH / pitch)),
    tileWidth: cardW / dp,
    tileHeight: cardH / dp,
    screenWidth: screenW / dp,
    screenHeight: screenH / dp,
    corners: cornersFor(cornerRadius),
    linux: true
  }
}

function cornersFor(radius) {
  var r = Number(radius) || 0
  return r <= 0 ? 0 : r <= 6 ? 0.5 : 1
}

// ---------------------------------------------------------------- capabilities

var ROOT_TOOLS = /(^|[\s;&|()`$])(sudo|pkexec|doas|run0|su)(\s|$)/
var NETWORK_TOOLS = /(^|[\s;&|()`$])(curl|wget|xh|http|aria2c|nc|ssh|scp|rsync)(\s|$)/
var RISKS = [
  { id: "pipe-to-shell", re: /(curl|wget)[^|]*\|\s*(ba|z|da)?sh\b/, says: "downloads something and runs it as a script" },
  { id: "rm-rf", re: /\brm\s+-[a-zA-Z]*r[a-zA-Z]*f|\brm\s+-[a-zA-Z]*f[a-zA-Z]*r/, says: "deletes files recursively (rm -rf)" },
  { id: "base64", re: /base64\s+(-d|--decode)/, says: "decodes hidden text (base64 -d)" },
  { id: "eval", re: /(^|[\s;&|(])eval\s/, says: "runs text as code (eval)" },
  { id: "disk", re: /(^|[\s;&|(])(dd|mkfs[.\w]*|shred|wipefs)\s/, says: "writes to disks (dd, mkfs, shred)" },
  // Installing software: never without the user (sudo itself is refused).
  { id: "installs", re: /(^|[\s;&|(`$])(pacman|yay|paru|pikaur|trizen|aura|makepkg|flatpak|pip3?|npm|cargo)\s+([^\n;&|]*\s)?(-S|-U|install\b|-i\b|--install)/, says: "installs software (pacman, yay, paru and the like)", high: true },
  { id: "secrets", re: /\.ssh\b|\.gnupg\b|\btokens?\b|\bsecret|password|\.netrc|keyring/i, says: "reads keys, tokens or passwords" }
]

function hostOf(url) {
  var m = /^https?:\/\/([a-z0-9.-]+)(?=[\/?#:]|$)/i.exec(url)
  return m ? m[1].toLowerCase() : ""
}

// What a widget may do, derived from the compiler's commands list and its
// requires (plan §3.1): { commands, network, hosts, files, notifications,
// risks, refusals }. Every list keeps the compiler's order.
function capabilities(program) {
  var out = { commands: [], network: false, hosts: [], files: [], notifications: false, risks: [], refusals: [], devices: [], terminal: false }
  var builtFrom = false
  var httpIndex = 0
  function risk(id, says, line) {
    if (!out.risks.some(function(r) { return r.id === id && r.line === line })) out.risks.push({ id: id, says: says, line: line })
  }
  ;(program.commands || []).forEach(function(line) {
    var text = line.replace(/^if Linux is installed: /, "")
    if (text.indexOf("http GET ") === 0) {
      out.network = true
      // A URL built while it runs still has a fixed host when its text
      // starts with one (https://wttr.in/${q}): the compiler keeps that prefix.
      var known = text.slice(9).indexOf("(a URL built") === 0 ? (program.httpPrefixes || [])[httpIndex] || "" : text.slice(9)
      httpIndex++
      var h = hostOf(known)
      if (h && out.hosts.indexOf(h) < 0) out.hosts.push(h)
      if (!h) risk("built", "reaches a web address built while it runs", line)
      return
    }
    if (text.indexOf("read file ") === 0) {
      out.files.push(text.slice(10))
      if (/\(a path built/.test(text)) risk("built", "reads a file whose path is built while it runs", line)
      return
    }
    if (text.indexOf("read Android notifications") === 0) {
      out.notifications = true
      risk("notifications", "reads your notifications", line)
      return
    }
    out.commands.push(line)
    if (/built from widget values$/.test(text)) { builtFrom = true; risk("built", "runs a command built while it runs", line) }
    if (ROOT_TOOLS.test(text)) out.refusals.push("runs a root tool: " + text.split("\n")[0].slice(0, 80))
    if (NETWORK_TOOLS.test(text)) {
      out.network = true
      var urls = text.match(/https?:\/\/[^\s'"`)]+/g) || []
      urls.forEach(function(u) { var h2 = hostOf(u); if (h2 && out.hosts.indexOf(h2) < 0) out.hosts.push(h2) })
    }
    RISKS.forEach(function(r) { if (r.re.test(text)) risk(r.id, r.says, line) })
  })
  var req = program.requires && program.requires.pacman ? program.requires.pacman : []
  if (req.indexOf("curl") >= 0 || req.indexOf("wget") >= 0) out.network = true
  // Things it can do to the phone itself, asked for on the approval sheet.
  out.devices = (program.actions || []).filter(function(a) { return DEVICE_ACTIONS.hasOwnProperty(a) })
  out.terminal = !!program.terminal
  return out
}

var DEVICE_ACTIONS = { haptic: "vibrates the phone", torch: "switches the torch" }

// The capability words the home screen and approval sheet use.
function capabilityList(caps) {
  var list = []
  if (caps.commands.length) list.push("commands")
  if (caps.network) list.push("network")
  if (caps.files.length) list.push("files")
  if (caps.notifications) list.push("notifications")
  ;(caps.devices || []).forEach(function(d) { list.push(d) })
  return list
}

// An approval holds for one exact list of commands, URLs and files: a widget
// whose list changes asks again, one that changes only its layout doesn't.
function approvalMatches(record, program) {
  if (!record || !Array.isArray(record.commands)) return false
  var now = program.commands || []
  if (record.commands.length !== now.length) return false
  for (var i = 0; i < now.length; i++) if (record.commands[i] !== now[i]) return false
  // Vibration and the torch are asked for too: a widget that starts using
  // one asks again.
  var devices = Array.isArray(record.devices) ? record.devices : []
  return (program.actions || []).every(function(a) { return !DEVICE_ACTIONS.hasOwnProperty(a) || devices.indexOf(a) >= 0 })
}

// ---------------------------------------------------------------- host calls

var TORCH = "white:torch"

// The argv a phone action runs (never through a shell unless shown), or
// null when the action isn't a plain command. The torch is the quick
// settings tile's LED (leds-lm3644), the haptic a feedbackd event, so the
// user's feedback profile (silent, quiet) applies.
function actionArgv(name, args) {
  var a = args || []
  function s(i) { return a[i] === undefined || a[i] === null ? "" : String(a[i]) }
  switch (name) {
  case "haptic": return ["fbcli", "-E", "button-pressed"]
  case "torch": {
    var v = a[0]
    if (v === true || s(0) === "on" || s(0) === "true") return ["brightnessctl", "--device=" + TORCH, "--quiet", "set", "100%"]
    if (v === false || s(0) === "off" || s(0) === "false") return ["brightnessctl", "--device=" + TORCH, "--quiet", "set", "0"]
    return ["sh", "-c", "if [ \"$(brightnessctl --device=" + TORCH + " get)\" -gt 0 ]; then brightnessctl --device=" + TORCH + " --quiet set 0; " +
            "else brightnessctl --device=" + TORCH + " --quiet set 100%; fi"]
  }
  case "notify": return ["notify-send", s(0), s(1)]
  case "copy": return ["wl-copy", "--", s(0)]
  case "media": return ["playerctl", s(0) === "toggle" ? "play-pause" : s(0) === "open" ? "play" : s(0)]
  case "volume": {
    var w = s(0), sink = "@DEFAULT_AUDIO_SINK@"
    if (w === "up") return ["wpctl", "set-volume", sink, "5%+"]
    if (w === "down") return ["wpctl", "set-volume", sink, "5%-"]
    if (w === "mute") return ["wpctl", "set-mute", sink, "1"]
    if (w === "unmute") return ["wpctl", "set-mute", sink, "0"]
    if (w === "toggle") return ["wpctl", "set-mute", sink, "toggle"]
    return ["wpctl", "set-volume", sink, Math.max(0, Math.min(100, Number(w) || 0)) + "%"]
  }
  }
  return null
}

// ---------------------------------------------------------------- android.*, from Linux

// `wpctl get-volume` -> { level, muted, steps }
function volumeFrom(text) {
  var m = /Volume:\s*([0-9.]+)/.exec(String(text || ""))
  if (!m) return null
  return { level: Math.round(parseFloat(m[1]) * 100), muted: /\[MUTED\]/.test(text), steps: 20 }
}

// `playerctl metadata --format ...` lines -> android.media's shape.
var MEDIA_FORMAT = "{{status}}\n{{title}}\n{{artist}}\n{{album}}\n{{playerName}}\n{{position}}\n{{mpris:length}}\n{{mpris:artUrl}}"
function mediaFrom(text) {
  var l = String(text || "").split("\n")
  if (l.length < 7 || !l[0]) return { available: true, playing: false, title: null, artist: null, album: null, app: null, package: null, position: null, duration: null, art: null }
  var us = function(v) { var n = parseInt(v, 10); return isFinite(n) ? Math.round(n / 1e6) : null }
  var art = l[7] || ""
  return { available: true, playing: l[0] === "Playing", title: l[1] || null, artist: l[2] || null, album: l[3] || null,
           app: l[4] || null, package: l[4] || null, position: us(l[5]), duration: us(l[6]),
           art: art.indexOf("file://") === 0 ? art.slice(7) : null }
}

// "<torch brightness>\n<mako modes>" -> android.modes' shape.
function modesFrom(text) {
  var l = String(text || "").split("\n")
  var torch = parseInt(l[0], 10)
  return { dnd: /do-not-disturb/.test(l.slice(1).join(" ")), saver: false, ringer: "normal", torch: isFinite(torch) ? torch > 0 : null }
}

// `df -B1 --output=size,used /`'s last line -> android.system's storage.
function storageFrom(df) {
  var n = String(df || "").trim().split(/\s+/).map(function(v) { return parseInt(v, 10) })
  if (n.length < 2 || !isFinite(n[0]) || !isFinite(n[1]) || n[0] <= 0) return null
  return { total: n[0], used: n[1], available: n[0] - n[1] }
}

// The first power supply of type Battery: "<capacity>\n<status>" -> android.battery.
var BATTERY_COMMAND = "for d in /sys/class/power_supply/*; do [ \"$(cat \"$d/type\" 2>/dev/null)\" = Battery ] && { cat \"$d/capacity\" \"$d/status\" 2>/dev/null; break; }; done"
function batteryFrom(text) {
  var lines = String(text || "").trim().split("\n")
  var level = parseInt(lines[0], 10)
  var status = String(lines[1] || "").trim()
  return { level: isFinite(level) ? level : null, charging: /Charging|Full/.test(status), status: status.toLowerCase() || null,
           temp: null, voltage: null, health: null, plugged: null, technology: null, cycles: null }
}

// The board from the device tree: "model" and the "compatible" list, read by
// DEVICE_COMMAND as "<model>\n@@\n<compatible, one per line>".
var DEVICE_COMMAND = "tr -d '\\0' < /proc/device-tree/model 2>/dev/null; echo; echo '@@'; tr '\\0' '\\n' < /proc/device-tree/compatible 2>/dev/null"
// What the device tree doesn't say, for the boards Omarchy Mobile runs on:
// the panel's size, density and top refresh rate (what it can do, not the
// rate it runs at now).
var BOARDS = {
  cheetah: { model: "Pixel 7 Pro", soc: "gs201", display: { width: 1440, height: 3120, hz: 120, dpi: 512 } },
  tegu: { model: "Pixel 9a", soc: "zumapro", display: { width: 1080, height: 2424, hz: 120, dpi: 422 } }
}
// "google,gs201-cheetah" or "google,zumapro-tegu" -> codename and SoC.
function boardFrom(text) {
  var parts = String(text || "").split("@@\n")
  var model = String(parts[0] || "").trim()
  var compat = String(parts[1] || "").split("\n").map(function(c) { return c.trim() }).filter(function(c) { return c })
  var m = /^[^,]+,([^-]+)-(.+)$/.exec(compat[0] || "")
  var codename = m ? m[2] : null
  var known = (codename && BOARDS[codename]) || {}
  return { model: known.model || model.replace(/^Google\s+/, "") || null, maker: /^Google\b/.test(model) || /^google,/.test(compat[0] || "") ? "Google" : null,
           codename: codename, soc: known.soc || (m ? m[1] : null), display: known.display || null }
}

// /proc/meminfo, /proc/uptime, uname and df (and the board) -> android.system.
function systemFrom(meminfo, uptime, kernel, df, board) {
  var b = board || {}
  var kb = function(name) { var m = new RegExp("^" + name + ":\\s+(\\d+)", "m").exec(meminfo || ""); return m ? parseInt(m[1], 10) * 1024 : null }
  var total = kb("MemTotal"), available = kb("MemAvailable")
  return { kernel: String(kernel || "").trim() || null, uptime: Math.floor(parseFloat(uptime) || 0),
           memory: { total: total, used: total !== null && available !== null ? total - available : null, available: available },
           storage: storageFrom(df), cpu: { soc: b.soc || null, maker: b.maker || null, hardware: null, cores: 8, abi: "arm64-v8a", maxMhz: null },
           display: b.display || null, build: null, codename: b.codename || null, patch: null,
           locale: null, timezone: null, launcher: "omamobile", theme: null, apps: 0 }
}

// The panel is off when its backlight's bl_power isn't 0, as omamobile-keys reads it.
function panelOff(blPower) {
  var t = String(blPower === undefined || blPower === null ? "" : blPower).trim()
  return t !== "" && t !== "0"
}

// ---------------------------------------------------------------- the clock

// The shared clock's rates (plan §2.6). An animation (a node or a Canvas
// that reads `time`) gets 20 fps while nobody touches it and 30 fps while a
// finger is on its widget and for 3 s after; never every vsync of the
// 120 Hz panel. A widget whose frame (its JS, the layout and the Canvas
// paint it causes) takes longer than the budget draws every other frame.
// While the home screen is hidden only `at` triggers run, on a 10 s tick.
var CLOCK = { idleMs: 50, touchMs: 33, touchHoldMs: 3000, budgetMs: 20, tickMs: 1000, hiddenTickMs: 10000 }

function frameInterval(touched) { return touched ? CLOCK.touchMs : CLOCK.idleMs }
function frameSlow(costMs) { return Number(costMs) > CLOCK.budgetMs }
function frameSkipped(slow, frameCount) { return !!slow && frameCount % 2 === 1 }
// Milliseconds to the next tick: just past the next whole second while the
// home screen shows, the next 10 s boundary while it doesn't.
function tickDelay(nowMs, hidden) {
  var period = hidden ? CLOCK.hiddenTickMs : CLOCK.tickMs
  return period - nowMs % period + 5
}

// ---------------------------------------------------------------- limits

// The phone's limits on a source (plan §3.3): returns the interval and
// timeout to use, in seconds.
var LIMITS = { cmdEvery: 2, timeoutMax: 30, httpEvery: 60, streams: 2, actionGap: 1, triggersPerSecond: 10,
               cmdOutput: 65536, bodyBytes: 1048576 }

function sourceLimits(spec, fastNetwork) {
  var every = spec.every
  if (spec.kind === "cmd") every = Math.max(every, LIMITS.cmdEvery)
  if (spec.kind === "http") every = Math.max(every, fastNetwork ? 5 : LIMITS.httpEvery)
  var timeout = Math.max(1, Math.min(LIMITS.timeoutMax, spec.timeout || 10))
  return { every: every, timeout: timeout }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseColorsToml: parseColorsToml, palette: palette, cardPalette: cardPalette,
    dpFor: dpFor, cellsFor: cellsFor, homeSpec: homeSpec, tileVars: tileVars, cornersFor: cornersFor,
    capabilities: capabilities, capabilityList: capabilityList, approvalMatches: approvalMatches,
    sourceLimits: sourceLimits, LIMITS: LIMITS, hostOf: hostOf, OWL_CELL_DP: OWL_CELL_DP,
    actionArgv: actionArgv, volumeFrom: volumeFrom, mediaFrom: mediaFrom, MEDIA_FORMAT: MEDIA_FORMAT,
    modesFrom: modesFrom, systemFrom: systemFrom, storageFrom: storageFrom,
    batteryFrom: batteryFrom, BATTERY_COMMAND: BATTERY_COMMAND, panelOff: panelOff, DEVICE_ACTIONS: DEVICE_ACTIONS,
    boardFrom: boardFrom, DEVICE_COMMAND: DEVICE_COMMAND, BOARDS: BOARDS,
    CLOCK: CLOCK, frameInterval: frameInterval, frameSlow: frameSlow, frameSkipped: frameSkipped, tickDelay: tickDelay
  }
}
