// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import "."
ColumnLayout {
    id: page
    spacing: 14
    property int brightness: -1
    property int refresh: -1
    property var rates: []
    property string status: qsTr("Reading the display...")
    property bool busy: true
    property int reqId: -1
    readonly property var levels: [10, 25, 50, 75, 100]
    function apply(r) {
        busy = false
        if (r.error) { status = r.error; return }
        if (r.brightness === undefined || r.refresh === undefined) { status = qsTr("The display backend gave no values."); return }
        brightness = r.brightness; refresh = r.refresh; rates = r.rates || []
        status = rates.length > 1 ? qsTr("Tap a value; it applies at once. The refresh rate lasts until the phone is turned or the session restarts.")
                                  : qsTr("Tap a value; it applies at once.")
    }
    Connections { target: actions; function onFinished(tool, r, id) { if (tool === "display" && id === page.reqId) page.apply(r) } }
    Component.onCompleted: reqId = actions.run("display", ["get"])
    SettingsLabel { text: qsTr("Brightness"); font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true }
    Flow {
        Layout.fillWidth: true; spacing: 8
        Repeater {
            model: page.levels
            delegate: SettingsButton {
                required property int modelData
                text: modelData + "%"; highlighted: page.brightness === modelData; enabled: !page.busy
                onClicked: { page.busy = true; page.reqId = actions.run("display", ["set", "brightness", String(modelData)]) }
            }
        }
    }
    SettingsLabel {
        visible: page.rates.length > 1
        text: qsTr("Refresh rate"); font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true; Layout.topMargin: 8
    }
    Flow {
        visible: page.rates.length > 1
        Layout.fillWidth: true; spacing: 8
        Repeater {
            model: page.rates
            delegate: SettingsButton {
                required property int modelData
                text: modelData + " Hz"; highlighted: page.refresh === modelData; enabled: !page.busy
                onClicked: { page.busy = true; page.reqId = actions.run("display", ["set", "refresh", String(modelData)]) }
            }
        }
    }
    SettingsLabel { text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
    Item { Layout.fillHeight: true }
}
