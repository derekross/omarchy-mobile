// SPDX-License-Identifier: MIT
import QtQuick

// Long-press anywhere on the pages: edit mode. Home.qml lays this over the
// pager, above the tiles and widgets, so it sees every press without taking
// any: apps and widgets still get their taps and the pager its swipes, and
// a drag cancels the long press.
//
// Touch and the mouse take separate handlers. A TapHandler here, even a
// passive DragThreshold one, takes a mouse press for itself, and the tile's
// MouseArea under it never saw a click (issue #147). So the TapHandler takes
// touch only, as the phone has always run it, and a mouse or touchpad hold
// is timed from a PointHandler, which only watches.
// test/home-mouse drives both.
Item {
  id: hold

  property var home: null
  property bool active: true
  // Seconds, as TapHandler.longPressThreshold.
  property real threshold: 0.5

  TapHandler {
    enabled: hold.active
    acceptedDevices: PointerDevice.TouchScreen
    gesturePolicy: TapHandler.DragThreshold
    longPressThreshold: hold.threshold
    onLongPressed: if (hold.home) hold.home.requestEdit()
  }

  PointHandler {
    id: pointer
    enabled: hold.active
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
    acceptedButtons: Qt.LeftButton
    property bool moved: false
    onActiveChanged: {
      moved = false
      if (active) mouseTimer.restart()
      else mouseTimer.stop()
    }
    onPointChanged: {
      if (!active || moved) return
      var d = Qt.styleHints.startDragDistance
      if (Math.abs(point.position.x - point.pressPosition.x) > d
          || Math.abs(point.position.y - point.pressPosition.y) > d) {
        moved = true
        mouseTimer.stop()
      }
    }
  }

  Timer {
    id: mouseTimer
    interval: Math.round(hold.threshold * 1000)
    onTriggered: if (hold.active && pointer.active && !pointer.moved && hold.home) hold.home.requestEdit()
  }
}
