// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."
// The intro sits above the list, not in its header: a wrapped header only gets its
// final height after the list's first layout, which left its top lines cut off.
ColumnLayout {
    id: page
    spacing: 12
    SettingsLabel {
        objectName: "creditsIntro"
        Layout.fillWidth: true
        text: qsTr("The people who work on Omamobile, by GitHub username: the contributors of the project's repositories and the authors of merged pull requests to linux-omamobile.")
        wrapMode: Text.Wrap; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(14)
    }
    ListView {
        id: list
        objectName: "creditsList"
        Layout.fillWidth: true; Layout.fillHeight: true
        clip: true; spacing: 8
        model: backend.credits()
        delegate: Rectangle {
            required property var modelData
            width: list.width
            implicitHeight: row.implicitHeight + 24
            height: implicitHeight
            radius: SettingsStyle.radius(width, height)
            color: SettingsStyle.surface
            ColumnLayout {
                id: row
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                spacing: 2
                SettingsLabel {
                    Layout.fillWidth: true
                    text: "@" + modelData.login; wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    color: backend.foreground; font.pixelSize: SettingsStyle.fontPx(16)
                }
            }
        }
        ScrollBar.vertical: SettingsScrollBar {}
    }
}
