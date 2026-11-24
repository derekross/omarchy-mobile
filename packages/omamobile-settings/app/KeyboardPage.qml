// SPDX-License-Identifier: MIT
// Keyboard layouts (up to 4) and the hardware switch key, through backends/keyboard.sh. Each change is
// saved to Omarchy's ~/.config/omarchy/keyboard-layouts and applied at once; new layouts are added to the on-screen
// keyboard's list. The Latin rule lives in the backend only: it puts us first when needed and says so in "note".
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
    property string override: ""     // set when the user's input.lua sets its own layouts
    property bool busy: true
    property int reqId: -1
    property int listId: -1
    readonly property int maxLayouts: 4
    function nameOf(code) {
        const l = code.split(":")[0], v = code.split(":")[1] || ""
        for (const a of available) if (a.layout === l) return v ? a.name + " (" + v + ")" : a.name
        return code
    }
    function keyName(opt) {
        for (const k of switchKeys) if (k.option === opt) return k.name
        return opt
    }
    property string lastError: ""   // shown after the re-read that follows a failed set
    function apply(r) {
        busy = false
        if (r.error) {
            // A set can fail half way (file saved, live apply or OSK not): read the real state again so
            // the next change is not built from a stale list, and keep the error on screen.
            if (lastError === "") { lastError = r.note ? r.error + " " + r.note : r.error; status = r.error; busy = true; reqId = actions.run("keyboard", ["get"]) }
            else { status = lastError; lastError = "" }
            return
        }
        if (!r.layouts) { status = qsTr("The keyboard backend gave no values."); return }
        layouts = r.layouts.map(x => x.variant ? x.layout + ":" + x.variant : x.layout)
        switchKey = r.switchKey || ""
        override = r.override || ""
        status = lastError !== "" ? lastError
               : override !== "" ? override + qsTr(": change the layouts there, or remove them from it.")
               : r.note ? r.note
               : qsTr("Changes apply at once to hardware keyboards; new layouts are added to the on-screen keyboard.")
        lastError = ""
    }
    function save(list) {
        filter.text = ""
        busy = true
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
                SettingsButton { text: "↑"; enabled: !page.busy && page.override === "" && index > 0; onClicked: page.move(index, -1); Accessible.name: qsTr("Move up") }
                SettingsButton { text: "↓"; enabled: !page.busy && page.override === "" && index < page.layouts.length - 1; onClicked: page.move(index, 1); Accessible.name: qsTr("Move down") }
                SettingsButton { text: "✕"; enabled: !page.busy && page.override === "" && page.layouts.length > 1; onClicked: page.remove(index); Accessible.name: qsTr("Remove") }
            }
        }
        // Add a layout: a search field, with matches shown as you type (the full list is ~100 long).
        SettingsTextField {
            id: filter
            visible: page.layouts.length < page.maxLayouts && page.override === ""
            enabled: !page.busy && page.available.length > 0
            Layout.fillWidth: true; Layout.preferredHeight: 52
            placeholderText: qsTr("Add a layout: type a language or country")
            color: backend.foreground; placeholderTextColor: backend.muted
            background: Rectangle { radius: Math.min(backend.radius, width / 2, height / 2); color: SettingsStyle.fill("normal") }
        }
        Repeater {
            model: filter.visible && filter.text.trim() !== "" ? page.available.filter(a => {
                const q = filter.text.trim().toLowerCase()
                return page.layouts.indexOf(a.layout) < 0 && (a.name.toLowerCase().indexOf(q) >= 0 || a.layout.indexOf(q) >= 0)
            }).slice(0, 12) : []
            delegate: SettingsButton {
                required property var modelData
                Layout.fillWidth: true
                text: modelData.name + "  (" + modelData.layout + ")"
                enabled: !page.busy
                onClicked: page.add(modelData.layout)
            }
        }
        SettingsLabel {
            text: qsTr("Switch key (hardware keyboard)"); font.weight: Font.DemiBold; color: backend.foreground
            Layout.fillWidth: true; Layout.topMargin: 8
        }
        Flow {
            Layout.fillWidth: true; spacing: 8
            Repeater {
                // From `keyboard.sh list`: Alt+Shift, Ctrl+Shift, Caps Lock, Omarchy default (no block in input.lua)
                model: page.switchKeys
                delegate: SettingsButton {
                    required property var modelData
                    text: modelData.name
                    highlighted: page.switchKey === modelData.option
                    enabled: !page.busy && page.switchKey !== "custom"
                    onClicked: { page.busy = true; page.reqId = actions.run("keyboard", ["set", "switch-key", modelData.option]) }
                }
            }
        }
        SettingsLabel {
            visible: page.switchKey === "custom"
            text: qsTr("input.lua sets its own kb_options, so the switch key is set there.")
            color: backend.muted; wrapMode: Text.Wrap; Layout.fillWidth: true
        }
        SettingsLabel { text: page.status; color: backend.muted; font.pixelSize: SettingsStyle.fontPx(13); wrapMode: Text.Wrap; Layout.fillWidth: true }
    }
}
