// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
import QtQuick
import "."
import QtQuick.Controls
import QtQuick.Layouts
ScrollView {
    id: page
    required property var controller
    required property var colors
    contentWidth: availableWidth
    clip: true
    function value(key) { return controller.info[key] || qsTr("Unavailable") }
    ScrollBar.vertical: SettingsScrollBar {
        width: 3; padding: 0; interactive: false
        active: page.contentItem.moving; opacity: active ? 0.65 : 0
        contentItem: Rectangle { implicitWidth: 3; radius: 1.5; color: page.colors.muted }
        background: Item {}
    }
    ColumnLayout {
        width: page.availableWidth
        spacing: 20
        SettingsLabel {
            Layout.fillWidth: true
            text: page.value("model")
            textFormat: Text.PlainText; wrapMode: Text.Wrap
            font.pixelSize: SettingsStyle.fontPx(28); font.weight: Font.DemiBold
            color: page.colors.foreground
        }
        SettingsLabel {
            Layout.fillWidth: true
            text: page.value("system")
            textFormat: Text.PlainText; wrapMode: Text.Wrap
            font.pixelSize: SettingsStyle.fontPx(15); color: page.colors.muted
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: storage.implicitHeight + 32
            radius: Math.min(page.colors.radius, width / 2, height / 2)
            color: SettingsStyle.surface
            ColumnLayout {
                id: storage
                anchors.fill: parent; anchors.margins: 16
                spacing: 10
                SettingsLabel { Layout.fillWidth: true; wrapMode: Text.Wrap; text: qsTr("Storage"); color: page.colors.foreground; font.pixelSize: SettingsStyle.fontPx(17); font.weight: Font.DemiBold }
                SettingsLabel {
                    Layout.fillWidth: true
                    text: page.controller.info.storageKnown
                        ? qsTr("%1 available of %2").arg(page.value("storageFree")).arg(page.value("storageTotal"))
                        : qsTr("Unavailable")
                    wrapMode: Text.Wrap; color: page.colors.muted; font.pixelSize: SettingsStyle.fontPx(14)
                }
                Rectangle {
                    Layout.fillWidth: true; height: 6; radius: 3
                    visible: !!page.controller.info.storageKnown
                    color: SettingsStyle.separator
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, page.controller.info.storageFraction || 0))
                        height: parent.height; radius: 3; color: page.colors.accent
                    }
                }
            }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 2; columnSpacing: 16; rowSpacing: 16
            uniformCellWidths: true
            Repeater {
                model: [
                    {label: qsTr("Manufacturer"), key: "manufacturer"},
                    {label: qsTr("Memory"), key: "memory"},
                    {label: qsTr("Architecture"), key: "architecture"},
                    {label: qsTr("Omarchy"), key: "omarchyVersion"},
                    {label: qsTr("Mobile shell"), key: "shellVersion"},
                    {label: qsTr("Settings"), key: "settingsVersion"},
                    {label: qsTr("Kernel"), key: "kernel", wide: true}
                ]
                delegate: ColumnLayout {
                    required property var modelData
                    objectName: "fact-" + modelData.key
                    Layout.fillWidth: true
                    Layout.columnSpan: modelData.wide ? 2 : 1
                    Layout.alignment: Qt.AlignTop
                    spacing: 5
                    SettingsLabel { Layout.fillWidth: true; wrapMode: Text.Wrap; text: modelData.label; color: page.colors.muted; font.pixelSize: SettingsStyle.fontPx(13) }
                    SettingsLabel {
                        Layout.fillWidth: true
                        text: page.value(modelData.key)
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        color: page.colors.foreground; font.pixelSize: SettingsStyle.fontPx(16)
                    }
                }
            }
        }
        SettingsItemDelegate {
            objectName: "creditsRow"
            Layout.fillWidth: true; implicitHeight: 64
            text: qsTr("Credits")
            onClicked: page.colors.navigate("credits")
            background: Rectangle { radius: Math.min(page.colors.radius, width / 2, height / 2); color: parent.down ? SettingsStyle.fill("pressed") : SettingsStyle.fill("normal") }
            contentItem: RowLayout {
                SettingsLabel { text: qsTr("Credits"); Layout.fillWidth: true; color: page.colors.foreground; font.pixelSize: SettingsStyle.fontPx(17) }
                SettingsLabel { text: "\u203a"; color: page.colors.muted; font.pixelSize: SettingsStyle.fontPx(24); Accessible.ignored: true }
            }
        }
        SettingsItemDelegate {
            objectName: "disclaimer"
            Layout.fillWidth: true; implicitHeight: 64
            text: qsTr("Disclaimer")
            onClicked: page.colors.navigate("disclaimer")
            background: Rectangle { radius: Math.min(page.colors.radius, width / 2, height / 2); color: parent.down ? SettingsStyle.fill("pressed") : SettingsStyle.fill("normal") }
            contentItem: RowLayout {
                SettingsLabel { text: qsTr("Disclaimer"); Layout.fillWidth: true; color: page.colors.foreground; font.pixelSize: SettingsStyle.fontPx(17) }
                SettingsLabel { text: "\u203a"; color: page.colors.muted; font.pixelSize: SettingsStyle.fontPx(24); Accessible.ignored: true }
            }
        }
        SettingsLabel {
            Layout.fillWidth: true; Layout.bottomMargin: 8
            text: qsTr("Omamobile is a community project, not an official Omarchy or Basecamp product.")
            wrapMode: Text.Wrap; color: page.colors.muted; font.pixelSize: SettingsStyle.fontPx(13)
        }
    }
}
