// SPDX-License-Identifier: MIT
// The back gesture's pure parts, shared by Back.qml and test/back-model.js
// (through the module.exports at the end).

// Escape to whatever has the keyboard focus: an app's window or a focused
// shell surface (a sheet, the drawer). Hyprland 0.56's Lua dispatcher, as
// Omarchy's own clipboard bindings send keys (default/hypr/bindings/
// clipboard.lua): no window target, so focused layer surfaces get it too, and
// a key down then a key up 50 ms later, because send_shortcut sometimes left
// the synthetic key held. One sh, so the up can't overtake the down.
// The key goes by its code (9: Escape, evdev's KEY_ESC + 8), not its name:
// Hyprland 0.57 answers a name with "send_key_state: key not found" (Pixel 7
// Pro and 9a, 2026-11-10), so the gesture armed, ticked and sent nothing. A
// code doesn't depend on the keyboard layout either.
var ESCAPE_DOWN = 'hl.dsp.send_key_state({ mods = "", key = "code:9", state = "down" })'
var ESCAPE_UP = 'hl.dsp.send_key_state({ mods = "", key = "code:9", state = "up" })'
// But the key itself goes through a virtual keyboard (wtype) when there is
// one: Hyprland answers the dispatches above with "ok" and the focused app
// never sees the key. On the Pixel 7 Pro (2026-11-10, hyprland 0.57.0-3.2)
// Settings on its About page stayed put for send_key_state by code, by the
// name "Esc", with the window named, and for send_shortcut, and went back at
// once for `wtype -k Escape`. A virtual keyboard's key goes wherever the
// keyboard focus is, a focused shell sheet included, as a real key would.
// The dispatches stay as the fallback on a phone without wtype.
//
// A terminal gets no Escape at all: there it is a key programs use (an
// editor's modes, and two in a row is the shell's "complete", which on an
// empty line asks to list every command: Pixel 7 Pro, 2026-11-10), it never
// means "back", and a terminal has no levels, so it is always at its top
// level and Back goes home (omamobile-home). The keyboard's own Esc key is
// there for the key. Matched by the focused window's class, exactly.
var TERMINALS = ["foot", "footclient", "Alacritty", "kitty", "com.mitchellh.ghostty", "org.omarchy.terminal"]
function isTerminal(windowClass) {
  return TERMINALS.indexOf(String(windowClass || "")) >= 0
}
var ESCAPE_ARGV = ["sh", "-c",
                   'cls=$(hyprctl activewindow -j 2>/dev/null | jq -r ".class // empty" 2>/dev/null); ' +
                   'if [ -n "$cls" ]; then for t in $3; do if [ "$t" = "$cls" ]; then exec omamobile-home; fi; done; fi; ' +
                   'if command -v wtype >/dev/null 2>&1; then exec wtype -k Escape; fi; ' +
                   'hyprctl dispatch "$1" >/dev/null; sleep 0.05; hyprctl dispatch "$2" >/dev/null',
                   "sh", ESCAPE_DOWN, ESCAPE_UP, TERMINALS.join(" ")]

// Home, for an app at its top level: Back is phone-wide, so an app goes back
// one level on Escape while it has one, and at its top level runs this
// command (bin/omamobile-home: the empty workspace and the home page, as the
// home pill). The shell can't tell that an app left Escape unused, so the app
// asks. `shell call omamobile.back home ''` runs it too.
var HOME_ARGV = ["omamobile-home"]

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
  module.exports = { TERMINALS: TERMINALS, isTerminal: isTerminal,
    ESCAPE_DOWN: ESCAPE_DOWN, ESCAPE_UP: ESCAPE_UP, ESCAPE_ARGV: ESCAPE_ARGV, HOME_ARGV: HOME_ARGV, THRESHOLD: THRESHOLD,
    progress: progress, fires: fires, inwardFor: inwardFor
  }
}
