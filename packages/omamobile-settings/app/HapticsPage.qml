// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import "."
ColumnLayout {
    id: page
    spacing: 14
    property string level: ""
    property string status: qsTr("Reading the haptics...")
    property bool busy: true
    // True once the theme has been read: a phone without the keyboard haptics theme gets no buttons.
    property bool available: false
    property int reqId: -1
    readonly property var levels: [
        { id: "low", label: qsTr("Low"), hint: qsTr("one light tick") },
        { id: "medium", label: qsTr("Medium"), hint: qsTr("tick, then a short gap") },
        { id: "high", label: qsTr("High"), hint: qsTr("stronger tick, then a short gap") }
    ]
    function apply(r) {
        busy = false
        if (r.error) { status = r.error; return }
        if (!r.level) { status = qsTr("The haptics backend gave no level."); return }
        available = true
        level = r.level
        status = qsTr("Keyboard tick: %1. Tap a level; it applies at once. Changing it restarts the feedback service, so a ring in progress stops.").arg(level)
    }
    Connections { target: actions; function onFinished(tool, r, id) { if (tool === "haptics" && id === page.reqId) page.apply(r) } }
    Component.onCompleted: reqId = actions.run("haptics", ["get"])
    // Leaving the page drops what was typed; nothing here is ever saved.
    Component.onDestruction: { tryField.clear(); if (tryField.activeFocus) Qt.inputMethod.hide() }
    Repeater {
        model: page.levels
        delegate: SettingsButton {
            required property var modelData
            Layout.fillWidth: true; Layout.preferredHeight: 64
            visible: page.available
            // No focus on tap, so the try field keeps the keyboard up while levels are compared.
            focusPolicy: Qt.NoFocus
            highlighted: page.level === modelData.id; enabled: page.available && !page.busy
            onClicked: { page.busy = true; page.reqId = actions.run("haptics", ["set", "level", modelData.id]) }
            contentItem: Column {
                spacing: 2
                SettingsLabel { text: modelData.label; color: backend.foreground; width: parent.width }
                SettingsLabel { text: modelData.hint; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(12); width: parent.width; wrapMode: Text.Wrap }
            }
        }
    }
    SettingsTextField {
        id: tryField
        objectName: "hapticsTryField"
        Layout.fillWidth: true; Layout.preferredHeight: 52
        visible: page.available
        placeholderText: qsTr("Try it here: type to feel the ticks")
        color: backend.foreground; placeholderTextColor: backend.muted
        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
        background: Rectangle { radius: Math.min(backend.radius, width / 2, height / 2); color: SettingsStyle.fill("normal") }
        onVisibleChanged: if (!visible) clear()
    }
    SettingsLabel { text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
    Item { Layout.fillHeight: true }
}
