// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// App search only. The application library and launch path remain Omarchy's;
// this component neither indexes files nor selects an agent or account.
Item {
  id: root
  objectName: "appsSearch"

  property var appLibrary: null
  property bool paintBackground: true
  property bool opened: false
  property bool sessionLocked: false
  onSessionLockedChanged: if (sessionLocked) dismiss()
  property string query: ""
  property var entries: []
  property bool surfaceActive: root.Window.active
  property bool inputReady: true
  property int focusGeneration: 0
  property bool focusPending: false
  property bool hadFocus: false
  property int transitionDuration: typeof Style.duration === "function" ? Style.duration(140) : 140
  readonly property color foreground: Commons.Color.menu.text
  readonly property int touch: Math.max(44, Style.space(44))
  readonly property real searchMargin: Math.max(0, Math.min(Style.spacing.xxl, (height - touch) / 4))
  signal dismissed()
  signal activated(var entry)
  // Also useful to the offscreen harness: this observes the production input
  // context request, not a pretend keyboard or a global visibility policy.
  signal inputRequested(bool visible)

  opacity: opened ? 1 : 0
  enabled: opened
  Behavior on opacity { NumberAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic } }

  function refreshEntries() {
    if (!opened) return
    var ranked = appLibrary ? appLibrary.sortedEntries(query) : []
    var next = []
    for (var i = 0; i < ranked.length && next.length < 40; i++)
      if (ranked[i] && ranked[i].entry) next.push(ranked[i].entry)
    var same = next.length === entries.length
    for (var j = 0; same && j < next.length; j++) same = next[j] === entries[j]
    if (!same) entries = next
  }
  function name(entry) {
    return appLibrary && typeof appLibrary.entryName === "function"
      ? appLibrary.entryName(entry) : String(entry && entry.name || "")
  }
  function icon(entry) {
    return appLibrary && typeof appLibrary.iconSource === "function"
      ? appLibrary.iconSource(entry.icon) : ""
  }
  function queueFocus() {
    if (sessionLocked || !opened || !focusPending || !surfaceActive || !inputReady) return
    var generation = focusGeneration
    Qt.callLater(function() {
      if (root.sessionLocked || !root.opened || !root.focusPending || !root.surfaceActive || !root.inputReady || generation !== root.focusGeneration) return
      root.focusPending = false
      input.forceActiveFocus()
      root.hadFocus = true
      Qt.inputMethod.show()
      root.inputRequested(true)
    })
  }
  function open(text) {
    if (sessionLocked) { close(); return }
    ++focusGeneration
    query = String(text || "").slice(0, 256)
    opened = true
    hadFocus = false
    focusPending = true
    refreshEntries()
    queueFocus()
  }
  function close() {
    ++focusGeneration
    focusPending = false
    // Never hide a different app's or the lock screen's input context after
    // focus has already moved there. Clearing our field still releases it.
    if (input.activeFocus && surfaceActive) {
      Qt.inputMethod.hide()
      inputRequested(false)
    }
    input.focus = false
    if (surfaceActive) root.forceActiveFocus()
    hadFocus = false
    opened = false
  }
  function dismiss() { close(); dismissed() }
  function activate(entry) {
    if (!entry || !entry.id) return
    close() // release our input context before an app can take focus
    activated(entry)
  }
  function activateFirst() { if (entries.length) activate(entries[0]) }
  onQueryChanged: refreshEntries()
  onAppLibraryChanged: refreshEntries()
  onInputReadyChanged: queueFocus()
  onSurfaceActiveChanged: {
    if (!opened) return
    if (surfaceActive) queueFocus()
    else if (hadFocus) dismiss()
  }
  Connections {
    target: root.appLibrary
    ignoreUnknownSignals: true
    function onAppsChanged() { root.refreshEntries() }
  }

  onOpacityChanged: if (opacity === 0 && !opened) { query = ""; entries = [] }
  Rectangle { anchors.fill: parent; visible: root.paintBackground; color: Commons.Color.menu.background }
  ColumnLayout {
    anchors.fill: parent
    anchors.margins: root.searchMargin
    spacing: Style.spacing.lg

    RowLayout {
      visible: root.height >= Style.space(280)
      Layout.fillWidth: true
      spacing: Style.spacing.lg
      Text {
        Layout.fillWidth: true
        text: "Search apps"
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        font.bold: true
        elide: Text.ElideRight
      }
      BorderSurface {
        objectName: "searchClose"
        Layout.preferredWidth: root.touch
        Layout.preferredHeight: root.touch
        radius: Style.cornerRadius
        color: closeTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : "transparent"
        borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)
        Accessible.name: "Close search"
        Accessible.role: Accessible.Button
        Text { anchors.centerIn: parent; text: "×"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.display }
        MouseArea { id: closeTouch; anchors.fill: parent; onClicked: root.dismiss() }
      }
    }

    ListView {
      id: results
      objectName: "searchResults"
      visible: root.height >= Style.space(180)
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: Style.spacing.sm
      model: root.entries
      boundsBehavior: Flickable.StopAtBounds
      delegate: BorderSurface {
        required property var modelData
        required property int index
        objectName: "searchResult" + index
        width: results.width
        height: Math.max(root.touch, Style.space(64))
        radius: Style.cornerRadius
        color: rowTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : "transparent"
        borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)
        Accessible.name: root.name(modelData)
        Accessible.role: Accessible.Button
        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.spacing.md
          spacing: Style.spacing.lg
          Item {
            Layout.preferredWidth: Style.space(36)
            Layout.preferredHeight: Style.space(36)
            Image { id: appIcon; anchors.fill: parent; source: root.icon(modelData); fillMode: Image.PreserveAspectFit }
            Text { anchors.centerIn: parent; visible: appIcon.status !== Image.Ready; text: root.name(modelData).slice(0, 1); textFormat: Text.PlainText; color: Commons.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.title }
          }
          Text {
            Layout.fillWidth: true
            text: root.name(modelData)
            textFormat: Text.PlainText
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            elide: Text.ElideRight
          }
          Text { text: "›"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title }
        }
        MouseArea { id: rowTouch; anchors.fill: parent; onClicked: root.activate(modelData) }
      }
      // Fade moving rows into the surface instead of ending a border at a
      // hard viewport edge. These decorations never receive input.
      Rectangle {
        parent: results
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: Math.min(Style.spacing.lg, results.height)
        visible: !results.atYBeginning
        z: 1
        gradient: Gradient {
          GradientStop { position: 0; color: Commons.Color.menu.background }
          GradientStop { position: 1; color: Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, 0) }
        }
      }
      Rectangle {
        parent: results
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Math.min(Style.spacing.lg, results.height)
        visible: !results.atYEnd
        z: 1
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, 0) }
          GradientStop { position: 1; color: Commons.Color.menu.background }
        }
      }
      Text {
        parent: results
        objectName: "searchEmpty"
        anchors.centerIn: parent
        width: parent.width
        visible: root.entries.length === 0
        text: root.appLibrary ? "No apps found" : "Loading apps…"
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    TextField {
      id: input
      objectName: "appsSearchInput"
      Layout.fillWidth: true
      Layout.minimumHeight: Math.min(root.touch, Math.max(0, root.height - root.searchMargin * 2))
      Layout.preferredHeight: Math.max(root.touch, implicitHeight, Style.space(52))
      Layout.alignment: Qt.AlignBottom
      text: root.query
      placeholderText: "Search apps…"
      foreground: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      maximumLength: 256
      selectByMouse: true
      Accessible.name: "Search apps"
      onTextEdited: root.query = text
      Keys.onReturnPressed: root.activateFirst()
      Keys.onEnterPressed: root.activateFirst()
      Keys.onEscapePressed: root.dismiss()
    }
  }
  Keys.onEscapePressed: root.dismiss()
  Keys.onBackPressed: root.dismiss()
}
