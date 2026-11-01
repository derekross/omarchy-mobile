// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell

// Stand-in for Quickshell's Process: records what it would run, and when
// the test's responder answers the command, finishes with that output.
QtObject {
  id: proc
  property var command: []
  property bool running: false
  property var stdout: null
  property var stderr: null
  property var environment: ({})
  signal exited(int exitCode, int exitStatus)

  onRunningChanged: {
    if (!running) return
    var argv = command
    Quickshell.started = Quickshell.started.concat([argv])
    var out = typeof Quickshell.responder === "function" ? Quickshell.responder(argv) : null
    if (out === null || out === undefined) return
    Qt.callLater(function() {
      if (proc.stdout) {
        proc.stdout.text = String(out)
        proc.stdout.streamFinished()
      }
      proc.running = false
      proc.exited(0, 0)
    })
  }
}
