// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick
QtObject {
  property var monitors: ({ values: [] })
  property var focusedMonitor: null
  signal rawEvent(var event)
  function dispatch(command) {}
  function monitorFor(screen) { return null }
}
