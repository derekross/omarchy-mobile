// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
import QtQuick
import "."
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
ApplicationWindow {
    id: window
    width: Math.min(420, Screen.width)
    height: Math.min(880, Screen.height)
    visible: true
    title: backend.title
    font.family: SettingsStyle.fontFamily
    palette.window: SettingsStyle.background
    palette.windowText: SettingsStyle.foreground
    palette.text: SettingsStyle.foreground
    palette.buttonText: SettingsStyle.foreground
    palette.highlight: SettingsStyle.accent
    color: backend.background
    function goBack() {
        search.focus = false
        Qt.inputMethod.hide()
        if (backend.searching) search.clear()
        backend.back()
    }
    readonly property var customPages: ({ display: "DisplayPage.qml" })
    readonly property string customSource: backend.searching ? "" : (customPages[backend.page] || "")
    readonly property bool showingAbout: backend.page === "about" && !backend.searching
    Connections {
        target: backend
        function onRaiseRequested() { window.show(); window.raise(); window.requestActivate() }
        function onPageChanged() { search.text = ""; search.focus = false; Qt.inputMethod.hide(); if (backend.page === "about") deviceInfo.refresh() }
    }
    Component.onCompleted: if (backend.page === "about") deviceInfo.refresh()
    Shortcut { sequence: "Escape"; onActivated: window.goBack() }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 20
        spacing: 18
        SettingsButton {
            visible: backend.page !== "root" || backend.searching
            Layout.preferredHeight: 52
            leftPadding: 0; rightPadding: 12; topPadding: 0; bottomPadding: 0
            onClicked: window.goBack()
            contentItem: Row {
                spacing: 4
                SettingsLabel { text: "‹"; font.pixelSize: SettingsStyle.fontPx(30); color: backend.foreground }
                SettingsLabel { text: qsTr("Back"); font.pixelSize: SettingsStyle.fontPx(17); color: backend.foreground; anchors.verticalCenter: parent.verticalCenter }
            }
            background: Rectangle { color: parent.down ? SettingsStyle.fill("normal") : "transparent"; radius: Math.min(backend.radius, width / 2, height / 2) }
        }
        SettingsLabel { text: backend.title; Layout.fillWidth: true; color: backend.foreground; font.pixelSize: SettingsStyle.fontPx(30); font.weight: Font.DemiBold; wrapMode: Text.Wrap }
        SettingsTextField {
            id: search
            objectName: "settingsSearch"
            Layout.fillWidth: true; Layout.preferredHeight: 52
            visible: !window.showingAbout && window.customSource === ""
            placeholderText: qsTr("Search settings")
            color: backend.foreground; placeholderTextColor: backend.muted
            onTextEdited: backend.search(text)
            background: Rectangle { radius: Math.min(backend.radius, width / 2, height / 2); color: SettingsStyle.fill("normal") }
        }
        AboutPage { visible: window.showingAbout; Layout.fillWidth: true; Layout.fillHeight: true; controller: deviceInfo; colors: backend }
        Loader { id: pageLoader; active: window.customSource !== ""; source: window.customSource; visible: active; Layout.fillWidth: true; Layout.fillHeight: true }
        ListView {
            id: list
            visible: !window.showingAbout && window.customSource === ""
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; model: backend.rows
            delegate: SettingsItemDelegate {
                required property var modelData
                width: list.width; implicitHeight: Math.max(80, copy.implicitHeight + 28)
                onClicked: { search.focus = false; Qt.inputMethod.hide(); backend.activate(modelData.id) }
                contentItem: RowLayout {
                    spacing: 14
                    Image { source: backend.icon(modelData.icon); sourceSize: Qt.size(24, 24); Layout.preferredWidth: 24; Layout.preferredHeight: 24; Accessible.ignored: true }
                    ColumnLayout {
                        id: copy
                        Layout.fillWidth: true; spacing: 5
                        SettingsLabel { text: modelData.title; color: backend.foreground; font.pixelSize: SettingsStyle.fontPx(17); wrapMode: Text.Wrap; Layout.fillWidth: true }
                        SettingsLabel { text: modelData.detail; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                    SettingsLabel { text: "›"; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(24); Accessible.ignored: true }
                }
                background: Rectangle { radius: Math.min(backend.radius, width / 2, height / 2); color: parent.down ? SettingsStyle.fill("pressed") : SettingsStyle.fill("normal") }
            }
        }
    }
}
