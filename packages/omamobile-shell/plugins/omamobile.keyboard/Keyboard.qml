// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io

// The on-screen keyboard's show and hide calls, for the rest of the shell:
// squeekboard's sm.puri.OSK0 SetVisible, with its visibility from
// bin/omamobile-osk-watch (squeekboard's Visible on the session bus).
//
// It draws nothing. The controls live on the home pill (omamobile.launcher):
// while the keyboard is up over an app, the pill sits in a strip of its own
// under the keyboard, with a keyboard-down key at the strip's right end, and
// a double tap on the pill shows or hides the keyboard. The launcher reaches
// these through IPC (`hideKeyboard`, `toggleKeyboard`), as plugins reach each
// other here.
//
// This plugin used to draw a floating "hide keyboard" button just above the
// keyboard's top-left corner (a layer-shell window, bottom-left, normal
// exclusion). Wherever it sat, it covered something in the app: at the right,
// Send and Next; at the left, a terminal's input line. The strip under the
// keyboard covers nothing. (A hide key inside squeekboard's layouts would
// cover nothing either, but the text layouts are squeekboard's own, one per
// language; overriding them means carrying and updating copies of all of
// them.)
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
    return JSON.stringify({ keyboard: oskOpen, watcher: oskWatch.running })
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
}
