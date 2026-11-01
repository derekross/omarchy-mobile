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

if (typeof module !== "undefined") {
  module.exports = { shownByHandAfter: shownByHandAfter, homeOnScreen: homeOnScreen, shouldHide: shouldHide }
}
