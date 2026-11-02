// SPDX-License-Identifier: MIT
// The keyboard plugin's pure rules, shared by Keyboard.qml and
// test/keyboard-model.js (through the module.exports at the end).
//
// squeekboard shows itself when a text field takes focus (the input method
// activates) and hides when it leaves. A keyboard shown by hand (the pill's
// double tap, showKeyboard from a script: sm.puri.OSK0 SetVisible true) is
// different: squeekboard keeps a forced-visible override that only an input
// method change clears. Shown over an app with no text field, going home
// changes no input method, so the keyboard stayed up over the home screen
// (and a second double tap could re-show it on the way: "random"). So the
// plugin remembers that it showed the keyboard, and puts such a keyboard
// away when the home screen comes up. A keyboard squeekboard showed on its
// own is left to squeekboard, which hides it when the field goes away.

// Whether the keyboard is still one shown by hand after a visibility report
// from omamobile-osk-watch: hiding ends it, showing keeps what we knew.
function shownByHandAfter(shownByHand, visible) {
  return visible ? !!shownByHand : false
}

// The home screen is in front: the focused workspace holds no window (the
// launcher's dock shows then, its !appOnScreen).
function homeOnScreen(workspace) {
  if (!workspace || !workspace.toplevels) return false
  var list = workspace.toplevels.values !== undefined ? workspace.toplevels.values : workspace.toplevels
  return !!list && list.length === 0
}

// Hide now: a keyboard we showed, still up, over the home screen. Checked
// when any of the three changes, so the order (home first, or the show
// arriving after it) doesn't matter.
function shouldHide(shownByHand, visible, home) {
  return !!(shownByHand && visible && home)
}

// The pill's double tap: show the keyboard when it is down, hide it when
// it is up. Its visibility reaches the plugin a moment after a show or a
// hide (omamobile-osk-watch, on the session bus), so a second double tap
// soon after the first answered the old state and showed it again: within
// TOGGLE_SETTLE_MS of the last request, the opposite of that request wins.
var TOGGLE_SETTLE_MS = 1500

function toggleTarget(visible, lastRequest, msSinceRequest) {
  if (lastRequest === true || lastRequest === false) {
    if (Number(msSinceRequest) >= 0 && Number(msSinceRequest) < TOGGLE_SETTLE_MS) return !lastRequest
  }
  return !visible
}

// The language sheet (the keyboard's globe key). omamobile-keyboard-languages
// list prints {current, configured, sources: [{kind, name, label}],
// available: [{name, label}]}; anything else is no listing (null), and the
// sheet then shows nothing to pick rather than stale rows.
function parseListing(text) {
  var data
  try { data = JSON.parse(String(text || "")) } catch (e) { return null }
  if (!data || typeof data !== "object" || !Array.isArray(data.sources)) return null
  var clean = function(list) {
    return (Array.isArray(list) ? list : []).filter(function(r) {
      return r && typeof r.name === "string" && r.name !== ""
    }).map(function(r) {
      return { name: r.name, label: typeof r.label === "string" && r.label !== "" ? r.label : r.name }
    })
  }
  return {
    current: typeof data.current === "string" ? data.current : "",
    configured: Number(data.configured) || 0,
    sources: clean(data.sources),
    available: clean(data.available)
  }
}

// The sheet's first page: one row per language, the current one marked, a
// remove target on the others while more than one is configured, and "Add
// a language" when the keyboard has a layout that isn't on the list. A
// single language still gets its row (the globe always opens the sheet, so
// people find it).
function languageRows(listing) {
  if (!listing) return []
  var rows = listing.sources.map(function(s) {
    var current = s.name === listing.current
    return { kind: "language", name: s.name, label: s.label, current: current,
             removable: !current && listing.configured > 1 }
  })
  if (listing.available.length > 0) rows.push({ kind: "add", name: "", label: "Add a language", current: false, removable: false })
  return rows
}

// The add page: the keyboard's other layouts; a tap adds one and switches.
function addRows(listing) {
  if (!listing) return []
  return listing.available.map(function(a) {
    return { kind: "language", name: a.name, label: a.label, current: false, removable: false }
  })
}

if (typeof module !== "undefined") {
  module.exports = { shownByHandAfter: shownByHandAfter, homeOnScreen: homeOnScreen, shouldHide: shouldHide,
                     TOGGLE_SETTLE_MS: TOGGLE_SETTLE_MS, toggleTarget: toggleTarget,
                     parseListing: parseListing, languageRows: languageRows, addRows: addRows }
}
