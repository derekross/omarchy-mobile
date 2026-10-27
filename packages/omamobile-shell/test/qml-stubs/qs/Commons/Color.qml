// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick

QtObject {
  property color background: "#1a1b26"
  property color foreground: "#c0caf5"
  property color accent: "#7aa2f7"
  property color urgent: "#f7768e"
  property QtObject menu: QtObject {
    property color background: "#16161e"
    property color text: "#c0caf5"
  }
  property QtObject popups: QtObject {
    property color background: "#16161e"
    property color text: "#c0caf5"
  }
  property QtObject bar: QtObject {
    property color background: "#16161e"
    property color text: "#c0caf5"
  }
}
