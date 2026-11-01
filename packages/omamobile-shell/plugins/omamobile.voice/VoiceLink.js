// SPDX-License-Identifier: MIT
.pragma library

// The voice bar, in reach of the pill (omamobile.launcher): a hold opens
// it, and a call through a process (`omarchy-shell shell call
// omamobile.voice ...`) is slower than the finger. All plugins run in the
// shell's one QML engine, and a `.pragma library` script has one instance
// per engine for every file that imports it by the same URL (as
// omamobile.launcher's DrawerLink.js): Voice.qml publishes its root here,
// and the launcher reaches it through VoiceLinkClient.qml, which sits
// beside this file so the URL is the same.
//
// The voice service's calls: start(), toggle(), press(), release(),
// done(), cancel(), and its `phase` and `mine`.
//
// Nothing depends on it: without it the launcher falls back to the
// plugin's IPC.

var voice = null
var watchers = []

function notify() {
  for (var i = 0; i < watchers.length; i++) {
    try { watchers[i].fn(voice) } catch (e) { }
  }
}

function publish(item) {
  voice = item
  notify()
}

function withdraw(item) {
  if (voice !== item) return
  voice = null
  notify()
}

// fn(voice) now, and again whenever the service comes or goes, until owner
// unwatches.
function watch(owner, fn) {
  watchers.push({ owner: owner, fn: fn })
  try { fn(voice) } catch (e) { }
}

function unwatch(owner) {
  var keep = []
  for (var i = 0; i < watchers.length; i++)
    if (watchers[i].owner !== owner) keep.push(watchers[i])
  watchers = keep
}
