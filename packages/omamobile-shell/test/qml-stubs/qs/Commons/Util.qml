// SPDX-License-Identifier: MIT
pragma Singleton
import QtQuick

QtObject {
  function alpha(c, opacity) { return Qt.rgba(c.r, c.g, c.b, opacity) }
}
