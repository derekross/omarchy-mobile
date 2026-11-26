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
    property int saved: 0   // the rate kept across restarts, 0 for none (the device default, 60 on husky, else the panel's own choice)
    property string status: qsTr("Reading the display...")
    property bool busy: true
    property int reqId: -1
    readonly property var levels: [10, 25, 50, 75, 100]
    function apply(r) {
        busy = false
        if (r.error) { status = r.error; return }
        if (r.brightness === undefined || r.refresh === undefined) { status = qsTr("The display backend gave no values."); return }
        brightness = r.brightness; refresh = r.refresh; rates = r.rates || []
        saved = r.saved !== undefined ? r.saved : 0
        status = rates.length > 1 ? qsTr("Tap a value; it applies at once. The refresh rate is kept across restarts. Default goes back to the device's own choice (60 Hz on this phone).")
                                  : qsTr("Tap a value; it applies at once.")
        if (rates.length > 1 && saved !== 0 && saved !== refresh)
            status += " " + qsTr("Saved %1 Hz, now %2 Hz.").arg(saved).arg(refresh)
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
        SettingsButton {
            text: qsTr("Default"); highlighted: page.saved === 0; enabled: !page.busy
            onClicked: { page.busy = true; page.reqId = actions.run("display", ["set", "refresh", "preferred"]) }
        }
        Repeater {
            model: page.rates
            delegate: SettingsButton {
                required property int modelData
                text: modelData + " Hz"; highlighted: page.saved === modelData; enabled: !page.busy
                onClicked: { page.busy = true; page.reqId = actions.run("display", ["set", "refresh", String(modelData)]) }
            }
        }
    }
    SettingsLabel { text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
    Item { Layout.fillHeight: true }
}
