// SPDX-License-Identifier: MIT
// Each part restates the repository: LICENSE, README.md, docs/INSTALL.md and docs/DEVICES.md. Change those first.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."
ScrollView {
    id: page
    objectName: "disclaimerPage"
    contentWidth: availableWidth
    clip: true
    ScrollBar.vertical: SettingsScrollBar {}
    ColumnLayout {
        width: page.availableWidth
        spacing: 16
        Repeater {
            model: [
                {title: qsTr("Status"), text: qsTr("Omamobile is a community project built on Omarchy. It isn't an official Omarchy or Basecamp product. Releases are developer previews.")},
                {title: qsTr("What works"), text: qsTr("Support differs from phone to phone. The project's devices list (docs/DEVICES.md on github.com/derekross/omamobile) gives each feature of each phone a status such as works, testing, partial or no. Anything it doesn't mark as works may be missing, off by default or incomplete.")},
                {title: qsTr("Installing"), text: qsTr("Unlocking the bootloader erases the phone, and installing replaces its user data. On the Pixel 7 Pro the installer writes only slot B and user data, and stock Android stays on slot A as the way back; other phones may differ, see their notes in the devices list.")},
                {title: qsTr("Licence"), text: qsTr("MIT License, copyright (c) 2026 Derek Ross and Omamobile contributors, except where a file's SPDX header says otherwise (for example, the kernel patches are GPL-2.0). The software is provided as is, without warranty of any kind. The full text is the LICENSE file on github.com/derekross/omamobile.")}
            ]
            delegate: ColumnLayout {
                objectName: "disclaimer-" + index
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 4
                SettingsLabel { Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData.title; color: backend.foreground; font.pixelSize: SettingsStyle.fontPx(17); font.weight: Font.DemiBold }
                SettingsLabel { Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: modelData.text; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(14) }
            }
        }
    }
}
