// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "quicksettings" as QS

// Offscreen review shots of quick settings (test/quicksettings-render):
// the real QuickSettings.qml at the phone's 480x1040 logical px and on
// its side at 1040x480, over an app stand-in, each shot in $QS_JOB
// (collapsed, expanded, editing) saved as a PNG with the geometry of the
// sheet, the tiles, the handle and the shade printed for the checks. Then
// it quits. A shot with "media" hands the sheet a made-up MPRIS player
// (no session bus here), with the job's art file, to show the media card.
ShellRoot {
  id: shell

  FileView { id: jobFile; path: Quickshell.env("QS_JOB"); blockLoading: true }
  readonly property var job: JSON.parse(jobFile.text())
  property int index: -1
  readonly property var shot: shell.index >= 0 && shell.index < shell.job.shots.length ? shell.job.shots[shell.index] : null

  FloatingWindow {
    id: win
    implicitWidth: 1040
    implicitHeight: 1040
    color: "black"

    Item {
      id: screen
      width: shell.shot ? shell.shot.w : 480
      height: shell.shot ? shell.shot.h : 1040

      // An app behind the sheet: a bar and a dark window.
      Rectangle { width: parent.width; height: 44; color: Commons.Color.bar.background
        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "13:27"; color: Commons.Color.bar.text; font.family: Style.font.family; font.pixelSize: 15 } }
      Rectangle { y: 44; width: parent.width; height: parent.height - 44; color: "#202020"
        Text { anchors.centerIn: parent; text: "app"; color: "#808080"; font.pixelSize: 30 } }

      QS.QuickSettings {
        id: qs
        anchors.fill: parent
      }
    }
  }

  function rectOf(item) {
    var p = item.mapToItem(screen, 0, 0)
    return { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(item.width), h: Math.round(item.height) }
  }

  // The named parts that are shown, as {name: {x, y, w, h}} in screen px.
  function describe(item, out) {
    if (!item || !item.visible || item.opacity === 0) return out
    if (item.objectName) out[item.objectName] = shell.rectOf(item)
    for (var i = 0; i < item.children.length; i++) shell.describe(item.children[i], out)
    return out
  }

  // A player as Quickshell's MprisPlayer looks to the card.
  component FakePlayer: QtObject {
    property string identity: "Music"
    property string desktopEntry: "org.example.Music"
    property string dbusName: "org.mpris.MediaPlayer2.music"
    property string trackTitle: ""
    property string trackArtist: ""
    property var trackArtists: []
    property string trackAlbum: ""
    property string trackArtUrl: ""
    property bool isPlaying: true
    property int playbackState: 1
    property bool canPlay: true
    property bool canPause: true
    property bool canTogglePlaying: true
    property bool canGoNext: true
    property bool canGoPrevious: true
    property bool canSeek: true
    property bool canRaise: false
    property bool positionSupported: true
    property bool lengthSupported: true
    property real position: 83
    property real length: 247
    signal trackChanged()
    function play() {}
    function pause() {}
    function togglePlaying() {}
    function next() {}
    function previous() {}
    function raise() {}
  }
  Component { id: fakePlayer; FakePlayer {} }

  // Whether a named Text is cut short (its full text wider than it is).
  function elided(item, name) {
    if (!item) return false
    if (item.objectName === name) return item.implicitWidth > item.width + 1
    for (var i = 0; i < item.children.length; i++) if (shell.elided(item.children[i], name)) return true
    return false
  }

  function next() {
    shell.index++
    if (shell.index >= shell.job.shots.length) { Qt.quit(); return }
    var s = shell.shot
    qs.close()
    qs.media.players = s.media ? [fakePlayer.createObject(shell, s.media)] : []
    Qt.callLater(function() {
      qs.open(JSON.stringify({ expanded: s.expanded === true, page: s.edit ? "edit" : "" }))
      settle.restart()
    })
  }

  Timer { id: settle; interval: 1500; onTriggered: shell.capture() }

  function capture() {
    var s = shell.shot
    var parts = shell.describe(qs, {})
    console.log("geometry " + s.name + " " + screen.width + "x" + screen.height
                + " " + JSON.stringify({ parts: parts, columns: qs.tileColumns, expanded: qs.expanded, edit: qs.editing, notifications: qs.notifications.length,
                                     media: !!s.media, titleElided: shell.elided(qs, "mediaTitle") }))
    screen.grabToImage(function(result) {
      result.saveToFile(s.png)
      console.log("shot " + s.png)
      Qt.callLater(shell.next)
    })
  }

  Timer { interval: 800; running: true; onTriggered: shell.next() }
}
