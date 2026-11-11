// SPDX-License-Identifier: MIT
import QtQuick

// A capture that never gets a frame until a test says so (hasContent), and
// then paints its window's colour (a test window's `colour`, else grey).
// Without a source it has no frame, as Quickshell's drops its context.
Item {
  property var captureSource: null
  property bool live: false
  property bool hasContent: false
  // Quickshell's ends a recording Hyprland fails and says so.
  signal stopped()
  property int starts: 0
  function captureFrame() {}
  onCaptureSourceChanged: if (!captureSource) hasContent = false; else starts++
  Rectangle {
    anchors.fill: parent
    visible: parent.hasContent
    color: parent.captureSource && parent.captureSource.colour !== undefined ? parent.captureSource.colour : "grey"
  }
}
