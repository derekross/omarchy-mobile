// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick

// The desktop entries a test declares, by id: { name, icon }.
QtObject {
  property var entries: ({})
  function byId(id) { return entries[id] || null }
  function heuristicLookup(id) { return entries[id] || entries[String(id).toLowerCase()] || null }
}
