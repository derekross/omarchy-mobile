// SPDX-License-Identifier: MIT
// Pure helpers for the phone launcher: settings merging and the rule that
// decides whether the bottom bar's text is an app search or a prompt for the
// coding agent.

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

// Manifest defaults, overlaid with the plugin's entry in shell.json
// (`plugins: [{ "id": "omamobile.launcher", "columns": 5, ... }]`).
// The drawer's columns (TOUCH-PLAN 2.4): the configured count across the
// screen's shorter side, and on a grid wider than that (the phone on its
// side) as many columns of the same width as fit, so the icons keep their
// size: 4 upright on the Pixel 7 Pro, 8 on its side. `margin` is the grid's
// inset from each screen edge.
function drawerColumns(columns, gridWidth, shortSide, margin) {
  var base = Math.max(3, Math.min(6, Math.round(Number(columns) || 4)))
  var portraitGrid = (Number(shortSide) || 0) - 2 * (Number(margin) || 0)
  if (!(gridWidth > portraitGrid) || portraitGrid <= 0) return base
  return Math.max(base, Math.floor(base * gridWidth / portraitGrid))
}

function mergedSettings(defaults, config, pluginId) {
  var out = {}
  var base = isPlainObject(defaults) ? defaults : {}
  for (var key in base) out[key] = base[key]
  var plugins = isPlainObject(config) && Array.isArray(config.plugins) ? config.plugins : []
  for (var i = 0; i < plugins.length; i++) {
    var entry = plugins[i]
    if (!isPlainObject(entry) || entry.id !== pluginId) continue
    for (var k in entry) if (k !== "id") out[k] = entry[k]
  }
  return out
}

function argv(value, fallback) {
  if (Array.isArray(value)) return value.map(function(part) { return String(part) })
  if (typeof value === "string" && value.trim()) return value.trim().split(/\s+/)
  return fallback.slice()
}

function wordCount(query) {
  var text = String(query || "").trim()
  return text ? text.split(/\s+/).length : 0
}

// A short query that names an app is a search. Text reads as a prompt once it
// has enough words to be a sentence, ends like one, or matches no app at all.
function looksLikePrompt(query, appMatches, sentenceWords) {
  var text = String(query || "").trim()
  if (!text) return false
  if (wordCount(text) >= Math.max(2, sentenceWords || 3)) return true
  if (/[?.!]$/.test(text)) return true
  return appMatches === 0
}

// Display names for the agents omarchy-default-agent knows, as Omarchy
// names them. Anything else shows its id.
var AGENT_NAMES = {
  pi: "Pi", omp: "Oh My Pi", opencode: "OpenCode", claude: "Claude Code",
  codex: "Codex", crush: "Crush", grok: "Grok", gemini: "Gemini",
  openclaw: "OpenClaw", hermes: "Hermes", copilot: "GitHub Copilot",
  muse: "Muse Code", "cursor-agent": "Cursor CLI"
}

// The agent id from ~/.config/omarchy/defaults/agent (first line), or "".
function agentId(fileText) {
  return String(fileText || "").split("\n")[0].trim()
}

function agentName(id) {
  return id ? (AGENT_NAMES[id] || id) : ""
}

// Every launch goes through omamobile-launch (bin/), which gives what it
// starts a new empty workspace of its own, or focuses an app that is already
// open there: one app per screen, as on Android.
var LAUNCH = "omamobile-launch"

function appArgv(desktopId) {
  return [LAUNCH, "app", String(desktopId || "")]
}

// Omarchy launches the user's chosen agent, in its own terminal, with the
// prompt as one argument. Without a chosen agent, open Omarchy's picker.
function promptArgv(prompt) {
  return [LAUNCH, "cmd", "--", "omarchy-agent-prompt", String(prompt || "").trim()]
}

var PICK_AGENT_ARGV = ["omarchy", "menu", "summon", "setup.default.agent"]

// ---------------------------------------------------------------- drawer gestures
//
// The drawer follows a finger both ways: up from anywhere on the home
// screen (omamobile.home drives it through DrawerLink.js) and down from the
// drawer itself or its handle. Its position is `progress`, 0 closed to 1
// open, a share of its own height, so the sheet's top stays under the
// finger whatever the window's size.

// A release this fast (logical px/s) decides by its direction alone.
var DRAWER_FLING = 350
// A slower release opens the drawer past a quarter of the way up, and
// closes an open one pulled down a tenth of the way (about 90-100 px on the
// phone, near the 80 px pull that closed it before).
var DRAWER_OPEN_AT = 0.25
var DRAWER_CLOSE_AT = 0.1

// Whether the drawer ends open: velocity in px/s along the screen's y axis
// (negative is up, toward open); fromOpen says which way the finger started.
function drawerEndsOpen(progress, velocity, fromOpen) {
  var v = Number(velocity) || 0
  if (v <= -DRAWER_FLING) return true
  if (v >= DRAWER_FLING) return false
  var p = Number(progress) || 0
  return fromOpen ? p > 1 - DRAWER_CLOSE_AT : p >= DRAWER_OPEN_AT
}

// How long a settle takes (ms) for `distance` px of a `span` px travel:
// 120 ms plus up to 140 ms with the distance (half the way, about 190 ms),
// and no slower than the finger was moving, so a fling carries on at its
// own speed (Easing.OutCubic starts at three times its average speed).
function settleMs(distance, span, speed) {
  var d = Math.abs(Number(distance) || 0)
  if (d < 0.5) return 0
  var byDistance = 120 + 140 * Math.min(1, d / Math.max(1, Number(span) || 1))
  var v = Math.abs(Number(speed) || 0)
  var bySpeed = v > 0 ? 3 * d / v * 1000 : Infinity
  return Math.round(Math.max(120, Math.min(byDistance, bySpeed)))
}

// A finger's speed from its recent positions: samples are { t (ms), pos
// (px) }, newest last. Only the last 100 ms count, so a finger that stopped
// before it let go has no speed (no fling), and one sample is no speed.
var SAMPLE_WINDOW_MS = 100
function addSample(samples, t, pos) {
  var out = []
  for (var i = 0; i < (samples || []).length; i++)
    if (t - samples[i].t <= SAMPLE_WINDOW_MS * 2) out.push(samples[i])
  out.push({ t: t, pos: pos })
  return out
}
function speedOf(samples, now) {
  var recent = []
  for (var i = 0; i < (samples || []).length; i++)
    if (now - samples[i].t <= SAMPLE_WINDOW_MS) recent.push(samples[i])
  if (recent.length < 2) return 0
  var a = recent[0], b = recent[recent.length - 1]
  var dt = b.t - a.t
  return dt >= 8 ? (b.pos - a.pos) / dt * 1000 : 0
}

if (typeof module !== "undefined") {
  module.exports = {
    drawerColumns: drawerColumns,
    mergedSettings: mergedSettings,
    argv: argv,
    wordCount: wordCount,
    looksLikePrompt: looksLikePrompt,
    agentId: agentId,
    agentName: agentName,
    LAUNCH: LAUNCH,
    appArgv: appArgv,
    promptArgv: promptArgv,
    PICK_AGENT_ARGV: PICK_AGENT_ARGV,
    DRAWER_FLING: DRAWER_FLING,
    DRAWER_OPEN_AT: DRAWER_OPEN_AT,
    DRAWER_CLOSE_AT: DRAWER_CLOSE_AT,
    drawerEndsOpen: drawerEndsOpen,
    settleMs: settleMs,
    addSample: addSample,
    speedOf: speedOf
  }
}
