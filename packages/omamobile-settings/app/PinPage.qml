// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import "."
ColumnLayout {
    id: page
    spacing: 12
    readonly property string hint: qsTr("Digits only, 4 to 8 long. The PIN is also the sudo password.")
    // What the page says: what it knows about the phone (baseText), the outcome of the last change (resultText: a
    // change that finished while the page was gone is shown once), and while a change runs only that.
    property string baseText: qsTr("Checking this phone...")
    property string resultText: ""
    property string busyText: ""
    readonly property string statusText: busy ? busyText : (resultText === "" ? baseText : (allowed ? resultText : resultText + " " + baseText))
    // The form is for a phone that unlocks with a PIN and has one; anything else gets a plain line.
    property bool allowed: false
    property bool busy: false
    property int statusId: -1
    readonly property var digits: /^[0-9]{4,8}$/
    readonly property var currentDigits: /^[0-9]{1,64}$/
    readonly property bool ready: currentDigits.test(cur.text) && digits.test(next.text) && again.text === next.text && !busy && allowed
    function reset() { cur.text = ""; next.text = ""; again.text = "" }
    function show(r) {
        if (r.changed) resultText = qsTr("The PIN was changed.")
        else resultText = r.error ? r.error : qsTr("The PIN was not changed.")
    }
    // Only a status that says "a PIN, and one is set" enables the form.
    function applyStatus(r) {
        allowed = false
        if (r.error) { baseText = r.error; return }
        if (r.hasPassword === false) { baseText = qsTr("This phone has no PIN yet. Set one in System, PIN."); return }
        if (r.type === "password") { baseText = qsTr("This phone unlocks with a password, not a PIN. Change it in System, PIN."); return }
        if (r.type !== "pin" || r.hasPassword !== true) { baseText = qsTr("Cannot tell how this phone unlocks."); return }
        allowed = true
        baseText = hint
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
            page.show(r)
        }
    }
    Component.onCompleted: {
        statusId = actions.run("pin", ["status"])
        if (actions.pending("pin", "change")) { busy = true; busyText = qsTr("A PIN change is still running..."); return }
        const last = actions.takeLastResult("pin", "change")
        if (last.changed !== undefined || last.error !== undefined) show(last)
    }
    Component.onDestruction: page.reset()
    SettingsTextField { id: cur; enabled: page.allowed && !page.busy; Layout.fillWidth: true; Layout.preferredHeight: 52; placeholderText: qsTr("Current PIN"); echoMode: TextInput.Password; maximumLength: 64; inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData; color: backend.foreground; placeholderTextColor: backend.muted }
    SettingsTextField { id: next; enabled: page.allowed && !page.busy; Layout.fillWidth: true; Layout.preferredHeight: 52; placeholderText: qsTr("New PIN"); echoMode: TextInput.Password; maximumLength: 8; inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData; color: backend.foreground; placeholderTextColor: backend.muted }
    SettingsTextField { id: again; enabled: page.allowed && !page.busy; Layout.fillWidth: true; Layout.preferredHeight: 52; placeholderText: qsTr("New PIN again"); echoMode: TextInput.Password; maximumLength: 8; inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData; color: backend.foreground; placeholderTextColor: backend.muted }
    SettingsButton {
        Layout.fillWidth: true; text: qsTr("Change PIN"); enabled: page.ready
        onClicked: { page.resultText = ""; page.busyText = qsTr("Changing..."); page.busy = true; actions.run("pin", ["change"], cur.text + "\n" + next.text + "\n" + again.text + "\n") }
    }
    SettingsLabel { text: page.statusText; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
    Item { Layout.fillHeight: true }
}
