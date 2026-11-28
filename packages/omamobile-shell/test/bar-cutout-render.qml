// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "bar" as Bar
import "bar/StatusModel.js" as StatusModel

// Offscreen shots of the status bar's own strip (BarStrip.qml) for
// test/bar-cutout-render: per $BAR_JOB entry a screen size and a set of
// items, fed through a stand-in for Bar.qml with the properties the strip
// reads. Prints the cutout zone, the fit and every shown item's rect in the
// strip's x, saves the strip as a PNG, then quits.
ShellRoot {
  id: shell

  FileView { id: jobFile; path: Quickshell.env("BAR_JOB"); blockLoading: true }
  readonly property var job: JSON.parse(jobFile.text())
  property int index: -1
  readonly property var shot: index >= 0 && index < job.shots.length ? job.shots[index] : null
  readonly property var st: shot ? shot.state : ({})

  // Bar.qml's side of the strip, from the shot's state.
  Item {
    id: stub
    readonly property color foreground: Commons.Color.bar.text
    readonly property color background: Commons.Color.bar.background
    readonly property color urgent: Commons.Color.bar.active
    readonly property string fontFamily: Style.font.family
    readonly property int barSize: Math.max(44, Style.bar.sizeHorizontal)
    readonly property bool cardsOnTap: false
    readonly property string omarchyPath: ""
    property var clickTargets: []
    function openQuickSettings() {}
    function openBluetoothPanel() {}
    readonly property string clockText: shell.st.clock || "13:27"
    readonly property string callChip: shell.st.call || ""
    readonly property bool showUnread: true
    readonly property int unread: shell.st.unread || 0
    readonly property bool showDnd: true
    readonly property bool doNotDisturb: shell.st.dnd === true
    readonly property bool showBluetooth: true
    readonly property bool bluetoothEnabled: shell.st.bluetooth !== undefined
    readonly property bool bluetoothConnected: shell.st.bluetooth === "connected"
    readonly property bool showCell: true
    readonly property string cellGlyph: shell.st.cellTech !== undefined ? StatusModel.cellularIcon(80) : ""
    readonly property string cellText: shell.st.cellTech || ""
    readonly property bool cellSearching: false
    readonly property bool showWifi: true
    readonly property string networkIcon: shell.st.wifi ? StatusModel.wifiIcon(90) : ""
    readonly property bool networkDim: false
    readonly property bool hasBattery: true
    readonly property string batteryStyle: shell.st.batteryStyle || "icon-percent"
    readonly property int batteryPercent: shell.st.percent || 58
    readonly property bool charging: shell.st.charging === true
    readonly property bool batteryFull: false
  }

  FloatingWindow {
    implicitWidth: 1100
    implicitHeight: 80
    color: "black"

    Rectangle {
      id: frame
      width: shell.shot ? shell.shot.w : 360
      height: stub.barSize
      color: stub.background

      Bar.BarStrip {
        id: strip
        anchors.fill: parent
        bar: stub
        cutout: StatusModel.cutout({}, "")
        screenWidth: shell.shot ? shell.shot.w : 360
        screenHeight: shell.shot ? shell.shot.h : 808
      }
    }
  }

  function describe(item, out) {
    if (!item) return out
    var name = String(item.objectName)
    if (["barClock", "callChip", "unreadNotifications", "barDnd", "barBluetooth", "barCell", "barCellText",
         "barWifi", "barBattery"].indexOf(name) >= 0 && item.visible) {
      var p = item.mapToItem(frame, 0, 0)
      out.push({ name: name, x: p.x, w: item.width })
    }
    for (var i = 0; i < item.children.length; i++) describe(item.children[i], out)
    return out
  }

  function next() {
    index++
    if (index >= job.shots.length) { Qt.quit(); return }
    settle.restart()
  }

  Timer { id: settle; interval: 500; onTriggered: shell.capture() }

  function capture() {
    var s = shell.shot
    var fit = strip.fit
    console.log("geometry " + s.name + " " + frame.width + "x" + frame.height + " "
      + JSON.stringify({ zone: strip.zone, margin: strip.margin, show: fit.show, left: fit.left, right: fit.right,
                         leftRoom: fit.leftRoom, rightRoom: fit.rightRoom, fits: fit.fits,
                         present: strip.leftItems.concat(strip.rightItems),
                         items: shell.describe(strip, []) }))
    frame.grabToImage(function(result) {
      result.saveToFile(s.png)
      console.log("shot " + s.png)
      Qt.callLater(shell.next)
    })
  }

  Component.onCompleted: Qt.callLater(shell.next)
}
