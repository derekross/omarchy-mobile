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
    var limit = query.trim() ? 40 : 3
    for (var i = 0; i < ranked.length && next.length < limit; i++)
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
  // The phone's Search layout: a top composer, then compact borderless
  // app rows. Glass is a tint, never a live client-side wallpaper effect.
  readonly property color backgroundTone: Commons.Color.menu.background
  readonly property real backdropAlpha: typeof Style.styleAlpha === "function" ? Style.styleAlpha("mobile-search-backdrop-alpha", 0.92) : 0.92
  readonly property real cardAlpha: typeof Style.styleAlpha === "function" ? Style.styleAlpha("mobile-search-card-alpha", 0.94) : 0.94
  readonly property color backdropColor: Qt.rgba(backgroundTone.r, backgroundTone.g, backgroundTone.b, backdropAlpha)
  readonly property color secondary: Qt.tint(backgroundTone, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.72))
  readonly property color muted: Qt.tint(backgroundTone, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.60))
  readonly property color cardTone: Qt.tint(backgroundTone, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.06))
  readonly property color cardColor: Qt.rgba(cardTone.r, cardTone.g, cardTone.b, cardAlpha)
  function glyph(name, ink) {
    var paths = {
      close: '<path d="m6 6 12 12M18 6 6 18"/>',
      search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
      chevron: '<path d="m9 6 6 6-6 6"/>'
    }
    return "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="' + String(ink) + '" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + paths[name] + '</svg>')
  }
  Rectangle { anchors.fill: parent; visible: root.paintBackground; color: root.backdropColor }
  ColumnLayout {
    anchors.fill: parent
    anchors.leftMargin: Math.min(Style.space(24), root.width / 8)
    anchors.rightMargin: anchors.leftMargin
    anchors.topMargin: Math.min(Style.space(12), Math.max(0, (root.height - root.touch) / 4))
    anchors.bottomMargin: Math.min(Style.space(16), Math.max(0, (root.height - root.touch) / 4))
    spacing: 0

    RowLayout {
      objectName: "searchHeader"
      Layout.fillWidth: true
      Layout.minimumHeight: Math.min(root.touch, root.height)
      Layout.maximumHeight: Layout.preferredHeight
      Layout.preferredHeight: Math.min(Style.space(56), Math.max(root.touch, root.height))
      spacing: Style.spacing.lg
      Item {
        objectName: "searchClose"
        Layout.preferredWidth: root.touch
        Layout.fillHeight: true
        Accessible.name: "Close search"
        Accessible.role: Accessible.Button
        Image { anchors.centerIn: parent; width: Style.space(24); height: width; source: root.glyph("close", root.foreground) }
        MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
      }
      BorderSurface {
        objectName: "searchInputSurface"
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Style.cornerRadius
        color: root.cardColor
        borderSpec: Border.controlSpec(input.activeFocus ? "focus" : "normal", root.foreground, Commons.Color.accent)
        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(16)
          anchors.rightMargin: Style.spacing.sm
          spacing: Style.spacing.xxl
          Image { Layout.preferredWidth: Style.space(20); Layout.preferredHeight: width; source: root.glyph("search", root.secondary) }
          TextField {
            id: input
            objectName: "appsSearchInput"
            Layout.fillWidth: true
            Layout.fillHeight: true
            background: null
            padding: 0
            text: root.query
            placeholderText: "Search apps"
            foreground: root.foreground
            placeholderTextColor: root.muted
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
          Item {
            objectName: "searchClear"
            visible: root.query.length > 0
            Layout.preferredWidth: root.touch
            Layout.fillHeight: true
            Accessible.name: "Clear search"
            Accessible.role: Accessible.Button
            Image { anchors.centerIn: parent; width: Style.space(20); height: width; source: root.glyph("close", root.secondary) }
            MouseArea { anchors.fill: parent; onClicked: { root.query = ""; input.forceActiveFocus() } }
          }
        }
      }
    }

    Item { Layout.fillWidth: true; Layout.preferredHeight: root.height >= Style.space(180) ? Style.space(28) : 0 }
    Text {
      visible: root.entries.length > 0 && root.height >= Style.space(180)
      Layout.fillWidth: true
      Layout.bottomMargin: Style.spacing.xxl
      text: "Apps"
      color: root.secondary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }
    ListView {
      id: results
      objectName: "searchResults"
      visible: root.height >= Style.space(180)
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      clip: true
      spacing: 0
      model: root.entries
      boundsBehavior: Flickable.StopAtBounds
      delegate: Item {
        required property var modelData
        required property int index
        objectName: "searchResult" + index
        width: results.width
        height: Math.max(root.touch, Style.space(68))
        Accessible.name: root.name(modelData)
        Accessible.role: Accessible.Button
        Rectangle { anchors.fill: parent; radius: Style.cornerRadius; color: rowTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : "transparent" }
        RowLayout {
          anchors.fill: parent
          spacing: Style.space(14)
          Rectangle {
            Layout.preferredWidth: root.touch
            Layout.preferredHeight: root.touch
            radius: Style.cornerRadius
            color: root.cardColor
            Image { id: appIcon; anchors.centerIn: parent; width: Style.space(32); height: width; source: root.icon(modelData); fillMode: Image.PreserveAspectFit }
            Text { anchors.centerIn: parent; visible: appIcon.status !== Image.Ready; text: root.name(modelData).slice(0, 1); textFormat: Text.PlainText; color: Commons.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.title }
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.xs
            Text {
              Layout.fillWidth: true
              text: root.name(modelData)
              textFormat: Text.PlainText
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: (typeof Style.font.heading === "number" ? Style.font.heading : Style.font.title)
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              Layout.fillWidth: true
              text: String(modelData.genericName || modelData.comment || "Application")
              textFormat: Text.PlainText
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }
          Image { Layout.preferredWidth: Style.space(18); Layout.preferredHeight: width; source: root.glyph("chevron", root.muted) }
        }
        MouseArea { id: rowTouch; anchors.fill: parent; onClicked: root.activate(modelData) }
      }
      // Translucent fades follow the glass tint without an opaque edge band.
      Rectangle {
        parent: results
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: Math.min(Style.spacing.lg, results.height)
        visible: !results.atYBeginning
        z: 1
        gradient: Gradient {
          GradientStop { position: 0; color: root.backdropColor }
          GradientStop { position: 1; color: Qt.rgba(root.backgroundTone.r, root.backgroundTone.g, root.backgroundTone.b, 0) }
        }
      }
      Rectangle {
        parent: results
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Math.min(Style.spacing.lg, results.height)
        visible: !results.atYEnd
        z: 1
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(root.backgroundTone.r, root.backgroundTone.g, root.backgroundTone.b, 0) }
          GradientStop { position: 1; color: root.backdropColor }
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
        color: root.secondary
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
    Item { visible: !results.visible; Layout.fillHeight: true }
  }
  Keys.onEscapePressed: root.dismiss()
  Keys.onBackPressed: root.dismiss()
}
