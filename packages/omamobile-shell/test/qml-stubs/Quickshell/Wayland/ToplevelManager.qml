// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick

// The foreign-toplevel list: the test fills values with objects that have
// appId, title, activate() and close().
QtObject {
  property QtObject toplevels: QtObject { property var values: [] }
}
