// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Templates as T
import "."
T.ScrollBar {
    id: control
    implicitWidth: 3; implicitHeight: 3
    padding: 0
    contentItem: Rectangle {
        implicitWidth: 3; implicitHeight: 3
        color: SettingsStyle.muted
        radius: SettingsStyle.radius(width, height)
    }
}
