// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// A "hide keyboard" button, as on Android: while squeekboard is unfolded, a
// small button sits just above the keyboard's top-left corner; a tap folds
// it (sm.puri.OSK0 SetVisible false). Visibility comes from
// bin/omamobile-osk-watch (squeekboard's Visible on the session bus).
//
// The button's window is anchored to the bottom-left corner with normal
// exclusion, so the compositor places it right above the area the keyboard
// reserves; the window is the button, so it takes no other touches. Left,
// not right: the bottom right just above the keyboard is where apps put
// Send and Next, and the button covered them. It is a full 44 px tall.
// (A hide key inside squeekboard's layouts would cover nothing, but the
// text layouts are squeekboard's own, one per language; overriding them
// means carrying and updating copies of all of them.)
// hypr/phone.lua lets it work over the lock screen too (above_lock 2).
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  // Nothing to summon: it follows the keyboard.
  function open(payloadJson) {
    Qt.callLater(function() {
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide((root.manifest && root.manifest.id) || "omamobile.keyboard")
    })
  }
  function close() {}

  // `shell call omamobile.keyboard state ''`
  function state() {
    return JSON.stringify({ keyboard: oskOpen, watcher: oskWatch.running, button: button.visible })
  }

  // `shell call omamobile.keyboard hideKeyboard ''` / `showKeyboard ''` /
  // `toggleKeyboard ''` (not show/hide: the IPC command line takes `show`
  // for itself)
  function hideKeyboard() { setVisible(false); return "ok" }
  function showKeyboard() { setVisible(true); return "ok" }
  function toggleKeyboard() { setVisible(!oskOpen); return oskOpen ? "hiding" : "showing" }

  function setVisible(visible) {
    Quickshell.execDetached(["busctl", "--user", "call", "sm.puri.OSK0", "/sm/puri/OSK0",
                             "sm.puri.OSK0", "SetVisible", "b", visible ? "true" : "false"])
  }

  property bool oskOpen: false

  Process {
    id: oskWatch
    command: ["omamobile-osk-watch"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var words = String(line).trim().split(" ")
        if (words[0] === "visible") root.oskOpen = words[1] === "true"
      }
    }
    onExited: {
      root.oskOpen = false
      restart.restart()
    }
  }

  Timer {
    id: restart
    interval: 3000
    onTriggered: oskWatch.running = true
  }

  readonly property int size: Math.max(44, Style.space(44))

  PanelWindow {
    id: button

    visible: root.oskOpen
    anchors { bottom: true; left: true }
    margins { left: Style.space(8); bottom: Style.space(6) }
    implicitWidth: root.size + Style.space(8)
    implicitHeight: root.size
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-osk-hide"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Item {
      anchors.fill: parent

      Rectangle {
        anchors.fill: parent
        radius: Math.min(height / 2, Style.cornerRadius + 6)
        color: tap.pressed ? Qt.darker(Commons.Color.bar.background, 1.3) : Commons.Color.bar.background
        opacity: 0.92
        border.width: 1
        border.color: Qt.rgba(Commons.Color.bar.text.r, Commons.Color.bar.text.g, Commons.Color.bar.text.b, 0.25)
      }

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        // nf-md-keyboard_close
        text: String.fromCodePoint(0xF030F)
        color: Commons.Color.bar.text
        font.family: Style.font.family
        font.pixelSize: Math.round(root.size * 0.5)
      }

      MouseArea {
        id: tap
        anchors.fill: parent
        onClicked: root.hideKeyboard()
      }
    }
  }
}
