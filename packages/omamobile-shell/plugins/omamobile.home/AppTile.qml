// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

// An app shortcut: icon over its name, launched the way the app drawer
// launches apps (omamobile-launch: uwsm-app -- gtk-launch on a new empty
// workspace, or the app's open window focused).
// An app that is no longer installed stays, dimmed and named "Not
// installed" rather than by its raw id (TOUCH-PLAN 3.7), until it is
// removed in edit mode (it may come back with its package); the widgets
// sheet's Missing list still shows the id.
Item {
  id: tile

  property var home: null
  property var entry: null
  property bool editing: false

  readonly property var desktopEntry: home && entry ? home.entryFor(entry.app) : null
  readonly property bool missing: !desktopEntry
  readonly property var library: home ? home.appLibrary : null

  opacity: missing ? 0.45 : 1

  Rectangle {
    anchors.centerIn: icon
    width: icon.width + 12
    height: width
    radius: width * 0.3
    color: touch.pressed ? Qt.rgba(1, 1, 1, 0.2) : "transparent"
  }

  Image {
    id: icon
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.verticalCenter
    anchors.bottomMargin: -Math.round(width * 0.18)
    // Phone-sized, like a home-screen icon on iOS: most of the cell's width.
    width: Math.min(64, Math.max(40, Math.min(tile.width, tile.height) * 0.62))
    height: width
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    sourceSize.width: width * Screen.devicePixelRatio
    sourceSize.height: height * Screen.devicePixelRatio
    source: tile.library ? tile.library.iconSource(tile.desktopEntry ? tile.desktopEntry.icon : "") : ""
  }

  Text {
    anchors.top: icon.bottom
    anchors.topMargin: Style.spacing.md
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.xs
    anchors.rightMargin: Style.spacing.xs
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
    text: tile.missing ? "Not installed" : (tile.library ? tile.library.entryName(tile.desktopEntry) : tile.desktopEntry.name)
    color: tile.home ? tile.home.foreground : "white"
    // An outline keeps the name readable on a light wallpaper; it costs
    // nothing like a blur or a drop shadow would.
    style: Text.Outline
    styleColor: Util.alpha(Commons.Color.menu.background, 0.85)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption + 3
    font.weight: Font.DemiBold
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  MouseArea {
    id: touch
    anchors.fill: parent
    enabled: !tile.editing
    onClicked: {
      if (!tile.home) return
      if (tile.missing) tile.home.flash("Not installed: hold to edit")
      else tile.home.launch(tile.entry.app)
    }
  }
}
