// SPDX-License-Identifier: MIT
// The back gesture's pure parts, shared by Back.qml and test/back-model.js
// (through the module.exports at the end).

// Escape to whatever has the keyboard focus: an app's window or a focused
// shell surface (a sheet, the drawer). Hyprland 0.56's Lua dispatcher, as
// Omarchy's own clipboard bindings send keys (default/hypr/bindings/
// clipboard.lua): no window target, so focused layer surfaces get it too, and
// a key down then a key up 50 ms later, because send_shortcut sometimes left
// the synthetic key held. One sh, so the up can't overtake the down.
var ESCAPE_DOWN = 'hl.dsp.send_key_state({ mods = "", key = "Escape", state = "down" })'
var ESCAPE_UP = 'hl.dsp.send_key_state({ mods = "", key = "Escape", state = "up" })'
var ESCAPE_ARGV = ["sh", "-c", 'hyprctl dispatch "$1" >/dev/null; sleep 0.05; hyprctl dispatch "$2" >/dev/null',
                   "sh", ESCAPE_DOWN, ESCAPE_UP]

// How far the finger has to come in from the edge (logical px), and how far
// a swipe may wander along the edge for each pixel it comes in: a mostly
// vertical drag that starts on the strip is not a back.
var THRESHOLD = 56

// 0 at the edge, 1 once a release would go back.
function progress(inward, threshold) {
  var t = threshold > 0 ? threshold : THRESHOLD
  var v = Number(inward) || 0
  return v <= 0 ? 0 : Math.min(1, v / t)
}

// inward: px towards the middle of the screen; across: px along the edge.
function fires(inward, across, threshold) {
  var t = threshold > 0 ? threshold : THRESHOLD
  var i = Number(inward) || 0
  return i >= t && Math.abs(Number(across) || 0) < i
}

// The finger's travel towards the middle, from a drag's x translation.
function inwardFor(rightEdge, translationX) {
  var x = Number(translationX) || 0
  return rightEdge ? -x : x
}

if (typeof module !== "undefined") {
  module.exports = {
    ESCAPE_DOWN: ESCAPE_DOWN, ESCAPE_UP: ESCAPE_UP, ESCAPE_ARGV: ESCAPE_ARGV, THRESHOLD: THRESHOLD,
    progress: progress, fires: fires, inwardFor: inwardFor
  }
}
