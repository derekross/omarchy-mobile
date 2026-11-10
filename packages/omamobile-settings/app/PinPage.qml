// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import "."
ColumnLayout {
    id: page
    spacing: 12
    property string status: qsTr("Digits only, 4 to 8 long.")
    property bool busy: false
    property int reqId: -1
    readonly property var digits: /^[0-9]{4,8}$/
    readonly property var currentDigits: /^[0-9]{1,64}$/
    readonly property bool ready: currentDigits.test(cur.text) && digits.test(next.text) && again.text === next.text && !busy
    function reset() { cur.text = ""; next.text = ""; again.text = "" }
    Connections {
        target: actions
        function onFinished(tool, r, id) {
            if (tool !== "pin" || id !== page.reqId) return
            page.busy = false
            page.reset()
            if (r.changed) { page.status = qsTr("The PIN was changed.") }
            else page.status = r.error ? r.error : qsTr("The PIN was not changed.")
        }
    }
    Component.onDestruction: page.reset()
    SettingsTextField { id: cur; Layout.fillWidth: true; Layout.preferredHeight: 52; placeholderText: qsTr("Current PIN"); echoMode: TextInput.Password; maximumLength: 64; inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData; color: backend.foreground; placeholderTextColor: backend.muted }
    SettingsTextField { id: next; Layout.fillWidth: true; Layout.preferredHeight: 52; placeholderText: qsTr("New PIN"); echoMode: TextInput.Password; maximumLength: 8; inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData; color: backend.foreground; placeholderTextColor: backend.muted }
    SettingsTextField { id: again; Layout.fillWidth: true; Layout.preferredHeight: 52; placeholderText: qsTr("New PIN again"); echoMode: TextInput.Password; maximumLength: 8; inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData; color: backend.foreground; placeholderTextColor: backend.muted }
    SettingsButton {
        Layout.fillWidth: true; text: qsTr("Change PIN"); enabled: page.ready
        onClicked: { page.busy = true; page.status = qsTr("Changing..."); page.reqId = actions.run("pin", ["change"], cur.text + "\n" + next.text + "\n" + again.text + "\n") }
    }
    SettingsLabel { text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
    Item { Layout.fillHeight: true }
}
