// SPDX-License-Identifier: MIT
// The voice bar's pure parts: the Voxtype commands the shell runs, what the
// daemon's state file means for the bar, where the words go (the
// destination) and how they get there, the clock, the level meter and the
// settings. No QML here, so test/voice-model.js runs it under Node through
// the module.exports below.
//
// One recording mode for everything: Voxtype writes the transcript to a
// file (--file), and the shell delivers it to the destination chosen in the
// bar, so the destination can change while the user speaks. Every recording
// passes --no-osd: Voxtype's own GTK overlay anchors bottom-centre, over the
// bottom bar, and the bar draws its own.

var VOXTYPE = "voxtype"
// Voxtype stops a recording itself at max_duration_secs (Omarchy's config:
// 60); the bar counts down to it.
var MAX_SECONDS = 60
// The model is the daemon's ([whisper] model): Voxtype ignores a
// per-recording --model it hasn't prepared ("not in available models").
// Since 0.2.63 that is Omarchy's base.en, with omamobile-setup-user cutting
// Whisper's context to the clip: 12 s of speech in about 2.2 s on the Pixel
// 7 Pro (tiny.en 1.0 s). The live preview runs tiny.en on its own
// (omamobile-voice-preview).
// The transcript, in the runtime directory (tmpfs, the user's own, gone at
// logout).
var TRANSCRIPT_NAME = "omamobile-voice.txt"
// A hold shorter than this (from the moment listening began) is a press,
// not push-to-talk: listening goes on until Done.
var HOLD_MS = 700
// Bars in the level meter.
var LEVEL_BARS = 24

// The argv that starts a recording: the old transcript removed first (a
// recording that writes nothing can't hand back the last one), then
// Voxtype writing the new one to filePath. One process: sh with the path
// and the argv as arguments, nothing interpolated.
function startArgv(filePath) {
  var path = String(filePath || "")
  return ["sh", "-c", 'rm -f -- "$1"; shift; exec "$@"', "sh", path,
          VOXTYPE, "record", "start", "--no-osd", "--file=" + path]
}

var STOP_ARGV = [VOXTYPE, "record", "stop"]
var CANCEL_ARGV = [VOXTYPE, "record", "cancel"]

function transcriptPath(runtimeDir) {
  return String(runtimeDir || "/tmp") + "/" + TRANSCRIPT_NAME
}

// The daemon's state file: idle, recording, streaming or transcribing.
// Anything else (missing, empty) is idle.
function voxState(text) {
  var s = String(text || "").trim().split(/\s+/)[0]
  if (s === "recording" || s === "streaming" || s === "transcribing") return s
  return "idle"
}

// What the bar shows, from where it was and the daemon's new state.
//
// phase: idle | starting | listening | transcribing | result | error
// mine: the bar started this recording (one it didn't start, say from a
//   desktop hotkey, shows nothing and delivers nothing)
//
// Returns { phase, read }: read is true when the bar's recording has ended
// and its transcript is to be read now.
//
// delivered: the words have gone where the chip said, and the bar shows them
// for a moment (DELIVERED_MS) in the preview's place before it closes.
function step(phase, mine, vox) {
  var stays = phase === "result" || phase === "error" || phase === "delivered"
  if (!mine) return { phase: stays ? phase : "idle", read: false }
  if (vox === "recording" || vox === "streaming") return { phase: "listening", read: false }
  if (vox === "transcribing") return { phase: "transcribing", read: false }
  // Idle. The result, the error and the delivered words stay until the user
  // (or the delivered timer) leaves them, and a start that hasn't reached
  // the daemon yet stays starting.
  if (stays || phase === "starting" || phase === "idle") return { phase: phase, read: false }
  return { phase: "transcribing", read: true }
}

// How long the delivered words stay in the bar before it closes.
var DELIVERED_MS = 900

// Voxtype's transcript, tidied: one paragraph, no surrounding space.
function cleanTranscript(text) {
  return String(text || "").replace(/\s+/g, " ").trim()
}

var NOTHING_HEARD = "Didn't catch that. Try again, a little closer to the phone."

// Push-to-talk: does letting go stop the recording? Not when the finger
// let go within HOLD_MS of listening starting (a press: it keeps
// listening), and not when the recording is no longer running.
function releaseStops(phase, heldMs) {
  if (phase !== "listening" && phase !== "starting") return false
  return Number(heldMs) >= HOLD_MS
}

// ---------------------------------------------------------------- destinations

// The agent terminals Omarchy starts (omarchy-agent: omarchy-launch-tui
// --app-id=org.omarchy.agent, one class for every agent).
var AGENT_APP_ID = "org.omarchy.agent"

function isAgent(appId) {
  return String(appId || "") === AGENT_APP_ID
}

// Where the words go, from what is in front: an agent's terminal, Send to
// the agent (typed into its prompt, then Enter); any other app, Type here
// (into the focused field); the home screen, Ask the agent (a new prompt,
// checked first).
function contextDestination(appOnScreen, agentInFront) {
  if (appOnScreen && agentInFront) return "agent"
  if (appOnScreen) return "type"
  return "ask"
}

// The choices the destination chip offers: the context's own, then the
// two that work anywhere.
function destinations(appOnScreen, agentInFront) {
  var list
  if (appOnScreen && agentInFront) list = ["agent", "type"]
  else if (appOnScreen) list = ["type"]
  else list = ["ask"]
  return list.concat(["copy", "search"])
}

function agentLabel(agentName) {
  return agentName || "your agent"
}

// The chip's words, the list's second column, and the primary button's verb.
function destinationLabel(dest, agentName) {
  switch (dest) {
  case "type": return "Type here"
  case "agent": return "Send to " + agentLabel(agentName)
  case "ask": return "Ask " + agentLabel(agentName)
  case "copy": return "Copy to clipboard"
  case "search": return "Search apps"
  default: return ""
  }
}

function destinationNote(dest) {
  switch (dest) {
  case "type": return "into the focused field"
  case "agent": return "prompt, then Enter"
  case "ask": return "new prompt"
  case "copy": return "paste anywhere"
  case "search": return "launcher"
  default: return ""
  }
}

function doneVerb(dest) {
  switch (dest) {
  case "type": return "type it"
  case "agent": return "send"
  case "ask": return "ask"
  case "copy": return "copy"
  case "search": return "search"
  default: return "done"
  }
}

// The line under the meter, for the one destination that acts on its own.
function destinationHint(dest) {
  return dest === "agent" ? "Types what you say into the prompt and presses Enter." : ""
}

// How the transcript is delivered once it is text: an argv to run, or
// "result" for the check step (a new prompt for the agent) unless the
// user turned the check off ("send", which runs the launcher's prompt).
// The text goes on stdin or as one argv element, never into a shell
// string. Typing needs no wait: the bar never takes the keyboard focus, so
// the app still has it.
function deliveryArgv(dest, text) {
  var t = String(text || "")
  switch (dest) {
  case "type": return ["sh", "-c", 'printf %s "$1" | exec wtype -', "sh", t]
  case "agent": return ["sh", "-c", 'printf %s "$1" | wtype - && exec wtype -k Return', "sh", t]
  case "copy": return ["sh", "-c", 'printf %s "$1" | exec wl-copy', "sh", t]
  case "search": return ["omarchy-shell", "shell", "summon", "omamobile.launcher", JSON.stringify({ query: t })]
  default: return null
  }
}

// After the transcript is read: the next phase and what to run. ask goes
// to the result step (or straight to the agent with the check off), the
// rest deliver at once; the bar shows the final words for a moment in the
// preview's place (delivered), then closes.
function afterRead(dest, text, confirmAsk) {
  var t = cleanTranscript(text)
  if (!t) return { phase: "error", text: "", error: NOTHING_HEARD, argv: null, send: false }
  if (dest === "ask") {
    if (confirmAsk === false) return { phase: "delivered", text: t, error: "", argv: null, send: true }
    return { phase: "result", text: t, error: "", argv: null, send: false }
  }
  return { phase: "delivered", text: t, error: "", argv: deliveryArgv(dest, t), send: false }
}

// ---------------------------------------------------------------- live preview

// omamobile-voice-preview: a second capture of the microphone, transcribed
// in chunks with tiny.en while Voxtype records (Voxtype 1.1.1 has no way to
// hand its own partial text to the shell). One JSON line per pass.
var PREVIEW_ARGV = ["omamobile-voice-preview"]

// One line of the preview: { text } for a pass, { status } when it can't
// run (no-model, no-voxtype, no-audio), else null.
function parsePartial(line) {
  var o = null
  try { o = JSON.parse(String(line || "")) } catch (e) { return null }
  if (!o || typeof o !== "object") return null
  if (typeof o.text === "string") return { text: cleanTranscript(o.text) }
  if (typeof o.status === "string") return { status: o.status }
  return null
}

// The end of a long preview: the bar has room for two lines, and the newest
// words matter. Cut at a word, with an ellipsis in front.
function partialTail(text, maxChars) {
  var t = cleanTranscript(text)
  var max = Math.max(8, Number(maxChars) || 90)
  if (t.length <= max) return t
  var tail = t.slice(t.length - max)
  var space = tail.indexOf(" ")
  if (space >= 0 && space < tail.length - 1) tail = tail.slice(space + 1)
  return "…" + tail
}

// Does the preview run? While the bar's own recording listens, with the
// setting on.
function previewRuns(phase, mine, livePreview) {
  return !!mine && phase === "listening" && livePreview !== false
}

// The bar's text line between the meter and the buttons: the preview while
// listening and transcribing (muted), the delivered words for their moment
// (final); nothing otherwise (the check before Ask has its own editable
// text).
function liveLine(phase, partial, finalText) {
  if (phase === "delivered") return { text: cleanTranscript(finalText), final: true }
  if (phase === "starting" || phase === "listening" || phase === "transcribing")
    return { text: cleanTranscript(partial), final: false }
  return { text: "", final: false }
}

// The result step's warning: Omarchy starts every agent unattended (Claude
// Code with --permission-mode auto, and the like), so a misheard prompt is
// acted on without another question.
function permissionText(agentName) {
  return (agentName || "Your agent") + " runs with full permissions on this phone. Check the words before it starts."
}

// ---------------------------------------------------------------- the bar's words

// "0:07", "1:00".
function clock(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var m = Math.floor(s / 60)
  var r = s % 60
  return m + ":" + (r < 10 ? "0" : "") + r
}

// The time at the top right: elapsed, and the cap once it is near.
function elapsedText(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  if (s >= MAX_SECONDS - 10) return clock(Math.min(s, MAX_SECONDS)) + " · stops at " + clock(MAX_SECONDS)
  return clock(s)
}

// The word beside the meter.
function statusText(phase) {
  switch (phase) {
  case "starting": return "starting"
  case "listening": return "listening"
  case "transcribing": return "turning it into text"
  default: return ""
  }
}

// The model's short name for the result's time line ("0:06 · tiny").
function modelShort(id) {
  return String(id || "").replace(/\.en$/, "")
}

// The level meter: the last LEVEL_BARS loudness values (0..1), oldest
// first, as a new array (QML sees a change only on reassignment). rms from
// voxtype-audio-bridge is small for speech (0.02-0.3): a square root
// spreads it over the bar's height.
function pushLevel(levels, rms) {
  var next = (levels || []).slice()
  var v = Math.sqrt(Math.max(0, Math.min(1, Number(rms) || 0)))
  next.push(Math.min(1, v * 1.6))
  while (next.length > LEVEL_BARS) next.shift()
  return next
}

// The meter's LEVEL_BARS bars from the levels so far, newest at the right:
// { value, lit }; the bars with no level yet are flat and unlit.
function meterBars(levels, active) {
  var l = levels || []
  var offset = LEVEL_BARS - l.length
  var bars = []
  for (var i = 0; i < LEVEL_BARS; i++) {
    var has = i >= offset
    bars.push({ value: has ? Math.max(0, Math.min(1, Number(l[i - offset]) || 0)) : 0, lit: has && !!active })
  }
  return bars
}

// One NDJSON line of voxtype-audio-bridge: {"peak","rms","vad","ts_ms"}, or
// {"status": ...}. Returns the frame or null.
function parseLevel(line) {
  try {
    var o = JSON.parse(String(line || ""))
    if (o && typeof o.rms === "number") return { rms: o.rms, peak: Number(o.peak) || 0, vad: !!o.vad }
  } catch (e) { }
  return null
}

// The theme's warning colour (the result step): colors.toml's `yellow`,
// else its `color3`, else "" (the caller falls back to the accent).
function themeWarning(colorsToml) {
  var text = String(colorsToml || "")
  var keys = ["yellow", "color3"]
  for (var i = 0; i < keys.length; i++) {
    var m = text.match(new RegExp("^\\s*" + keys[i] + "\\s*=\\s*[\"']?(#[0-9a-fA-F]{6,8})", "m"))
    if (m) return m[1]
  }
  return ""
}

// ---------------------------------------------------------------- settings

// The voice settings, in ~/.config/omamobile/voice.json (as
// quicksettings.json and home.json): Power + Volume Up (off until the user
// turns it on), the check before a new prompt goes to the agent, and the
// live preview (0.2.63, on; a file without the key gets the default). Keys
// from earlier versions (holdPill, micKey, agentMic, agentSubmit,
// sayToSend) are dropped on the next write.
var SETTINGS_VERSION = 3
var DEFAULT_SETTINGS = {
  version: SETTINGS_VERSION,
  powerVolumeUp: false,
  confirmSend: true,
  livePreview: true
}
var SETTING_KEYS = ["powerVolumeUp", "confirmSend", "livePreview"]

function defaultSettings() {
  var out = {}
  for (var k in DEFAULT_SETTINGS) out[k] = DEFAULT_SETTINGS[k]
  return out
}

// Whatever is in the file, over the defaults: only known keys, only
// booleans; anything unreadable is the defaults.
function parseSettings(text) {
  var out = defaultSettings()
  var o = null
  try { o = JSON.parse(String(text || "")) } catch (e) { o = null }
  if (!o || typeof o !== "object") return out
  for (var i = 0; i < SETTING_KEYS.length; i++) {
    var k = SETTING_KEYS[i]
    if (typeof o[k] === "boolean") out[k] = o[k]
  }
  return out
}

function withSetting(settings, key, value) {
  var out = parseSettings(JSON.stringify(settings || {}))
  if (SETTING_KEYS.indexOf(key) >= 0) out[key] = !!value
  return out
}

function serializeSettings(settings) {
  return JSON.stringify(parseSettings(JSON.stringify(settings || {})), null, 2) + "\n"
}

// ---------------------------------------------------------------- models

// The speech models the settings offer (Whisper's English ones), with
// their download sizes.
var MODELS = [
  { id: "tiny.en", name: "Fast", detail: "tiny", size: "75 MB", note: "quickest, rougher" },
  { id: "base.en", name: "Balanced", detail: "base", size: "142 MB", note: "the default" },
  { id: "small.en", name: "Accurate", detail: "small", size: "466 MB", note: "slower" }
]

function modelFile(id) {
  return "ggml-" + String(id) + ".bin"
}

// The daemon's model from the user's voxtype config.toml: [whisper]'s
// `model = "..."`, or Omarchy's default.
function configModel(text) {
  var lines = String(text || "").split("\n")
  var section = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    var sec = line.match(/^\[([^\]]+)\]$/)
    if (sec) { section = sec[1].trim(); continue }
    if (section !== "whisper") continue
    var m = line.match(/^model\s*=\s*"([^"]*)"/)
    if (m) return m[1]
  }
  return "base.en"
}

// The model files present in Voxtype's models directory (one name a line).
function installedModels(listing) {
  var out = []
  String(listing || "").split("\n").forEach(function(name) {
    var m = name.trim().match(/^ggml-(.+)\.bin$/)
    if (m) out.push(m[1])
  })
  return out
}

// Each model's row: chosen, downloaded, and its line under the name.
function modelRows(current, installed) {
  var have = installed || []
  return MODELS.map(function(m) {
    var downloaded = have.indexOf(m.id) >= 0
    return {
      id: m.id, name: m.name, chosen: m.id === current, downloaded: downloaded, size: m.size,
      line: m.detail + " · " + m.size + " · " + (downloaded ? m.note : "download")
    }
  })
}

// Voxtype's own download (non-interactive, NDJSON progress), then the
// switch: Voxtype's config setter and a restart of its daemon.
function downloadArgv(id) {
  return [VOXTYPE, "setup", "--download", "--model", String(id), "--no-post-install", "--progress-format", "json"]
}

function switchArgv(id) {
  return ["sh", "-c", 'voxtype config set whisper.model "$1" && exec systemctl --user try-restart voxtype.service', "sh", String(id)]
}

// One progress line of the download: a percentage when it can tell, else
// the megabytes so far; null for anything else.
function parseProgress(line) {
  var o = null
  try { o = JSON.parse(String(line || "")) } catch (e) { return null }
  if (!o || typeof o !== "object") return null
  var pct = typeof o.percent === "number" ? o.percent : typeof o.progress === "number" ? (o.progress <= 1 ? o.progress * 100 : o.progress) : NaN
  var done = Number(o.downloaded !== undefined ? o.downloaded : o.bytes !== undefined ? o.bytes : o.current)
  var total = Number(o.total !== undefined ? o.total : o.total_bytes !== undefined ? o.total_bytes : o.size)
  if (isNaN(pct) && done > 0 && total > 0) pct = done / total * 100
  if (!isNaN(pct)) return { percent: Math.max(0, Math.min(100, Math.round(pct))), text: Math.round(Math.max(0, Math.min(100, pct))) + "%" }
  if (done > 0) return { percent: -1, text: Math.round(done / 1048576) + " MB" }
  return null
}

// ---------------------------------------------------------------- feel

// A short tick at the start and the end of listening: a feedbackd event, so
// the user's feedback profile (silent, quiet) decides; nothing without fbcli.
var HAPTIC_ARGV = ["sh", "-c", "command -v fbcli >/dev/null 2>&1 && exec fbcli -E button-pressed"]

// Does this phase change tick? Listening starting, and listening ending.
function ticks(was, now) {
  return (now === "listening") !== (was === "listening")
}

if (typeof module !== "undefined") {
  module.exports = {
    VOXTYPE: VOXTYPE, MAX_SECONDS: MAX_SECONDS, TRANSCRIPT_NAME: TRANSCRIPT_NAME, HOLD_MS: HOLD_MS,
    LEVEL_BARS: LEVEL_BARS, STOP_ARGV: STOP_ARGV, CANCEL_ARGV: CANCEL_ARGV, NOTHING_HEARD: NOTHING_HEARD,
    startArgv: startArgv, transcriptPath: transcriptPath, voxState: voxState, step: step,
    cleanTranscript: cleanTranscript, releaseStops: releaseStops,
    AGENT_APP_ID: AGENT_APP_ID, isAgent: isAgent, contextDestination: contextDestination,
    destinations: destinations, destinationLabel: destinationLabel, destinationNote: destinationNote,
    doneVerb: doneVerb, destinationHint: destinationHint, deliveryArgv: deliveryArgv, afterRead: afterRead,
    permissionText: permissionText, clock: clock, elapsedText: elapsedText, statusText: statusText,
    modelShort: modelShort, pushLevel: pushLevel, meterBars: meterBars, parseLevel: parseLevel,
    themeWarning: themeWarning, SETTINGS_VERSION: SETTINGS_VERSION, DEFAULT_SETTINGS: DEFAULT_SETTINGS,
    SETTING_KEYS: SETTING_KEYS, defaultSettings: defaultSettings, parseSettings: parseSettings,
    withSetting: withSetting, serializeSettings: serializeSettings, MODELS: MODELS, modelFile: modelFile,
    configModel: configModel, installedModels: installedModels, modelRows: modelRows,
    downloadArgv: downloadArgv, switchArgv: switchArgv, parseProgress: parseProgress,
    HAPTIC_ARGV: HAPTIC_ARGV, ticks: ticks, DELIVERED_MS: DELIVERED_MS, PREVIEW_ARGV: PREVIEW_ARGV,
    parsePartial: parsePartial, partialTail: partialTail, previewRuns: previewRuns, liveLine: liveLine
  }
}
