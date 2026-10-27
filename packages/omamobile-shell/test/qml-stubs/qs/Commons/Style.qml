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
    property int iconLarge: 18
  }
  property QtObject spacing: QtObject {
    property int xxs: 2
    property int xs: 4
    property int md: 8
    property int lg: 12
  }
  function space(px) { return Math.round(px) }
  function pressedFillFor(foreground, accent, urgent) { return Qt.rgba(1, 1, 1, 0.2) }
}
