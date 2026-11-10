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
    property int reqId: -1
    readonly property var levels: [
        { id: "off", label: qsTr("Silent, whole phone"), hint: qsTr("no vibration from any app, lock screen too") },
        { id: "low", label: qsTr("Low"), hint: qsTr("keyboard tick, gentlest") },
        { id: "medium", label: qsTr("Medium"), hint: qsTr("keyboard tick") },
        { id: "high", label: qsTr("High"), hint: qsTr("keyboard tick, strongest") }
    ]
    function apply(r) {
        busy = false
        if (r.error) { status = r.error; return }
        if (!r.level) { status = qsTr("The haptics backend gave no level."); return }
        level = r.level
        status = level === "off" ? qsTr("Haptics are silent for the whole phone. Pick a level to turn them back on.")
                                 : qsTr("Keyboard tick: %1. Tap a level; it applies at once.").arg(level)
    }
    Connections { target: actions; function onFinished(tool, r, id) { if (tool === "haptics" && id === page.reqId) page.apply(r) } }
    Component.onCompleted: reqId = actions.run("haptics", ["get"])
    Repeater {
        model: page.levels
        delegate: SettingsButton {
            required property var modelData
            Layout.fillWidth: true; Layout.preferredHeight: 64
            highlighted: page.level === modelData.id; enabled: !page.busy
            onClicked: { page.busy = true; page.reqId = actions.run("haptics", ["set", "level", modelData.id]) }
            contentItem: Column {
                spacing: 2
                SettingsLabel { text: modelData.label; color: backend.foreground; width: parent.width }
                SettingsLabel { text: modelData.hint; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(12); width: parent.width; wrapMode: Text.Wrap }
            }
        }
    }
    SettingsLabel { text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
    Item { Layout.fillHeight: true }
}
