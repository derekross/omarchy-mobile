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
    property int saved: 0   // the rate kept across restarts, 0 for none (then the device default, else the panel's own choice)
    property int deviceDefault: 0   // the device package's default rate when the panel lists it (husky: 60), 0 for none
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
        deviceDefault = r["default"] !== undefined ? r["default"] : 0
        if (rates.length <= 1) { status = qsTr("Tap a value; it applies at once."); return }
        status = qsTr("Tap a value; it applies at once. The refresh rate is kept across restarts.") + " "
               + (deviceDefault !== 0 ? qsTr("Default goes back to this phone's own choice (%1 Hz).").arg(deviceDefault)
                                      : qsTr("Default goes back to the screen's own choice."))
        if (saved !== 0 && saved !== refresh)
            status += " " + qsTr("Saved %1 Hz, now %2 Hz.").arg(saved).arg(refresh)
        else if (saved === 0 && deviceDefault !== 0 && deviceDefault !== refresh)
            status += " " + qsTr("Default %1 Hz, now %2 Hz.").arg(deviceDefault).arg(refresh)
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
