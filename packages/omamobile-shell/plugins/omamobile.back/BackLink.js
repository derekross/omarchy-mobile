// SPDX-License-Identifier: MIT
.pragma library

// What Back asks before it sends Escape. Escape goes to whatever has the
// keyboard focus, and some of the shell's surfaces never take it, on purpose:
// the permission sheet, fingerprint enrollment, the keyboard's language
// sheet, voice settings, and the home screen's edit mode and most of its
// sheets. Escape went through those to the app underneath, which, now that
// an app at its top level goes home on Back, went home under the sheet. And
// the on-screen keyboard is no window of any app: Back should put it away
// first, as on Android, for every app at once.
//
// So a surface that is open registers a handler here and takes itself off
// when it closes, and Back.qml asks before it sends anything. The order:
//
//   1. the on-screen keyboard (tier "keyboard"): hidden, nothing else sent;
//      before it, what sits on the keyboard (tier "on-keyboard": its
//      language sheet);
//   2. the topmost registered surface (tier "surface"): the one registered
//      last, since what opened last is on top;
//   3. Escape, to the focused window (Back.qml, when back() here says "").
//
// One Back does one thing. A handler that returns false didn't use it (its
// surface closed without saying so), and the next one is asked; one that
// throws is skipped the same way. A surface that closed is off the list, so
// it can never swallow a later Back.
//
// The plugins run in the shell's one QML engine, and a `.pragma library`
// script has one instance per engine for every file that imports it by the
// same URL: Back.qml imports it here, and the other plugins load
// BackLinkClient.qml from this folder, as the home screen reaches the drawer
// through omamobile.launcher's DrawerLink.js. Nothing depends on it: a
// plugin that can't load the client keeps what it did before.

var TIERS = { "on-keyboard": 3, keyboard: 2, surface: 1 }

var entries = []
var counter = 0

function indexOf(owner) {
  for (var i = 0; i < entries.length; i++) if (entries[i].owner === owner) return i
  return -1
}

// owner: any object, the entry's identity. fn: the handler; true (or
// nothing) when it used the Back. tier: "on-keyboard", "keyboard" or "surface". name: for
// the log and `state`. Registering again keeps the entry's place.
function register(owner, fn, tier, name) {
  if (owner === null || owner === undefined || typeof fn !== "function") return false
  var at = indexOf(owner)
  var rank = TIERS[tier] || TIERS.surface
  if (at >= 0) {
    entries[at].fn = fn
    entries[at].rank = rank
    entries[at].name = String(name || "")
    return true
  }
  entries.push({ owner: owner, fn: fn, rank: rank, name: String(name || ""), seq: ++counter })
  return true
}

function unregister(owner) {
  var keep = []
  for (var i = 0; i < entries.length; i++) if (entries[i].owner !== owner) keep.push(entries[i])
  var gone = keep.length !== entries.length
  entries = keep
  return gone
}

// The entries as Back asks them: the keyboard's first, then the surfaces,
// the last registered first in each.
function ordered() {
  return entries.slice().sort(function(a, b) { return b.rank - a.rank || b.seq - a.seq })
}

function names() {
  return ordered().map(function(e) { return e.name || "surface" })
}

// One Back: the name of the entry that used it, or "" when none did and
// Escape is to be sent.
function back() {
  var list = ordered()
  for (var i = 0; i < list.length; i++) {
    // Still registered: an earlier handler may have closed this one too.
    if (indexOf(list[i].owner) < 0) continue
    var used = false
    try { used = list[i].fn() !== false } catch (e) { used = false }
    if (used) return list[i].name || "surface"
  }
  return ""
}

// For the tests: start empty.
function clear() { entries = []; counter = 0 }
