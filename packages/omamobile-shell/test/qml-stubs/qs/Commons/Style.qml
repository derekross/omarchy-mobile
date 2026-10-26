// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick

// Omarchy's Style at scale 1.
QtObject {
  property int cornerRadius: 8
  property QtObject font: QtObject {
    property string family: "sans-serif"
    property int caption: 10
    property int body: 14
    property int subtitle: 16
    property int title: 18
  }
  function space(px) { return Math.round(px) }
  function pressedFillFor(foreground, accent, urgent) { return Qt.rgba(1, 1, 1, 0.2) }
}
