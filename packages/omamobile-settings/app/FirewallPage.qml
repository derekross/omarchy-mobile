// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import "."
// Firewall & SSH (backends/security.sh). The firewall is UFW, switched by a root helper the polkit rule lets the user
// start; turning it off asks first. SSH is shown, never switched: USB SSH is the same sshd, and a switch here could
// take away the only way into a phone under development.
// Microphone and camera access (backends/privacy.sh): off totally through omamobile-shell's privacy units, the PIN
// both ways. Off is a block no app can undo (the capture nodes become root's), not a mute.
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
    function run(args) { confirming = false; setting = true; busy = true; status = qsTr("Enter your PIN to change the firewall."); reqId = actions.run("security", args) }
    Connections {
        target: actions
        function onFinished(tool, r, id) {
            if (tool === "security" && id === page.reqId) page.apply(r)
            else if (tool === "privacy" && id === page.privReqId) page.applyPrivacy(r)
        }
    }
    Component.onCompleted: { reqId = actions.run("security", ["get"]); privReqId = actions.run("privacy", ["get"]) }

    property bool privSwitchable: false
    property string mic: ""           // "on", "off", or "" before the first read (or without omamobile-shell's switch)
    property string camera: ""
    property int cameras: 0           // camera devices the kernel has now (the video codec is not one)
    property string privStatus: ""
    property bool privSetting: false
    property bool privRead: false     // a privacy answer (or error) has come back
    property int privReqId: -1
    function applyPrivacy(r) {
        privRead = true
        const wasSet = privSetting
        privSetting = false
        if (typeof r.mic === "string") {
            privSwitchable = r.switchable === true
            mic = privSwitchable ? r.mic : ""
            camera = privSwitchable ? r.camera : ""
            cameras = typeof r.cameras === "number" ? r.cameras : 0
        }
        if (r.error) { privStatus = r.error; return }
        privStatus = wasSet ? qsTr("Microphone access: %1. Camera access: %2.").arg(mic === "on" ? qsTr("on") : qsTr("off")).arg(camera === "on" ? qsTr("on") : qsTr("off")) : ""
    }
    function setPrivacy(kind, on) { privSetting = true; privStatus = qsTr("Enter your PIN to change it."); privReqId = actions.run("privacy", ["set", kind, on ? "on" : "off"]) }
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

    SettingsLabel { visible: page.mic !== ""; text: qsTr("Microphone access"); font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true; Layout.topMargin: 8 }
    Flow {
        visible: page.mic !== ""
        Layout.fillWidth: true; spacing: 8
        SettingsButton { text: qsTr("On"); highlighted: page.mic === "on"; enabled: !page.privSetting && page.mic !== "on"; onClicked: page.setPrivacy("mic", true) }
        SettingsButton { text: qsTr("Off"); highlighted: page.mic === "off"; enabled: !page.privSetting && page.mic !== "off"; onClicked: page.setPrivacy("mic", false) }
    }
    SettingsLabel {
        visible: page.mic !== ""
        text: qsTr("Off blocks every app from every microphone wired to the phone (built-in, USB and dock), and stops an app that is still recording. The speakers keep working. Bluetooth headset microphones are only hidden through the audio server (headsets get music, not calls): best effort, not a block. Both ways ask for your PIN.")
        color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    SettingsLabel { visible: page.camera !== ""; text: qsTr("Camera access"); font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true; Layout.topMargin: 8 }
    Flow {
        visible: page.camera !== ""
        Layout.fillWidth: true; spacing: 8
        SettingsButton { text: qsTr("On"); highlighted: page.camera === "on"; enabled: !page.privSetting && page.camera !== "on"; onClicked: page.setPrivacy("camera", true) }
        SettingsButton { text: qsTr("Off"); highlighted: page.camera === "off"; enabled: !page.privSetting && page.camera !== "off"; onClicked: page.setPrivacy("camera", false) }
    }
    SettingsLabel {
        visible: page.camera !== ""
        text: (page.cameras === 0 ? qsTr("No camera works on this phone yet: the switch is kept, and enforced as soon as camera drivers land. ") : "")
              + qsTr("Off blocks every app from every camera. Video playback (the video decoder) is not affected. Both ways ask for your PIN.")
        color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    SettingsLabel { visible: page.privStatus !== ""; text: page.privStatus; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }

    Item { Layout.fillHeight: true }
}
