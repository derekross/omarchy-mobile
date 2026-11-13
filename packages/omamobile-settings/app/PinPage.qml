// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import "."
ColumnLayout {
    id: page
    spacing: 12
    readonly property string hint: qsTr("Digits only, 4 to 8 long. The PIN is also the sudo password.")
    property string status: qsTr("Checking this phone...")
    // The form is for a phone that unlocks with a PIN and has one; anything else gets a plain line.
    property bool allowed: false
    property bool busy: false
    property int statusId: -1
    // A result that came while the page was gone (the change finishes either way), shown once until a status arrives.
    property string note: ""
    readonly property var digits: /^[0-9]{4,8}$/
    readonly property var currentDigits: /^[0-9]{1,64}$/
    readonly property bool ready: currentDigits.test(cur.text) && digits.test(next.text) && again.text === next.text && !busy && allowed
    function reset() { cur.text = ""; next.text = ""; again.text = "" }
    function show(r) {
        if (r.changed) status = qsTr("The PIN was changed.")
        else status = r.error ? r.error : qsTr("The PIN was not changed.")
    }
    // Only a status that says "a PIN, and one is set" enables the form.
    function applyStatus(r) {
        allowed = false
        if (r.error) { status = r.error; return }
        if (r.hasPassword === false) { status = qsTr("This phone has no PIN yet. Set one in System, PIN."); return }
        if (r.type === "password") { status = qsTr("This phone unlocks with a password, not a PIN. Change it in System, PIN."); return }
        if (r.type !== "pin" || r.hasPassword !== true) { status = qsTr("Cannot tell how this phone unlocks."); return }
        allowed = true
        if (!busy && note === "") status = hint
    }
    Connections {
        target: actions
        function onFinished(tool, r, id, verb) {
            if (tool !== "pin") return
            actions.takeLastResult("pin", verb)
            if (verb === "status") { if (id === page.statusId) page.applyStatus(r); return }
            if (verb !== "change") return
            // the change: its own request, or the one that was still running when the page was opened again
            page.busy = false
            page.reset()
            page.note = ""
            page.show(r)
        }
    }
    Component.onCompleted: {
        statusId = actions.run("pin", ["status"])
        if (actions.pending("pin", "change")) { busy = true; status = qsTr("A PIN change is still running..."); return }
        const last = actions.takeLastResult("pin", "change")
        if (last.changed !== undefined || last.error !== undefined) { show(last); note = status }
    }
    Component.onDestruction: page.reset()
    SettingsTextField { id: cur; enabled: page.allowed && !page.busy; Layout.fillWidth: true; Layout.preferredHeight: 52; placeholderText: qsTr("Current PIN"); echoMode: TextInput.Password; maximumLength: 64; inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData; color: backend.foreground; placeholderTextColor: backend.muted }
    SettingsTextField { id: next; enabled: page.allowed && !page.busy; Layout.fillWidth: true; Layout.preferredHeight: 52; placeholderText: qsTr("New PIN"); echoMode: TextInput.Password; maximumLength: 8; inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData; color: backend.foreground; placeholderTextColor: backend.muted }
    SettingsTextField { id: again; enabled: page.allowed && !page.busy; Layout.fillWidth: true; Layout.preferredHeight: 52; placeholderText: qsTr("New PIN again"); echoMode: TextInput.Password; maximumLength: 8; inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData; color: backend.foreground; placeholderTextColor: backend.muted }
    SettingsButton {
        Layout.fillWidth: true; text: qsTr("Change PIN"); enabled: page.ready
        onClicked: { page.busy = true; page.status = qsTr("Changing..."); actions.run("pin", ["change"], cur.text + "\n" + next.text + "\n" + again.text + "\n") }
    }
    SettingsLabel { text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
    Item { Layout.fillHeight: true }
}
