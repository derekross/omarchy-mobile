// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import "."
T.TextField {
    id: control
    readonly property real contentMinimumHeight: Math.max(48, contentHeight + topPadding + bottomPadding, placeholder.implicitHeight + topPadding + bottomPadding)
    implicitWidth: 160; implicitHeight: contentMinimumHeight
    Layout.minimumHeight: contentMinimumHeight
    leftPadding: 16; rightPadding: 16; topPadding: 10; bottomPadding: 10
    font.family: SettingsStyle.fontFamily; font.pixelSize: SettingsStyle.fontPx(15)
    color: enabled ? SettingsStyle.foreground : SettingsStyle.disabledForeground
    placeholderTextColor: SettingsStyle.muted
    selectionColor: SettingsStyle.selection
    selectedTextColor: SettingsStyle.foreground
    verticalAlignment: TextInput.AlignVCenter
    Text {
        id: placeholder
        objectName: "nativePlaceholder"
        x: control.leftPadding; y: control.topPadding
        width: control.width - control.leftPadding - control.rightPadding
        height: control.height - control.topPadding - control.bottomPadding
        text: control.placeholderText; font: control.font
        color: control.placeholderTextColor
        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        textFormat: Text.PlainText
        visible: control.length === 0 && control.preeditText.length === 0
    }
    background: Rectangle {
        radius: SettingsStyle.radius(width, height)
        color: SettingsStyle.fill("normal")
        border.color: SettingsStyle.border(control.activeFocus ? "focus" : "normal")
        border.width: SettingsStyle.borderWidth(control.activeFocus ? "focus" : "normal")
        opacity: control.enabled ? 1 : .5
    }
}
