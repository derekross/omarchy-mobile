// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick

// Omarchy's border specs: plain objects here, nothing drawn.
QtObject {
  function flat(color, width) { return { color: color, width: width } }
  function controlSpec(state, foreground, accent) { return { state: state } }
  function none() { return {} }
  function left(spec) { return 0 }
}
