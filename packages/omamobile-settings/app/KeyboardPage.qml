// SPDX-License-Identifier: MIT
// Keyboard layouts (up to 4) and the hardware switch key, through backends/keyboard.sh. Each change is
// saved and applied at once; the backend keeps the on-screen keyboard's list in the same order.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."
Flickable {
    id: page
    clip: true
    contentWidth: width; contentHeight: col.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    property var layouts: []        // ["us", "gr:polytonic"], index 0 = main layout
    property string switchKey: ""
    property var available: []      // [{layout, name}]
    property var switchKeys: []     // [{option, name}]
    property string status: qsTr("Reading the keyboard settings...")
    property string warn: ""
    property bool busy: true
    property bool adding: false
    property int reqId: -1
    property int listId: -1
    readonly property int maxLayouts: 4
    // Same set as LATIN in backends/keyboard.sh
    readonly property var latin: ["us", "gb", "de", "fr", "es", "it", "pt", "nl", "be", "ch", "at", "se", "no", "dk", "fi",
        "is", "ie", "pl", "cz", "sk", "hu", "ro", "hr", "si", "ee", "lv", "lt", "tr", "br", "latam",
        "ca", "au", "nz", "za", "epo"]
    function nameOf(code) {
        const l = code.split(":")[0], v = code.split(":")[1] || ""
        for (const a of available) if (a.layout === l) return v ? a.name + " (" + v + ")" : a.name
        return code
    }
    function keyName(opt) {
        for (const k of switchKeys) if (k.option === opt) return k.name
        return opt
    }
    function apply(r) {
        busy = false
        if (r.error) { status = r.error; return }
        if (!r.layouts) { status = qsTr("The keyboard backend gave no values."); return }
        layouts = r.layouts.map(x => x.variant ? x.layout + ":" + x.variant : x.layout)
        switchKey = r.switchKey || ""
        warn = r.warn || (layouts.length && latin.indexOf(layouts[0].split(":")[0]) < 0
              ? qsTr("The first layout is not a Latin one: passwords on the lock screen are typed in it") : "")
        status = qsTr("Changes apply at once to hardware keyboards and the on-screen keyboard.")
    }
    function save(list) {
        busy = true; adding = false
        reqId = actions.run("keyboard", ["set", "layouts", list.join(",")])
    }
    function move(i, d) {
        const l = layouts.slice(), j = i + d
        if (j < 0 || j >= l.length) return
        const t = l[i]; l[i] = l[j]; l[j] = t
        save(l)
    }
    function remove(i) { const l = layouts.slice(); l.splice(i, 1); save(l) }
    function add(code) { if (layouts.indexOf(code) < 0) save(layouts.concat([code])) }
    Connections {
        target: actions
        function onFinished(tool, r, id) {
            if (tool !== "keyboard") return
            if (id === page.listId) { page.available = r.layouts || []; page.switchKeys = r.switchKeys || [] }
            else if (id === page.reqId) page.apply(r)
        }
    }
    Component.onCompleted: { listId = actions.run("keyboard", ["list"]); reqId = actions.run("keyboard", ["get"]) }
    ColumnLayout {
        id: col
        width: page.width
        spacing: 14
        SettingsLabel { text: qsTr("Layouts"); font.weight: Font.DemiBold; color: backend.foreground; Layout.fillWidth: true }
        Repeater {
            model: page.layouts
            delegate: RowLayout {
                required property string modelData
                required property int index
                Layout.fillWidth: true; spacing: 8
                SettingsLabel {
                    text: (index + 1) + ". " + page.nameOf(modelData)
                    color: backend.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                SettingsButton { text: "↑"; enabled: !page.busy && index > 0; onClicked: page.move(index, -1); Accessible.name: qsTr("Move up") }
                SettingsButton { text: "↓"; enabled: !page.busy && index < page.layouts.length - 1; onClicked: page.move(index, 1); Accessible.name: qsTr("Move down") }
                SettingsButton { text: "✕"; enabled: !page.busy && page.layouts.length > 1; onClicked: page.remove(index); Accessible.name: qsTr("Remove") }
            }
        }
        SettingsLabel {
            visible: page.warn !== ""
            text: "⚠ " + page.warn
            color: backend.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true
        }
        SettingsButton {
            visible: !page.adding && page.layouts.length < page.maxLayouts
            enabled: !page.busy && page.available.length > 0
            text: qsTr("Add a layout")
            onClicked: { filter.text = ""; page.adding = true }
        }
        SettingsTextField {
            id: filter
            visible: page.adding
            Layout.fillWidth: true; Layout.preferredHeight: 52
            placeholderText: qsTr("Search layouts")
            color: backend.foreground; placeholderTextColor: backend.muted
            background: Rectangle { radius: Math.min(backend.radius, width / 2, height / 2); color: SettingsStyle.fill("normal") }
        }
        Repeater {
            model: page.adding ? page.available.filter(a => {
                const q = filter.text.toLowerCase()
                return page.layouts.indexOf(a.layout) < 0 && (q === "" || a.name.toLowerCase().indexOf(q) >= 0 || a.layout.indexOf(q) >= 0)
            }).slice(0, 30) : []
            delegate: SettingsButton {
                required property var modelData
                Layout.fillWidth: true
                text: modelData.name + "  (" + modelData.layout + ")"
                enabled: !page.busy
                onClicked: page.add(modelData.layout)
            }
        }
        SettingsButton { visible: page.adding; text: qsTr("Cancel"); onClicked: page.adding = false }
        SettingsLabel {
            visible: page.layouts.length > 1
            text: qsTr("Switch key (hardware keyboard)"); font.weight: Font.DemiBold; color: backend.foreground
            Layout.fillWidth: true; Layout.topMargin: 8
        }
        Flow {
            visible: page.layouts.length > 1
            Layout.fillWidth: true; spacing: 8
            Repeater {
                model: [{ option: "none", name: qsTr("None") }].concat(page.switchKeys.filter(k =>
                    ["grp:alt_shift_toggle", "grp:ctrl_shift_toggle", "grp:caps_toggle",
                     "grp:alt_space_toggle", "grp:ctrl_space_toggle"].indexOf(k.option) >= 0 || k.option === page.switchKey))
                delegate: SettingsButton {
                    required property var modelData
                    text: modelData.name
                    highlighted: modelData.option === "none" ? page.switchKey === "" : page.switchKey === modelData.option
                    enabled: !page.busy
                    onClicked: { page.busy = true; page.reqId = actions.run("keyboard", ["set", "switch-key", modelData.option]) }
                }
            }
        }
        SettingsLabel { text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
    }
}
