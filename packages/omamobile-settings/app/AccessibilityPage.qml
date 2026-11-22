// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import "."
// Accessibility (backends/accessibility.sh): text size and animations through Omarchy's own commands. Each control shows only when its Omarchy command is there; the size and the animations state
// shown are the ones read back after each change.
ColumnLayout {
    id: page
    spacing: 14
    property bool textAvailable: false
    property int textSize: 0
    property bool animAvailable: false
    property string anim: ""          // "on", "off", or "" before the first read
    property string status: qsTr("Reading accessibility settings...")
    property bool busy: true
    property int reqId: -1
    readonly property var sizes: [{ v: 12, t: qsTr("Default") }, { v: 14, t: qsTr("Large") }, { v: 16, t: qsTr("Larger") }, { v: 18, t: qsTr("Largest") }]
    property bool failed: false   // a set error stays until the next user action; a refresh does not erase it
    function apply(r) {
        busy = false
        const wasSet = setting
        setting = false
        // an answer without state (the runner's own error, a kill) keeps the last known state on screen
        if (r.text !== undefined) {
            textAvailable = r.text.available === true
            textSize = textAvailable && typeof r.text.size === "number" ? r.text.size : 0
        }
        if (r.animations !== undefined) {
            animAvailable = r.animations.available === true
            anim = animAvailable && typeof r.animations.on === "boolean" ? (r.animations.on ? "on" : "off") : ""
        }
        if (r.error) { if (wasSet) failed = true; if (wasSet || !failed) status = r.error; return }
        if (!failed) status = !textAvailable && !animAvailable ? qsTr("Omarchy's text size and animation commands are not installed.") : ""
    }
    property bool setting: false
    function run(args) { failed = false; setting = true; busy = true; reqId = actions.run("accessibility", args) }
    function refresh() { if (!busy) {  // a refresh does not disable the buttons (only a set does)
        busy = true; reqId = actions.run("accessibility", ["get"]) } }
    Connections { target: actions; function onFinished(tool, r, id) { if (tool === "accessibility" && id === page.reqId) page.apply(r) } }
    Component.onCompleted: reqId = actions.run("accessibility", ["get"])
    // the Omarchy menu can change both while this page is open: read again every 5 s (only while shown)
    Timer { interval: 5000; repeat: true; running: page.visible && Qt.application.state === Qt.ApplicationActive; onTriggered: page.refresh() }
    SettingsLabel { visible: page.status !== ""; text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }

    SettingsLabel { visible: page.textAvailable; text: qsTr("Text size"); font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true }
    Flow {
        visible: page.textAvailable
        Layout.fillWidth: true; spacing: 8
        Repeater {
            model: page.sizes
            delegate: SettingsButton {
                required property var modelData
                text: modelData.t; highlighted: page.textSize === modelData.v; enabled: !page.setting
                onClicked: if (page.textSize !== modelData.v) page.run(["set", "text", String(modelData.v)])   // it also rewrites GTK and terminal sizes: never for the size already shown
            }
        }
    }
    SettingsLabel {
        visible: page.textAvailable
        text: (page.textSize === -1 ? qsTr("The size in shell.toml is set by hand and not one of these. ")
               : page.textSize > 0 && !page.sizes.some(s => s.v === page.textSize) ? qsTr("Now %1 px, set outside Settings. ").arg(page.textSize) : "")
              + qsTr("Text in the shell, GTK apps and terminals, through Omarchy's text size. An open foot terminal keeps its size until it is opened again. Settings itself keeps its own size.")
        color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    SettingsLabel { visible: page.animAvailable; text: qsTr("Animations"); font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true; Layout.topMargin: 8 }
    Flow {
        visible: page.animAvailable
        Layout.fillWidth: true; spacing: 8
        Repeater {
            model: [{ v: "on", t: qsTr("On") }, { v: "off", t: qsTr("Off") }]
            delegate: SettingsButton {
                required property var modelData
                text: modelData.t; highlighted: page.anim === modelData.v; enabled: !page.setting
                onClicked: if (page.anim !== modelData.v) page.run(["set", "animations", modelData.v])   // each set reloads Hyprland
            }
        }
    }
    SettingsLabel {
        visible: page.animAvailable
        text: qsTr("Off stops window and screen animations, blur and shadows (Omarchy's animations switch). The shell's own transitions are not changed.")
        color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    Item { Layout.fillHeight: true }
}
