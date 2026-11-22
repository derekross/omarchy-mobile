// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import "."
// Firewall & SSH (backends/security.sh). The firewall is UFW, switched by a root helper the polkit rule lets the user
// start; turning it off asks first. SSH is shown, never switched: USB SSH is the same sshd, and a switch here could
// take away the only way into a phone under development.
ColumnLayout {
    id: page
    spacing: 14
    property string firewall: ""      // "on", "off", "not installed", "unknown", or "" before the first read
    property string sshActive: ""
    property string sshEnabled: ""
    property var sshAllowed: []
    property bool canEnable: false
    property string why: ""
    property bool confirming: false
    onVisibleChanged: if (!visible) confirming = false
    property string status: qsTr("Reading the firewall...")
    property bool busy: true
    property bool setting: false
    property int reqId: -1
    function apply(r) {
        busy = false
        const wasSet = setting
        setting = false
        confirming = false
        // an answer without state (the backend's or the runner's error) keeps the last known state on screen
        if (typeof r.firewall === "string") {
            firewall = r.firewall
            sshActive = typeof r.ssh_active === "string" ? r.ssh_active : ""
            sshEnabled = typeof r.ssh_enabled === "string" ? r.ssh_enabled : ""
            sshAllowed = r.ssh_allowed && r.ssh_allowed.length !== undefined ? r.ssh_allowed : []
            canEnable = r.can_enable === true
            why = typeof r.why === "string" ? r.why : ""
        }
        if (r.error) { status = r.error; return }
        status = firewall === "not installed" ? qsTr("UFW is not installed, so there is no firewall to switch.")
               : firewall === "unknown" ? qsTr("The firewall state could not be read.") : ""
        if (wasSet && status === "") status = firewall === "on" ? qsTr("The firewall is on.") : qsTr("The firewall is off.")
    }
    function run(args) { confirming = false; setting = true; busy = true; reqId = actions.run("security", args) }
    Connections { target: actions; function onFinished(tool, r, id) { if (tool === "security" && id === page.reqId) page.apply(r) } }
    Component.onCompleted: reqId = actions.run("security", ["get"])
    SettingsLabel { visible: page.status !== ""; text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }

    SettingsLabel { visible: page.firewall === "on" || page.firewall === "off"; text: qsTr("Firewall"); font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true }
    Flow {
        visible: page.firewall === "on" || page.firewall === "off"
        Layout.fillWidth: true; spacing: 8
        SettingsButton { text: qsTr("On"); highlighted: page.firewall === "on"; enabled: !page.setting && page.firewall !== "on" && page.canEnable; onClicked: page.run(["set", "firewall", "on"]) }
        SettingsButton { visible: !page.confirming; text: qsTr("Off"); highlighted: page.firewall === "off"; enabled: !page.setting && page.firewall !== "off"; onClicked: page.confirming = true }
        SettingsButton { visible: page.confirming; text: qsTr("Turn off, stays off after restart"); highlighted: true; enabled: !page.setting; onClicked: page.run(["set", "firewall", "off"]) }
        SettingsButton { visible: page.confirming; text: qsTr("Cancel"); onClicked: page.confirming = false }
    }
    SettingsLabel {
        visible: page.firewall === "on" || page.firewall === "off"
        text: (page.firewall === "off" && !page.canEnable && page.why !== "" ? page.why + " " : "")
              + qsTr("On blocks incoming connections except the ones a rule allows; outgoing traffic is not limited. Rules are not changed here.")
        color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    SettingsLabel { visible: page.firewall !== ""; text: qsTr("SSH server"); font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true; Layout.topMargin: 8 }
    SettingsLabel {
        visible: page.firewall !== ""
        text: (page.sshActive === "active" ? qsTr("Running") : page.sshActive === "inactive" ? qsTr("Not running") : qsTr("State: %1").arg(page.sshActive || qsTr("unknown")))
              + ", " + (page.sshEnabled === "enabled" ? qsTr("starts at boot") : page.sshEnabled === "disabled" ? qsTr("does not start at boot") : qsTr("start at boot: %1").arg(page.sshEnabled || qsTr("unknown")))
        color: backend.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    SettingsLabel {
        visible: page.firewall === "on" || page.firewall === "off"
        text: (page.sshAllowed.length > 0 ? qsTr("Firewall lets SSH in on: %1.").arg(page.sshAllowed.join(", ")) : qsTr("No firewall rule lets SSH in."))
              + (page.firewall === "off" && page.sshActive === "active" ? " " + qsTr("With the firewall on, SSH from anywhere else is blocked.") : "")
        color: backend.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    SettingsLabel {
        visible: page.firewall !== ""
        text: qsTr("SSH is shown here, not switched: SSH over USB is the same server, and turning it off could leave no way into the phone. Use a terminal to change it.")
        color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    Item { Layout.fillHeight: true }
}
