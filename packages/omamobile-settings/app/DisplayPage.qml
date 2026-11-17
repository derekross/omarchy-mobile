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
    // Screen lock (backends/lock.sh): one timer locks and then turns the screen off
    property int lockAfter: -1
    property bool keyboardAwake: false
    property bool keyboard: false
    property bool lockBusy: true
    property int lockReq: -1
    property string lockError: ""
    readonly property var lockChoices: [{s: 30, t: qsTr("30 s")}, {s: 60, t: qsTr("1 min")}, {s: 120, t: qsTr("2 min")},
                                        {s: 180, t: qsTr("3 min")}, {s: 300, t: qsTr("5 min")}, {s: 0, t: qsTr("Never")}]
    function applyLock(r) {
        lockBusy = false
        if (r.error) { lockError = r.error; return }
        if (r.lock === undefined) { lockError = qsTr("The lock backend gave no values."); return }
        lockError = ""; lockAfter = r.lock; keyboardAwake = !!r.keyboardAwake; keyboard = !!r.keyboard
    }
    function apply(r) {
        busy = false
        if (r.error) { status = r.error; return }
        if (r.brightness === undefined || r.refresh === undefined) { status = qsTr("The display backend gave no values."); return }
        brightness = r.brightness; refresh = r.refresh; rates = r.rates || []
        status = rates.length > 1 ? qsTr("Tap a value; it applies at once. The refresh rate lasts until the phone is turned or the session restarts.")
                                  : qsTr("Tap a value; it applies at once.")
    }
    Connections {
        target: actions
        function onFinished(tool, r, id) {
            if (tool === "display" && id === page.reqId) page.apply(r)
            else if (tool === "lock" && id === page.lockReq) page.applyLock(r)
        }
    }
    Component.onCompleted: { reqId = actions.run("display", ["get"]); lockReq = actions.run("lock", ["get"]) }
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
    SettingsLabel { text: qsTr("Lock screen after"); font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true; Layout.topMargin: 8 }
    Flow {
        Layout.fillWidth: true; spacing: 8
        Repeater {
            model: page.lockChoices
            delegate: SettingsButton {
                required property var modelData
                text: modelData.t; highlighted: page.lockAfter === modelData.s; enabled: !page.lockBusy
                onClicked: { page.lockBusy = true; page.lockReq = actions.run("lock", ["set", "lock", String(modelData.s)]) }
            }
        }
    }
    SettingsLabel {
        text: page.lockError !== "" ? page.lockError
            : page.lockAfter === 0 ? qsTr("Never: the phone stays unlocked and the screen stays on until you press the power key. It also won't go to sleep by itself.")
            : qsTr("With no touch for this long the phone locks, and the screen turns off a few seconds later. Locking and screen off are the same timer.")
        color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    SettingsLabel { text: qsTr("Stay unlocked while a keyboard is connected"); font.weight: Font.DemiBold; color: backend.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.topMargin: 8 }
    Flow {
        Layout.fillWidth: true; spacing: 8
        Repeater {
            model: [{on: false, t: qsTr("Off")}, {on: true, t: qsTr("On")}]
            delegate: SettingsButton {
                required property var modelData
                text: modelData.t; highlighted: page.lockAfter >= 0 && page.keyboardAwake === modelData.on; enabled: !page.lockBusy
                onClicked: { page.lockBusy = true; page.lockReq = actions.run("lock", ["set", "keyboard", modelData.on ? "on" : "off"]) }
            }
        }
    }
    SettingsLabel {
        text: (page.keyboard ? qsTr("A keyboard is connected now. ") : qsTr("No keyboard is connected now. "))
              + qsTr("Any Bluetooth or USB keyboard counts. While one is connected the screen also stays on.")
        color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    Item { Layout.fillHeight: true }
}
