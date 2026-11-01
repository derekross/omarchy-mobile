// SPDX-License-Identifier: MIT
.pragma library

// The app drawer, in reach of the home screen's swipe. A swipe up on the
// home screen has to move the drawer with the finger, but the finger is on
// the home screen's surface (omamobile.home), and the host lets a plugin
// summon only its own panels, through a process (`omarchy-shell shell
// summon`) far too slow to follow a finger. Both plugins run in the shell's
// one QML engine, and a `.pragma library` script has one instance per
// engine for every file that imports it by the same URL: Launcher.qml
// publishes its root here, and the home screen reaches it through
// DrawerLinkClient.qml, which sits beside this file so the URL is the same.
// The drawer's calls are gestureBegin(), gestureMove(px), gestureEnd(px/s),
// and its `progress` (0 closed, 1 open).
//
// Nothing depends on it: without it the home screen's swipe still opens the
// drawer through the host when the finger lets go.

var drawer = null
var watchers = []

function notify() {
  for (var i = 0; i < watchers.length; i++) {
    try { watchers[i].fn(drawer) } catch (e) { }
  }
}

function publish(item) {
  drawer = item
  notify()
}

function withdraw(item) {
  if (drawer !== item) return
  drawer = null
  notify()
}

// fn(drawer) now, and again whenever the drawer comes or goes, until owner
// unwatches.
function watch(owner, fn) {
  watchers.push({ owner: owner, fn: fn })
  try { fn(drawer) } catch (e) { }
}

function unwatch(owner) {
  var keep = []
  for (var i = 0; i < watchers.length; i++)
    if (watchers[i].owner !== owner) keep.push(watchers[i])
  watchers = keep
}
