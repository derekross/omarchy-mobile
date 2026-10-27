// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick

// Hyprland's windows: { wayland, address, workspace, title, lastIpcObject }.
QtObject {
  property QtObject toplevels: QtObject { property var values: [] }
  function refreshToplevels() {}
}
