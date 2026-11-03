// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick

// The desktop entries, for the lock's media controls' app icon: the test
// fills applications.values with objects that have id and icon.
QtObject {
  property QtObject applications: QtObject { property var values: [] }
  function byId(id) {
    var list = applications.values
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }
  function heuristicLookup(name) { return byId(name) }
}
