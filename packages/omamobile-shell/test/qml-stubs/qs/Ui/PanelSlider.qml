// SPDX-License-Identifier: MIT
import QtQuick

// Omarchy's PanelSlider: a press or a drag sets liveValue from x and says
// moved, the release says released; nothing drawn.
Item {
  id: root
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property real trackHeight: 4
  property real knobSize: 14
  property color trackColor: "#333"
  property color fillColor: "#fff"
  property color knobColor: "#fff"
  property color tickColor: "#000"
  property bool dragging: false
  property real liveValue: value
  onValueChanged: if (!dragging) liveValue = value
  signal moved(real value)
  signal released(real value)
  implicitWidth: 200
  implicitHeight: 22

  MouseArea {
    anchors.fill: parent
    function at(x) { return root.minimum + Math.max(0, Math.min(1, x / Math.max(1, width))) * (root.maximum - root.minimum) }
    onPressed: function(mouse) { root.dragging = true; root.liveValue = at(mouse.x); root.moved(root.liveValue) }
    onPositionChanged: function(mouse) { if (root.dragging) { root.liveValue = at(mouse.x); root.moved(root.liveValue) } }
    onReleased: { root.dragging = false; root.released(root.liveValue); root.liveValue = root.value }
  }
}
