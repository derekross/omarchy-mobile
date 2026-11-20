// SPDX-License-Identifier: MIT
// The install link's code window (docs/INSTALL-LINK-PLAN.md §2.8): the
// pairing code the owner types into the installer, shown after a tap on the
// setup notice, for its valid time or until it is closed. Started by
// omamobile-install-link-agent with `qs -n -p` on this directory; the code
// arrives in the environment (OMAMOBILE_LINK_CODE), never on a command line
// or in a file. Quitting (Close, or the code's time running out) is how the
// agent learns the window was closed.
//
// The look is plain Qt Quick for now: Omarchy's shell modules (qs.Commons)
// are the shell's own and are not on a standalone config's import path.
// Moving it into an omamobile.* shell plugin, so it follows the theme as the
// rest of the phone does, is open (the plan's §19).
import QtQuick
import Quickshell

ShellRoot {
    id: root
    readonly property string code: Quickshell.env("OMAMOBILE_LINK_CODE") || ""
    readonly property int validS: parseInt(Quickshell.env("OMAMOBILE_LINK_VALID_S") || "600")

    Timer {
        interval: Math.max(1, root.validS) * 1000
        running: true
        onTriggered: Qt.quit()
    }

    FloatingWindow {
        title: "Phone setup"
        visible: root.code.length > 0
        implicitWidth: 420
        implicitHeight: 300
        color: "#1f1f1f"

        Column {
            anchors.centerIn: parent
            spacing: 18
            width: parent.width - 48

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: "#f2f2f2"
                font.pixelSize: 18
                text: "Type this code into the installer on your computer"
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                color: "#f2f2f2"
                font.pixelSize: 44
                font.family: "monospace"
                font.letterSpacing: 4
                // Two groups of three, as the installer asks for it
                text: root.code.slice(0, 3) + " " + root.code.slice(3)
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 160
                height: 48
                radius: 6
                color: "#3a3a3a"
                Text {
                    anchors.centerIn: parent
                    color: "#f2f2f2"
                    font.pixelSize: 18
                    text: "Close"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.quit()
                }
            }
        }
    }
}
