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
                SettingsLabel { text: qsTr("Storage"); color: page.colors.foreground; font.pixelSize: SettingsStyle.fontPx(17); font.weight: Font.DemiBold }
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
        Repeater {
            model: [
                {label: qsTr("Manufacturer"), key: "manufacturer"},
                {label: qsTr("Memory"), key: "memory"},
                {label: qsTr("Architecture"), key: "architecture"},
                {label: qsTr("Kernel"), key: "kernel"},
                {label: qsTr("Omarchy"), key: "omarchyVersion"},
                {label: qsTr("Mobile shell"), key: "shellVersion"},
                {label: qsTr("Settings"), key: "settingsVersion"}
            ]
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 5
                SettingsLabel { text: modelData.label; color: page.colors.muted; font.pixelSize: SettingsStyle.fontPx(13) }
                SettingsLabel {
                    Layout.fillWidth: true
                    text: page.value(modelData.key)
                    textFormat: Text.PlainText; wrapMode: Text.Wrap
                    color: page.colors.foreground; font.pixelSize: SettingsStyle.fontPx(16)
                }
            }
        }
    }
}
