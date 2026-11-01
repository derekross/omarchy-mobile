// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick

// Stand-in for Quickshell's singleton, enough for Omarchy's Commons and the
// lock to load under qmltestrunner (test/lock-glance). The test sets the
// environment (vars), the files FileView finds (files: path -> text, which
// take the place of the disk), and answers the commands Process starts
// (responder); diskChanged() makes every watching FileView re-read.
QtObject {
  property var vars: ({})
  property var files: ({})
  property var screens: []
  property string shellDir: "/stub/shell"
  property var executed: []
  property var started: []
  // function(argv) -> stdout text, or null to leave the process running
  property var responder: null

  signal diskChanged()

  function env(name) { return vars[name] !== undefined ? String(vars[name]) : "" }
  function execDetached(argv) { executed = executed.concat([argv]) }
  function iconPath(name, check) { return "" }
}
