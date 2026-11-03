// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick

// The MPRIS players on the session bus: the test fills players.values with
// objects shaped as Quickshell's MprisPlayer.
QtObject {
  property QtObject players: QtObject { property var values: [] }
}
