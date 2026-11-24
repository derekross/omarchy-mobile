// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import "."
// Notifications: lock screen and history (backends/notifications.sh). Hide text is Omarchy's
// lock-hide-notification-text toggle; Clear forgets every stored notification through the notification service's own
// forget call. Each part shows only when the backend says it works on this phone; what is shown is read back.
ColumnLayout {
    id: page
    spacing: 14
    property bool lockAvailable: false
    property string hide: ""          // "on", "off", or "" before the first read
    property bool keypad: false
    property bool histAvailable: false
    property int count: -1
    property bool confirming: false
    onVisibleChanged: if (!visible) confirming = false
    property string status: qsTr("Reading notification settings...")
    property bool busy: true
    property bool setting: false
    property int reqId: -1
    property bool failed: false   // a set error stays until the next user action; a refresh does not erase it
    property string action: ""    // the verb of the running or last user action (set, clear)
    property string failedAction: ""
    property bool failedStillStored: false   // the failure was "still stored", which a count of 0 later makes stale
    function apply(r) {
        busy = false
        const wasSet = setting
        setting = false
        // an answer without state (the runner's own error, a kill) keeps the last known state on screen
        if (r.lock !== undefined) {
            lockAvailable = r.lock.available === true
            hide = lockAvailable && typeof r.lock.hide === "boolean" ? (r.lock.hide ? "on" : "off") : ""
            keypad = r.lock.keypad === true
        }
        if (r.history !== undefined) {
            histAvailable = r.history.available === true
            const c = histAvailable && typeof r.history.count === "number" ? r.history.count : -1
            if (c !== count) confirming = false   // never leave "Clear, cannot be undone" armed over a different list
            // nothing stored any more: an old clear error no longer holds (a lock screen error still does)
            if (c === 0 && !wasSet && failedAction === "clear" && failedStillStored) failed = false
            count = c
        }
        const e = r.error || (r.history && r.history.error) || ""
        if (e) { if (wasSet) { failed = true; failedAction = action; failedStillStored = r.still_stored === true } if (wasSet || !failed) status = e; return }
        if (!failed) status = !lockAvailable && !histAvailable ? qsTr("The notification service and the lock screen setting are not available.") : ""
    }
    function run(args) {
        failed = false; failedAction = ""; failedStillStored = false; confirming = false; setting = true; busy = true; action = args[0]
        if (action === "clear") status = qsTr("Clearing notifications...")
        reqId = actions.run("notifications", args)
    }
    function refresh() { if (!busy) { busy = true; reqId = actions.run("notifications", ["get"]) } }
    Connections { target: actions; function onFinished(tool, r, id) { if (tool === "notifications" && id === page.reqId) page.apply(r) } }
    Component.onCompleted: reqId = actions.run("notifications", ["get"])
    // notifications arrive while the page is open: read again every 5 s (only while shown)
    Timer { interval: 5000; repeat: true; running: page.visible && Qt.application.state === Qt.ApplicationActive; onTriggered: page.refresh() }
    SettingsLabel { visible: page.status !== ""; text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }

    SettingsLabel { visible: page.lockAvailable; text: qsTr("Hide notification text on the lock screen"); font.weight: Font.DemiBold; color: backend.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true }
    Flow {
        visible: page.lockAvailable
        Layout.fillWidth: true; spacing: 8
        Repeater {
            model: [{ v: "on", t: qsTr("Hide") }, { v: "off", t: qsTr("Show") }]
            delegate: SettingsButton {
                required property var modelData
                text: modelData.t; highlighted: page.hide === modelData.v; enabled: !page.setting
                onClicked: if (page.hide !== modelData.v) page.run(["set", "lockhide", modelData.v])
            }
        }
    }
    SettingsLabel {
        visible: page.lockAvailable
        text: qsTr("Hide shows only the app name and \"Unlock to read\", and no track title in the lock screen's media controls.")
              + (page.keypad ? "" : " " + qsTr("The lock screen shows notifications only with the keypad lock, which is off now."))
        color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    SettingsLabel { visible: page.histAvailable; text: qsTr("Notification history"); font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true; Layout.topMargin: 8 }
    SettingsLabel {
        visible: page.histAvailable && page.count >= 0
        text: page.count === 0 ? qsTr("No notifications are stored.") : page.count === 1 ? qsTr("1 notification stored (on screen and in history).") : qsTr("%1 notifications stored (on screen and in history).").arg(page.count)
        color: backend.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    Flow {
        visible: page.histAvailable && page.count > 0
        Layout.fillWidth: true; spacing: 8
        SettingsButton { visible: !page.confirming; text: qsTr("Clear all"); enabled: !page.setting; onClicked: page.confirming = true }
        SettingsButton { visible: page.confirming; text: qsTr("Clear, cannot be undone"); highlighted: true; enabled: !page.setting; onClicked: page.run(["clear"]) }
        SettingsButton { visible: page.confirming; text: qsTr("Cancel"); onClicked: page.confirming = false }
    }
    SettingsLabel {
        visible: page.histAvailable
        text: qsTr("Clear removes them from the screen, the notification shade, the lock screen and the history. Nothing in them is opened or run.")
        color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    Item { Layout.fillHeight: true }
}
