// SPDX-License-Identifier: MIT
import QtQuick

QtObject {
  property string text: ""
  property bool waitForEnd: false
  signal streamFinished()
}
