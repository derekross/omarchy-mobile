// SPDX-License-Identifier: MIT
// Voice input's pure parts: the Voxtype commands the shell runs, what the
// daemon's state file means for the sheet and the listening strip, the
// clock and the level meter. No QML here, so test/voice-model.js runs it
// under Node through the module.exports below.
//
// Every recording the shell starts passes --no-osd: Voxtype's own GTK
// overlay anchors bottom-centre, over the dock and the home pill, and the
// shell draws its own (the sheet, the strip).

var VOXTYPE = "voxtype"
// Voxtype stops a recording itself at max_duration_secs (Omarchy's config:
// 60); the sheet and the strip count down to it.
var MAX_SECONDS = 60
// The model is the daemon's ([whisper] model): Voxtype ignores a
// per-recording --model it hasn't prepared ("not in available models"), so
// omamobile-setup-user switches the user's config to tiny.en once it is
// downloaded (3.9 s for 10 s of speech on the Pixel 7 Pro, base.en 8.8 s).
// The agent flow's transcript, in the runtime directory (tmpfs, the user's
// own, gone at logout).
var TRANSCRIPT_NAME = "omamobile-voice.txt"
// A hold shorter than this (from the moment listening began) is a press,
// not push-to-talk: listening goes on until Stop.
var HOLD_MS = 700
// Bars in the level meter.
var LEVEL_BARS = 24

// The argv that starts a recording. mode: "type" (Voxtype types into the
// focused window) or "file" (the transcript goes to filePath).
function startArgv(mode, filePath) {
  var argv = [VOXTYPE, "record", "start", "--no-osd"]
  if (mode === "file") argv.push("--file=" + String(filePath || ""))
  else argv.push("--type")
  return argv
}

// The agent flow removes the old transcript before it starts, so a
// recording that writes nothing can't hand back the last one. One process:
// sh with the path and the start argv as arguments, nothing interpolated.
function fileStartArgv(filePath) {
  return ["sh", "-c", 'rm -f -- "$1"; shift; exec "$@"', "sh", String(filePath || "")]
    .concat(startArgv("file", filePath))
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

// What the shell shows, from where it was and the daemon's new state.
//
// phase: idle | starting | listening | transcribing | review | error
// owner: "ask" (the agent sheet started it), "type" (the mic key or the
//   Dictation tile), or "" (a recording the shell didn't start)
//
// Returns { phase, owner, read }: read is true when the agent flow's
// recording has ended and its transcript is to be read now.
function step(phase, owner, vox) {
  var listening = vox === "recording" || vox === "streaming"
  if (listening) return { phase: "listening", owner: owner || "", read: false }
  if (vox === "transcribing") return { phase: "transcribing", owner: owner || "", read: false }
  // Idle. The review and error pages stay until the user leaves them, and
  // a start that hasn't reached the daemon yet stays starting.
  if (phase === "review" || phase === "error" || phase === "starting")
    return { phase: phase, owner: owner, read: false }
  if (owner === "ask" && (phase === "listening" || phase === "transcribing"))
    return { phase: "transcribing", owner: "ask", read: true }
  return { phase: "idle", owner: "", read: false }
}

// Voxtype's transcript, tidied: one paragraph, no surrounding space.
function cleanTranscript(text) {
  return String(text || "").replace(/\s+/g, " ").trim()
}

// What the agent flow does with what it read: the review page, or an error
// when nothing was heard.
function afterRead(text) {
  var t = cleanTranscript(text)
  if (t) return { phase: "review", text: t, error: "" }
  return { phase: "error", text: "", error: "Didn't catch that. Try again, a little closer to the phone." }
}

// Push-to-talk: does letting go stop the recording? Not when the finger
// let go within HOLD_MS of listening starting (a press: it keeps
// listening), and not when the recording is no longer running.
function releaseStops(phase, heldMs) {
  if (phase !== "listening" && phase !== "starting") return false
  return Number(heldMs) >= HOLD_MS
}

// "0:07", "1:00".
function clock(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var m = Math.floor(s / 60)
  var r = s % 60
  return m + ":" + (r < 10 ? "0" : "") + r
}

// The listening line's time: elapsed, and the cap once it is near.
function elapsedText(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  if (s >= MAX_SECONDS - 10) return clock(Math.min(s, MAX_SECONDS)) + " · stops at " + clock(MAX_SECONDS)
  return clock(s)
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

// The strip's and the sheet's words for each phase.
function statusText(phase, owner) {
  switch (phase) {
  case "starting": return "Starting"
  case "listening": return "Listening"
  case "transcribing": return owner === "type" ? "Typing" : "Transcribing"
  default: return ""
  }
}

// The hint under the listening sheet.
function askHint(phase, pushToTalk) {
  if (phase === "transcribing") return "Turning speech into text on this phone"
  if (pushToTalk) return "Let go of the pill to stop · transcribed on this phone"
  return "Tap Stop when you're done · transcribed on this phone"
}

// The auto-permissions line on the check-and-send page.
function permissionText(agentName) {
  var name = agentName || "Your agent"
  return name + " runs with auto permissions here, so it acts on this without asking again."
}

function sendLabel(agentName) {
  return agentName ? "Send to " + agentName : "Choose an agent"
}

// Copy and "Type into last app": the text goes on stdin, never into a
// shell string. Typing waits for the sheet to close and the app to have
// the keyboard focus again.
function copyArgv(text) {
  return ["sh", "-c", 'printf %s "$1" | exec wl-copy', "sh", String(text || "")]
}

function typeArgv(text) {
  return ["sh", "-c", 'sleep 0.5; printf %s "$1" | exec wtype -', "sh", String(text || "")]
}

if (typeof module !== "undefined") {
  module.exports = {
    VOXTYPE: VOXTYPE, MAX_SECONDS: MAX_SECONDS,
    TRANSCRIPT_NAME: TRANSCRIPT_NAME, HOLD_MS: HOLD_MS, LEVEL_BARS: LEVEL_BARS,
    STOP_ARGV: STOP_ARGV, CANCEL_ARGV: CANCEL_ARGV,
    startArgv: startArgv, fileStartArgv: fileStartArgv, transcriptPath: transcriptPath,
    voxState: voxState, step: step, cleanTranscript: cleanTranscript,
    afterRead: afterRead, releaseStops: releaseStops, clock: clock, elapsedText: elapsedText,
    pushLevel: pushLevel, meterBars: meterBars, parseLevel: parseLevel, statusText: statusText, askHint: askHint,
    permissionText: permissionText, sendLabel: sendLabel, copyArgv: copyArgv, typeArgv: typeArgv
  }
}
