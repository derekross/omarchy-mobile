// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import "."
T.ItemDelegate {
    id: control
    readonly property real contentMinimumHeight: Math.max(48, implicitContentHeight + topPadding + bottomPadding)
    implicitWidth: 160; implicitHeight: contentMinimumHeight
    Layout.minimumHeight: contentMinimumHeight
    padding: 12; hoverEnabled: true
    font.family: SettingsStyle.fontFamily; font.pixelSize: SettingsStyle.fontPx(15)
    contentItem: Text {
        text: control.text; font: control.font
        color: control.enabled ? SettingsStyle.foreground : SettingsStyle.disabledForeground
        verticalAlignment: Text.AlignVCenter; wrapMode: Text.Wrap; elide: Text.ElideNone; textFormat: Text.PlainText
    }
    background: Rectangle {
        radius: SettingsStyle.radius(width, height)
        readonly property string stateName: control.down ? "pressed" : control.highlighted ? "selected" : control.activeFocus ? "focus" : control.hovered ? "hover-cursor" : "normal"
        color: SettingsStyle.fill(stateName)
        border.color: SettingsStyle.border(stateName)
        border.width: SettingsStyle.borderWidth(stateName)
    }
}
