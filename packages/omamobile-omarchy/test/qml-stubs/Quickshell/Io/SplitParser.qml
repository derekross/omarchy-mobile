// SPDX-License-Identifier: MIT
import QtQuick
QtObject {
  property string text: ""
  property string splitMarker: "\n"
  signal read(string data)
  signal streamFinished()
}
