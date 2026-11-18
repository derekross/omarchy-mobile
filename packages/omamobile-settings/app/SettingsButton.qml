// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import "."
T.Button {
    id: control
    property real cornerRadius: SettingsStyle.cornerRadius
    readonly property string visualState: down ? "pressed" : highlighted ? "selected" : activeFocus ? "focus" : hovered ? "hover-cursor" : "normal"
    implicitWidth: Math.max(80, implicitContentWidth + leftPadding + rightPadding)
    readonly property real contentMinimumHeight: Math.max(48, implicitContentHeight + topPadding + bottomPadding)
    implicitHeight: contentMinimumHeight
    Layout.minimumHeight: contentMinimumHeight
    padding: 12
    hoverEnabled: true
    font.family: SettingsStyle.fontFamily
    font.pixelSize: SettingsStyle.fontPx(15)
    contentItem: Text {
        text: control.text; font: control.font
        color: control.enabled ? SettingsStyle.foreground : SettingsStyle.disabledForeground
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap; elide: Text.ElideNone; textFormat: Text.PlainText
    }
    background: Rectangle {
        radius: Math.min(Math.max(0, control.cornerRadius), width / 2, height / 2)
        color: control.flat && control.visualState === "normal" ? "transparent" : SettingsStyle.fill(control.visualState)
        border.color: SettingsStyle.border(control.visualState)
        border.width: control.flat && !control.activeFocus ? 0 : SettingsStyle.borderWidth(control.visualState)
        opacity: control.enabled ? 1 : .5
    }
}
