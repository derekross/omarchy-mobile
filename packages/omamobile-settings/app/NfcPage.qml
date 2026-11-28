// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import "."
// Connected devices > NFC (backends/nfc.sh). On and Off go through omamobile-shell's omamobile-privacy@nfc-on|off
// units, as the NFC tile does, and both ask for the PIN. Off is total: the radio blocked, neard stopped, no polling.
// The tag sound is omamobile-nfc-chirp's, set in ~/.config/omamobile/nfc.json.
ColumnLayout {
    id: page
    spacing: 14
    property bool read: false
    property bool available: false
    property bool on: false
    property bool switchable: false
    property bool sound: true
    property bool custom: false
    property string status: qsTr("Reading NFC...")
    property bool busy: true
    property bool setting: false
    property int reqId: -1
    function apply(r) {
        busy = false
        const wasSet = setting
        setting = false
        // an answer without state (the runner's error) keeps the last known state on screen
        if (typeof r.available === "boolean") {
            read = true
            available = r.available; on = r.on === true; switchable = r.switchable === true
            sound = r.sound !== false; custom = r.custom === true
        }
        if (r.error) { status = r.error; return }
        status = !available ? qsTr("This phone has no NFC, or its driver hasn't started.") : ""
        if (wasSet && status === "") status = on ? qsTr("NFC is on.") : qsTr("NFC is off: the radio is blocked and nothing polls for tags.")
    }
    function run(args, waiting) { busy = true; setting = args[0] === "set"; status = waiting || ""; reqId = actions.run("nfc", args) }
    Connections { target: actions; function onFinished(tool, r, id) { if (tool === "nfc" && id === page.reqId) page.apply(r) } }
    Component.onCompleted: reqId = actions.run("nfc", ["get"])
    // the PIN can arrive after the page gave up waiting: read again whenever the page is shown
    onVisibleChanged: if (visible && !busy) run(["get"])

    FileDialog {
        id: picker
        title: qsTr("Choose a tag sound")
        nameFilters: [qsTr("Sounds (*.ogg *.oga *.opus *.wav *.flac)"), qsTr("All files (*)")]
        onAccepted: {
            const why = actions.stageSound(selectedFile)
            if (why !== "") { page.status = why; return }
            page.run(["sound", "import"], qsTr("Checking the sound..."))
        }
    }

    SettingsLabel { visible: page.status !== ""; text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }

    SettingsLabel { visible: page.available; text: qsTr("NFC"); font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true }
    Flow {
        visible: page.available && page.switchable
        Layout.fillWidth: true; spacing: 8
        SettingsButton { text: qsTr("On"); highlighted: page.on; enabled: !page.busy && !page.on; onClicked: page.run(["set", "nfc", "on"], qsTr("Enter your PIN to turn NFC on.")) }
        SettingsButton { text: qsTr("Off"); highlighted: !page.on; enabled: !page.busy && page.on; onClicked: page.run(["set", "nfc", "off"], qsTr("Enter your PIN to turn NFC off.")) }
    }
    SettingsLabel {
        visible: page.available
        text: !page.switchable ? qsTr("Switching NFC here needs a newer omamobile-shell.")
            : qsTr("Off turns NFC off totally: the radio is blocked, the NFC service stops, and it stays off after a restart. Both ways ask for your PIN.")
        color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    SettingsLabel { visible: page.read; text: qsTr("Play a sound when a tag is detected"); font.weight: Font.DemiBold; color: backend.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true }
    Flow {
        visible: page.read
        Layout.fillWidth: true; spacing: 8
        SettingsButton { text: qsTr("On"); highlighted: page.sound; enabled: !page.busy && !page.sound; onClicked: page.run(["sound", "on"]) }
        SettingsButton { text: qsTr("Off"); highlighted: !page.sound; enabled: !page.busy && page.sound; onClicked: page.run(["sound", "off"]) }
    }
    Flow {
        visible: page.read
        Layout.fillWidth: true; spacing: 8
        SettingsButton { text: qsTr("Choose sound…"); enabled: !page.busy; onClicked: picker.open() }
        SettingsButton { text: qsTr("Test sound"); enabled: !page.busy; onClicked: page.run(["sound", "test"]) }
        SettingsButton { visible: page.custom; text: qsTr("Built-in chirp"); enabled: !page.busy; onClicked: page.run(["sound", "default"]) }
    }
    SettingsLabel {
        visible: page.read
        text: (page.custom ? qsTr("Your own sound plays. ") : qsTr("The built-in chirp plays. "))
            + qsTr("A sound you choose must be 2 seconds or shorter; a copy is kept in ~/.config/omamobile/sounds. With the screen off the phone doesn't look for tags, so there is no sound.")
        color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    Item { Layout.fillHeight: true }
}
