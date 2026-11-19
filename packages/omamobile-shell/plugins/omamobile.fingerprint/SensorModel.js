// SPDX-License-Identifier: MIT
// Pure logic for omamobile.fingerprint. Node runs it in test/sensor-model.js
// through the module.exports at the end.

// What omamobile-fp-bridge publishes (/run/omamobile-fp-ui/state.json):
//   {"op":"idle|enroll|auth","finger":false,"x":717,"y":2360,"r":121,
//    "w":1440,"h":3120,"seq":7,"acquired":1,"remaining":24,"error":0,
//    "last":"none|enrolled|match|nomatch|lockout|error","contact":false,
//    "illuminate":false}
// x, y and r are panel pixels in the panel's own (portrait) orientation,
// w and h the panel size they refer to. acquired, remaining and error are
// the last ACQUIRED code, PROGRESS remaining (-1: none yet) and ERROR code
// of the current or last operation, seq counts those events (older bridges
// leave them out). illuminate: the panel does not light the sensor itself
// (no LHBM, as on the OnePlus 7T Pro): the shell draws a white disc over it
// while a finger is down, as the stock system does. Returns null for
// anything else.
function parse(text) {
  var s
  try { s = JSON.parse(String(text || "")) } catch (e) { return null }
  if (!s || typeof s !== "object") return null
  if (["idle", "enroll", "auth"].indexOf(s.op) < 0) return null
  var n = ["x", "y", "r", "w", "h"]
  for (var i = 0; i < n.length; i++)
    if (typeof s[n[i]] !== "number" || !isFinite(s[n[i]])) return null
  if (s.w <= 0 || s.h <= 0 || s.r <= 0) return null
  var int = function(v, d) { return typeof v === "number" && isFinite(v) ? Math.round(v) : d }
  return { op: s.op, finger: s.finger === true, x: s.x, y: s.y, r: s.r, w: s.w, h: s.h,
           seq: int(s.seq, 0), acquired: int(s.acquired, 0), remaining: int(s.remaining, -1),
           error: int(s.error, 0),
           last: ["enrolled", "match", "nomatch", "lockout", "error"].indexOf(s.last) >= 0 ? s.last : "none",
           // a touch that reached the sensor is still down; null: an older
           // bridge that does not say
           contact: typeof s.contact === "boolean" ? s.contact : null,
           illuminate: s.illuminate === true }
}

function active(state) {
  return !!state && (state.op === "enroll" || state.op === "auth")
}

// The sensor in the screen's logical coordinates.
// TRANSFORM is Hyprland's monitor transform (0 normal, 1 left side up,
// 2 upside down, 3 right side up, as omamobile-autorotate sets them; 4-7
// flipped), WIDTH and HEIGHT the screen's logical size after it.
// Returns { x, y, r } (centre and radius), or null when it cannot be placed:
// a flipped transform, or a screen that doesn't match the panel's shape.
function place(state, transform, width, height) {
  if (!state || !(width > 0) || !(height > 0)) return null
  var t = Number(transform) || 0
  if (t < 0 || t > 3) return null
  var quarter = t === 1 || t === 3
  // logical px per panel pixel; the same both ways, or the screen is not
  // this panel at its own aspect ratio (a mirrored or scaled-down output)
  var k = (quarter ? height : width) / state.w
  var k2 = (quarter ? width : height) / state.h
  if (Math.abs(k - k2) > 0.02 * k) return null
  var px = state.x, py = state.y, x, y
  if (t === 0) { x = px; y = py }
  else if (t === 1) { x = state.h - py; y = px }
  else if (t === 2) { x = state.w - px; y = state.h - py }
  else { x = py; y = state.w - px }
  return { x: x * k, y: y * k, r: state.r * k }
}

// ---------------------------------------------------------------- enrollment

// The HAL's steps: PROGRESS counts the samples still needed down to 0, two
// at a time on this sensor. FIRST is the first count seen, SECOND the next
// one (or -1): their difference is the step, so the first touch already
// shows on the ring. Returns 0..1.
function enrollProgress(remaining, first, second) {
  if (!(first >= 0) || !(remaining >= 0)) return 0
  var step = second >= 0 && second < first ? first - second : 2
  var total = first + step
  return Math.max(0, Math.min(1, (total - remaining) / total))
}

// Android's second stage: after half the samples, the edges of the finger.
function enrollStage(progress) {
  return progress >= 0.5 ? "edges" : "center"
}

// android.hardware.biometrics.fingerprint.AcquiredInfo -> what to tell the
// user, or "" for nothing new (GOOD and START keep the stage's own words).
function acquiredHint(code) {
  switch (Number(code)) {
  case 2: case 3: return "Press your whole finger on the sensor"
  case 4: return "Clean the screen over the sensor, then try again"
  case 5: return "Finger moved too slowly. Try again"
  case 6: return "Finger moved too fast. Try again"
  case 8: case 12: return "Keep your finger still"
  case 9: return "Couldn't see your finger. Press it flat on the sensor"
  case 10: return "Too bright. Shade the screen from strong light"
  case 11: return "Move your finger slightly each time"
  case 13: return "Lifted too soon. Hold your finger on the sensor a moment longer"
  default: return ""
  }
}

// fprintd's EnrollStatus retry results -> words, for when the bridge's
// finer hint is not there (an older bridge).
function retryHint(result) {
  switch (String(result || "")) {
  case "enroll-retry-scan": return "Couldn't read your fingerprint. Try again"
  case "enroll-swipe-too-short": return "Lifted too soon. Hold your finger on the sensor a moment longer"
  case "enroll-finger-not-centered": return "Press your whole finger on the sensor"
  case "enroll-remove-and-retry": return "Lift your finger, then try again"
  default: return ""
  }
}

// The stage's own title and subtitle, after Android's enrollment screens.
function enrollText(started, progress) {
  if (!started) return { title: "Touch the sensor", body: "Put your finger on the circle and hold it there until the circle lights up" }
  if (enrollStage(progress) === "edges")
    return { title: "Now place the edges of your finger", body: "Lift, then touch again with the left or right side of your finger" }
  return { title: "Lift, then touch again", body: "Keep lifting your finger to add the different parts of your fingerprint" }
}

// android.hardware.biometrics.fingerprint.Error -> words.
function errorText(code) {
  switch (Number(code)) {
  case 1: return "The fingerprint sensor isn't available right now"
  case 2: return "Couldn't process the fingerprint. Try again"
  case 3: return "Time's up. Try again"
  case 4: return "There's no room for more fingerprints"
  case 5: return "Fingerprint setup was canceled"
  case 7: return "The sensor reported a problem. Try again"
  case 8: return "The sensor needs calibration"
  default: return "Fingerprint setup didn't work. Try again"
  }
}

// A failed enrollment, from the helper's result (fprintd) and the bridge's
// state, which knows the HAL's own reason. BASESEQ is the bridge's seq when
// this enrollment started, so an older error is not taken for this one.
function failureText(result, kind, state, baseSeq) {
  if (state && state.seq > baseSeq && state.last === "error" && state.error > 0)
    return errorText(state.error)
  if (state && state.seq > baseSeq && state.last === "lockout")
    return "Too many attempts. Try again later"
  switch (String(kind || "")) {
  case "busy": return "The fingerprint sensor is busy. Try again in a moment"
  case "denied": return "Fingerprint setup needs your permission"
  case "no-device": return "No fingerprint sensor found. Is omamobile-fp running?"
  case "no-space": return "Every finger is already added"
  }
  switch (String(result || "")) {
  case "enroll-data-full": return "There's no room for more fingerprints"
  case "enroll-duplicate": return "This fingerprint is already added"
  case "enroll-disconnected": return "The fingerprint sensor stopped responding"
  case "canceled": return errorText(5)
  }
  return errorText(0)
}

// fprintd's finger names ("right-index-finger", "left-thumb") -> words.
function fingerLabel(name) {
  var text = String(name || "").split("-").filter(function(w) { return w.length > 0 }).join(" ")
  return text.length > 0 ? text : "finger"
}

if (typeof module !== "undefined") {
  module.exports = { parse: parse, active: active, place: place,
                     enrollProgress: enrollProgress, enrollStage: enrollStage,
                     acquiredHint: acquiredHint, retryHint: retryHint, enrollText: enrollText,
                     errorText: errorText, failureText: failureText, fingerLabel: fingerLabel }
}
