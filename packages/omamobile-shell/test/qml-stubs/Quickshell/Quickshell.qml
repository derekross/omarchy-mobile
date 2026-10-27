// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick

// Records the commands a plugin starts instead of running them.
QtObject {
  property string shellDir: "/stub/shell"
  property var executed: []
  function execDetached(argv) { executed = executed.concat([argv]) }
}
