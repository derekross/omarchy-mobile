// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import "."
ColumnLayout {
    id: page
    spacing: 14
    property int limit: -1
    property bool available: false
    property string status: qsTr("Reading the charger...")
    property bool busy: true
    property int reqId: -1
    readonly property var levels: [80, 85, 90, 95, 100]
    function apply(r) {
        busy = false
        if (r.error) { status = r.error; return }
        available = r.available === true
        if (!available) { status = qsTr("Settings cannot set a charge limit on this phone."); return }
        if (r.limit === undefined) { status = qsTr("The charger backend gave no value."); return }
        limit = r.limit
        status = qsTr("Stops charging at this level; it resumes 5 % lower. 100 % charges fully.")
    }
    Connections { target: actions; function onFinished(tool, r, id) { if (tool === "charge" && id === page.reqId) page.apply(r) } }
    Component.onCompleted: reqId = actions.run("charge", ["get"])
    SettingsLabel {
        visible: page.available
        text: page.limit > 0 ? qsTr("Charge limit: %1 %").arg(page.limit) : qsTr("Charge limit")
        font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true
    }
    Flow {
        visible: page.available
        Layout.fillWidth: true; spacing: 8
        Repeater {
            model: page.levels
            delegate: SettingsButton {
                required property int modelData
                text: modelData + "%"; highlighted: page.limit === modelData; enabled: !page.busy
                onClicked: { page.busy = true; page.reqId = actions.run("charge", ["set", "limit", String(modelData)]) }
            }
        }
    }
    SettingsLabel { text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
    Item { Layout.fillHeight: true }
}
