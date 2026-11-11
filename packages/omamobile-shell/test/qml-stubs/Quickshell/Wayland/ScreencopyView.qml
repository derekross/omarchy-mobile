// SPDX-License-Identifier: MIT
import QtQuick

// A capture that never gets a frame until a test says so (hasContent), and
// then paints its window's colour (a test window's `colour`, else grey).
// Without a source it has no frame, as Quickshell's drops its context.
Item {
  property var captureSource: null
  property bool live: false
  property bool hasContent: false
  // A recording Hyprland fails just never gets a frame, as Quickshell's
  // (0.3.2) ends it without emitting its stopped signal.
  property int starts: 0
  function captureFrame() {}
  onCaptureSourceChanged: if (!captureSource) hasContent = false; else starts++
  Rectangle {
    anchors.fill: parent
    visible: parent.hasContent
    color: parent.captureSource && parent.captureSource.colour !== undefined ? parent.captureSource.colour : "grey"
  }
}
