// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Wayland

// The language sheet's layer-shell window: the whole screen, on the overlay
// layer over the keyboard (squeekboard's "osk" surface) and the app, mapped
// only while the sheet is open or sliding away. It never takes the keyboard
// focus, so the text field keeps it and squeekboard stays up underneath with
// the new layout. Not above the lock: Hyprland runs the globe's bind only
// while unlocked.
PanelWindow {
  id: win

  property bool opened: false
  property var listing: null
  signal picked(string name)
  signal removed(string name)
  signal dismissed()

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  onOpenedChanged: if (opened) languageSheet.reset()

  visible: opened || reveal > 0
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  WlrLayershell.namespace: "omamobile-keyboard-languages"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  LanguageSheet {
    id: languageSheet
    anchors.fill: parent
    listing: win.listing
    reveal: win.reveal
    onPicked: function(name) { win.picked(name) }
    onRemoved: function(name) { win.removed(name) }
    onDismissed: win.dismissed()
  }
}
