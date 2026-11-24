// SPDX-License-Identifier: MIT
// Apps: the apps the app drawer shows (the same desktop entries and filters), and one app's detail: its package,
// version and installed size from pacman (read-only), Open, then Manage (appmgr.sh): battery policy (Unrestricted /
// Optimized / Restricted, read by Doze) and Stop for this session. The list loads only when this page opens: the saved
// list shows at once, a fresh scan (nice 10, idle I/O) replaces it. Uninstalling is not offered (see the note).
import QtQuick
import QtQuick.Layouts
import "."
ColumnLayout {
    id: page
    objectName: "appsPage"
    spacing: 12
    property var apps: []
    property bool scanning: true
    property bool freshOk: false         // the fresh scan answered with a list (a saved list arriving later is then ignored)
    property string status: qsTr("Reading the installed apps...")
    property int listReq: -1
    property int cachedReq: -1
    property var app: null               // the open app's list entry, null for the list
    property var info: ({})
    property bool infoBusy: false
    property string infoStatus: ""
    property int infoReq: -1
    property int openReq: -1
    property bool partial: false
    property var mgr: ({})               // appmgr.sh state for the open app
    property bool mgrBusy: false
    property string mgrStatus: ""
    property int mgrReq: -1
    property int actReq: -1
    property bool policyBusy: false     // one policy write at a time: a later tap must not lose to a slower earlier one
    readonly property bool canGoBack: app !== null
    function goBack() { app = null; info = ({}); infoStatus = ""; infoReq = -1; openReq = -1; mgr = ({}); mgrStatus = ""; mgrReq = -1; actReq = -1; policyBusy = false }
    function loadMgr() { mgrBusy = true; mgrReq = actions.run("appmgr", ["state", app.id]) }
    function policyText(p) {
        return p === "unrestricted" ? qsTr("Unrestricted: never frozen, also with the screen off")
             : p === "restricted" ? qsTr("Restricted: frozen as soon as the screen is off and the phone is locked")
             : qsTr("Optimized: frozen when the phone dozes (default)")
    }
    function iconSource(name) {
        const n = String(name || "")
        // encodeURI leaves # and ? alone, and a URL would cut the path there
        if (n.charAt(0) === "/") return "file://" + encodeURI(n).replace(/#/g, "%23").replace(/\?/g, "%3F")
        // a theme name is one path segment of the image URL: encoded, so # ? / % stay in the name (the provider decodes it)
        return "image://appicon/" + encodeURIComponent(n === "" ? "application-x-executable" : n)
    }
    function showApp(entry) {
        // a late answer for the previous app (its info or open) must not land on this one
        app = entry; info = ({}); infoStatus = ""; infoBusy = false; infoReq = -1; openReq = -1
        mgr = ({}); mgrStatus = ""; mgrReq = -1; actReq = -1; policyBusy = false
        if (entry.open === false) { infoStatus = qsTr("Settings cannot show or open this app: its ID (%1) has characters Settings does not accept. Open it from the app drawer.").arg(entry.id); return }
        infoBusy = true
        infoReq = actions.run("apps", ["info", entry.id])
        loadMgr()
    }
    function applyList(r, fresh) {
        if (fresh) scanning = false
        if (r.error) { if (fresh) status = apps.length ? "" : r.error; return }
        // r.apps arrives as a converted list, not always a JS Array: copy it
        const list = r.apps
        if (!list || typeof list.length !== "number") { if (fresh) status = apps.length ? "" : qsTr("Settings could not read the installed apps."); return }
        if (!fresh && freshOk) return
        if (fresh) freshOk = true
        const next = []
        for (let i = 0; i < list.length; i++) if (list[i] && list[i].id) next.push(list[i])
        // the same list again (the usual case after the saved one): keep the view where it is
        if (JSON.stringify(next) !== JSON.stringify(apps)) apps = next
        if (fresh || !freshOk) partial = r.partial === true
        status = next.length ? "" : qsTr("No apps found.")
    }
    Connections {
        target: actions
        function onFinished(tool, r, id) {
            if (tool === "appmgr") {
                if (id === page.mgrReq) { page.mgrBusy = false; if (r.error) page.mgrStatus = r.error; else page.mgr = r }
                else if (id === page.actReq) {
                    page.policyBusy = false
                    page.mgrStatus = r.error ? r.error : r.stopped ? qsTr("Stopped.") : ""
                    page.loadMgr()
                }
                return
            }
            if (tool !== "apps") return
            if (id === page.listReq) page.applyList(r, true)
            else if (id === page.cachedReq) page.applyList(r, false)
            else if (id === page.infoReq) {
                page.infoBusy = false
                if (r.error) page.infoStatus = r.error
                else page.info = r
            } else if (id === page.openReq) {
                page.infoStatus = r.error ? r.error : qsTr("Opening %1...").arg(page.app ? page.app.name : "")
            }
        }
    }
    Component.onCompleted: { cachedReq = actions.run("apps", ["cached"]); listReq = actions.run("apps", ["list"]) }

    // the list
    ListView {
        id: list
        objectName: "appsList"
        visible: page.app === null
        Layout.fillWidth: true; Layout.fillHeight: true
        clip: true; boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 0
        model: page.apps
        delegate: SettingsItemDelegate {
            required property var modelData
            width: list.width
            onClicked: page.showApp(modelData)
            contentItem: RowLayout {
                spacing: 12
                Image {
                    source: page.iconSource(modelData.icon)
                    sourceSize.width: 40; sourceSize.height: 40
                    Layout.preferredWidth: 40; Layout.preferredHeight: 40
                    fillMode: Image.PreserveAspectFit; cache: true
                }
                SettingsLabel { text: modelData.name; color: backend.foreground; elide: Text.ElideRight; Layout.fillWidth: true }
            }
        }
        header: SettingsLabel {
            width: list.width; bottomPadding: 8
            text: page.apps.length > 0 ? qsTr("Apps in the app drawer: %1").arg(page.apps.length) + (page.scanning ? qsTr(" (checking for changes...)") : "") + (page.partial ? "\n" + qsTr("The list may be incomplete: there are more apps than Settings can show.") : "") : ""
            color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap
        }
        footer: SettingsLabel {
            width: list.width; topPadding: 12
            text: qsTr("Default apps and app permissions are not in Settings yet.")
            color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap
        }
    }
    SettingsLabel {
        objectName: "appsStatus"
        visible: page.app === null && page.status !== ""
        text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
    }

    // one app
    Flickable {
        visible: page.app !== null
        Layout.fillWidth: true; Layout.fillHeight: true
        contentWidth: width; contentHeight: detail.implicitHeight; clip: true
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: detail
            width: parent.width
            spacing: 10
            RowLayout {
                spacing: 14
                Image {
                    source: page.app ? page.iconSource(page.app.icon) : ""
                    sourceSize.width: 64; sourceSize.height: 64
                    Layout.preferredWidth: 64; Layout.preferredHeight: 64
                    fillMode: Image.PreserveAspectFit
                }
                SettingsLabel {
                    text: page.app ? page.app.name : ""
                    color: backend.foreground; font.pixelSize: SettingsStyle.fontPx(20); font.weight: Font.DemiBold
                    wrapMode: Text.Wrap; Layout.fillWidth: true
                }
            }
            SettingsButton {
                objectName: "openApp"
                text: qsTr("Open")
                enabled: page.app !== null && page.app.open !== false
                Layout.fillWidth: true
                onClicked: { page.infoStatus = ""; page.openReq = actions.run("apps", ["open", page.app.id]) }
            }
            SettingsLabel { visible: page.infoBusy; text: qsTr("Asking pacman..."); color: backend.muted; Layout.fillWidth: true }
            Repeater {
                model: page.infoBusy || page.info.id === undefined ? [] : [
                    { label: qsTr("Package"), value: page.info.package === null ? qsTr("Not from a pacman package") : page.info.package },
                    { label: qsTr("Version"), value: page.info.version },
                    { label: qsTr("Installed size"), value: page.info.size },
                    { label: qsTr("App ID"), value: page.info.id },
                    { label: qsTr("Desktop entry"), value: page.info.path }
                ]
                delegate: ColumnLayout {
                    required property var modelData
                    visible: modelData.value !== null && modelData.value !== undefined && modelData.value !== ""
                    Layout.fillWidth: true; spacing: 2
                    SettingsLabel { text: modelData.label; color: backend.foreground; Layout.fillWidth: true }
                    SettingsLabel { text: String(modelData.value); color: backend.muted; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true }
                }
            }
            // Manage: battery, stop
            ColumnLayout {
                objectName: "appManage"
                visible: page.mgr.id !== undefined
                Layout.fillWidth: true; spacing: 8
                SettingsLabel { visible: page.mgr.doze !== "missing"; text: qsTr("Battery"); color: backend.foreground; font.weight: Font.DemiBold; Layout.fillWidth: true; topPadding: 8 }
                Repeater {
                    // no Doze daemon installed: no choices (they would only write a file nothing reads)
                    model: page.mgr.doze === "missing" ? [] : ["unrestricted", "optimized", "restricted"]
                    delegate: SettingsButton {
                        required property string modelData
                        objectName: "policy_" + modelData
                        text: page.policyText(modelData)
                        highlighted: page.mgr.policy === modelData
                        enabled: !page.policyBusy
                        Layout.fillWidth: true
                        onClicked: { page.mgrStatus = ""; page.policyBusy = true; page.actReq = actions.run("appmgr", ["policy", page.app.id, modelData]) }
                    }
                }
                SettingsLabel {
                    visible: page.mgr.doze === "off"
                    text: qsTr("Doze is off: these choices take effect once it is on.")
                    color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                SettingsButton {
                    objectName: "stopApp"
                    text: qsTr("Stop for this session")
                    enabled: (page.mgr.units || []).length > 0 && !page.policyBusy
                    Layout.fillWidth: true
                    onClicked: { page.mgrStatus = ""; page.actReq = actions.run("appmgr", ["stop", page.app.id]) }
                }
                SettingsLabel {
                    visible: (page.mgr.units || []).length === 0
                    text: qsTr("Not running in its own unit (or not running): nothing to stop.")
                    color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
                }
            }
            SettingsLabel { visible: page.mgrBusy; text: qsTr("Checking what can be done..."); color: backend.muted; Layout.fillWidth: true }
            SettingsLabel { objectName: "mgrStatus"; visible: page.mgrStatus !== ""; text: page.mgrStatus; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
            SettingsLabel {
                visible: !page.infoBusy && page.info.id !== undefined
                text: page.info.package
                      ? qsTr("Uninstalling is not offered here: removing a package can take parts of the phone's system with it. To remove it from a terminal: sudo pacman -R %1").arg(page.info.package)
                      : qsTr("Uninstalling is not offered here.")
                color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true
            }
            SettingsLabel { visible: page.infoStatus !== ""; text: page.infoStatus; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
        }
    }
}
