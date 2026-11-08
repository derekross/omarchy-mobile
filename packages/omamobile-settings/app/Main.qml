// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Marsel Nenaj
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Window
ApplicationWindow {
    id: window
    width: Math.min(420, Screen.width)
    height: Math.min(880, Screen.height)
    visible: true
    title: backend.title
    color: backend.background
    Material.theme: (backend.background.r * .2126 + backend.background.g * .7152 + backend.background.b * .0722) > .5 ? Material.Light : Material.Dark
    Material.accent: backend.accent
    Material.background: backend.background
    Material.foreground: backend.foreground
    function goBack() {
        search.focus = false
        Qt.inputMethod.hide()
        if (backend.searching) search.clear()
        backend.back()
    }
    readonly property bool showingAbout: backend.page === "about" && !backend.searching
    Connections {
        target: backend
        function onCloseRequested() { window.close() }
        function onRaiseRequested() { window.show(); window.raise(); window.requestActivate() }
        function onPageChanged() { search.text = ""; search.focus = false; Qt.inputMethod.hide(); if (backend.page === "about") deviceInfo.refresh() }
    }
    Component.onCompleted: if (backend.page === "about") deviceInfo.refresh()
    Shortcut { sequence: "Escape"; onActivated: window.goBack() }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 20
        spacing: 18
        Button {
            visible: backend.page !== "root" || backend.searching
            Layout.preferredHeight: 52
            leftPadding: 0; rightPadding: 12
            onClicked: window.goBack()
            contentItem: Row {
                spacing: 4
                Label { text: "‹"; font.pixelSize: 30; color: backend.foreground }
                Label { text: qsTr("Back"); font.pixelSize: 17; color: backend.foreground; anchors.verticalCenter: parent.verticalCenter }
            }
            background: Rectangle { color: parent.down ? Qt.rgba(backend.foreground.r, backend.foreground.g, backend.foreground.b, 0.06) : "transparent"; radius: Math.min(backend.radius, width / 2, height / 2) }
        }
        Label { text: backend.title; Layout.fillWidth: true; color: backend.foreground; font.pixelSize: 30; font.weight: Font.DemiBold; wrapMode: Text.Wrap }
        TextField {
            id: search
            objectName: "settingsSearch"
            Layout.fillWidth: true; Layout.preferredHeight: 52
            visible: !window.showingAbout
            placeholderText: qsTr("Search settings")
            color: backend.foreground; placeholderTextColor: backend.muted
            onTextEdited: backend.search(text)
            background: Rectangle { radius: Math.min(backend.radius, width / 2, height / 2); color: Qt.rgba(backend.foreground.r, backend.foreground.g, backend.foreground.b, 0.06) }
        }
        AboutPage { visible: window.showingAbout; Layout.fillWidth: true; Layout.fillHeight: true; controller: deviceInfo; colors: backend }
        ListView {
            id: list
            visible: !window.showingAbout
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; model: backend.rows
            delegate: ItemDelegate {
                required property var modelData
                width: list.width; implicitHeight: Math.max(80, copy.implicitHeight + 28)
                onClicked: { search.focus = false; Qt.inputMethod.hide(); backend.activate(modelData.id) }
                contentItem: RowLayout {
                    spacing: 14
                    Image { source: backend.icon(modelData.icon); sourceSize: Qt.size(24, 24); Layout.preferredWidth: 24; Layout.preferredHeight: 24; Accessible.ignored: true }
                    ColumnLayout {
                        id: copy
                        Layout.fillWidth: true; spacing: 5
                        Label { text: modelData.title; color: backend.foreground; font.pixelSize: 17; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Label { text: modelData.detail; color: backend.muted; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                    Label { text: "›"; color: backend.muted; font.pixelSize: 24; Accessible.ignored: true }
                }
                background: Rectangle { radius: Math.min(backend.radius, width / 2, height / 2); color: parent.down ? Qt.rgba(backend.accent.r, backend.accent.g, backend.accent.b, 0.10) : Qt.rgba(backend.foreground.r, backend.foreground.g, backend.foreground.b, 0.045) }
            }
        }
    }
}
