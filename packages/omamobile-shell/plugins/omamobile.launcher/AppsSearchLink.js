// SPDX-License-Identifier: MIT
.pragma library

// Native panels share one registry in the shell's QML engine. Back can close
// Search even before its OnDemand window has received keyboard focus.
var controller = null

function publish(value) { controller = value }
function clear(value) { if (controller === value) controller = null }
function close() {
  if (!controller || !controller.searchOpened) return false
  controller.closeSearch()
  return true
}

// System Back may step out of the conversation. Home always calls close().
function back() {
  if (!controller || !controller.searchOpened) return false
  if (typeof controller.backSearch === "function") controller.backSearch()
  else controller.closeSearch()
  return true
}
