// SPDX-License-Identifier: MIT
// The home screen under a mouse and a finger (test/home-mouse runs this):
// AppTile.qml in a pager built as Home.qml builds it (a horizontal ListView
// of pages) with LongPressEdit.qml over it at z 50, and a stand-in for the
// home screen that records what the tiles ask of it, with requestEdit()
// and the edit-mode switch as Home.qml has them.
import QtQuick
import QtTest
import "home"

Item {
  id: view
  width: 412
  height: 892

  QtObject {
    id: homeStub
    property color foreground: "#c0caf5"
    property var appLibrary: null
    property bool editing: false
    property bool landscape: false
    property string sheet: ""
    property var launched: []
    property var notices: []
    property int editRequests: 0
    function entryFor(app) { return app === "gone" ? null : { id: app + ".desktop", name: app, icon: "" } }
    function launch(app) { launched = launched.concat([app]); return true }
    function flash(text) { notices = notices.concat([text]) }
    function requestEdit() {
      editRequests++
      if (landscape) { flash("Turn the phone upright to edit"); return "landscape" }
      editing = true
      return "editing"
    }
  }

  property int widgetTaps: 0

  ListView {
    id: pager
    anchors.fill: parent
    anchors.topMargin: 12
    anchors.bottomMargin: 28
    orientation: ListView.Horizontal
    snapMode: ListView.SnapOneItem
    highlightRangeMode: ListView.StrictlyEnforceRange
    boundsBehavior: Flickable.StopAtBounds
    interactive: !homeStub.editing && homeStub.sheet === ""
    model: 2

    delegate: Item {
      id: page
      required property int index
      width: pager.width
      height: pager.height

      // An app in the top-left cell, a widget with its own tap beside it,
      // the rest of the page empty.
      AppTile {
        objectName: "tile" + page.index
        x: 0
        y: 0
        width: 103
        height: 110
        home: homeStub
        entry: { "app": "app" + page.index }
        editing: homeStub.editing
      }
      Rectangle {
        objectName: "widget" + page.index
        x: 103
        y: 0
        width: 206
        height: 110
        color: "#24283b"
        MouseArea {
          anchors.fill: parent
          enabled: !homeStub.editing
          onClicked: view.widgetTaps++
        }
      }
    }
  }

  LongPressEdit {
    id: hold
    anchors.fill: pager
    z: 50
    home: homeStub
    active: !homeStub.editing && homeStub.sheet === ""
  }

  TestCase {
    id: test
    name: "HomeMouse"
    when: windowShown

    readonly property point tile: Qt.point(51, 12 + 55)
    readonly property point widget: Qt.point(206, 12 + 55)
    readonly property point empty: Qt.point(206, 500)

    function init() {
      homeStub.editing = false
      homeStub.landscape = false
      homeStub.sheet = ""
      homeStub.launched = []
      homeStub.notices = []
      homeStub.editRequests = 0
      view.widgetTaps = 0
      pager.positionViewAtIndex(0, ListView.Beginning)
      waitForRendering(pager)
    }

    function touchTap(p) {
      var t = touchEvent(view)
      t.press(0, view, p.x, p.y).commit()
      wait(50)
      t.release(0, view, p.x, p.y).commit()
    }

    function touchHold(p) {
      var t = touchEvent(view)
      t.press(0, view, p.x, p.y).commit()
      wait(800)
      t.release(0, view, p.x, p.y).commit()
    }

    function mouseHold(p) {
      mousePress(view, p.x, p.y)
      wait(800)
      mouseRelease(view, p.x, p.y)
    }

    function test_mouse_click_launches() {
      mouseClick(view, tile.x, tile.y)
      compare(homeStub.launched, ["app0"], "a click on a tile launches its app")
      compare(homeStub.editRequests, 0)
    }

    function test_touch_tap_launches() {
      touchTap(tile)
      tryCompare(homeStub, "launched", ["app0"])
      compare(homeStub.editRequests, 0)
    }

    function test_mouse_click_on_widget() {
      mouseClick(view, widget.x, widget.y)
      compare(view.widgetTaps, 1, "a click on a widget reaches it")
    }

    function test_mouse_hold_on_tile() {
      mouseHold(tile)
      compare(homeStub.editRequests, 1, "a held click asks for edit mode once")
      verify(homeStub.editing)
      compare(homeStub.launched, [], "and the release doesn't launch the app")
    }

    function test_touch_hold_on_tile() {
      touchHold(tile)
      compare(homeStub.editRequests, 1, "a held finger asks for edit mode once")
      verify(homeStub.editing)
      compare(homeStub.launched, [], "and the release doesn't launch the app")
    }

    function test_mouse_hold_on_widget() {
      mouseHold(widget)
      compare(homeStub.editRequests, 1)
      verify(homeStub.editing)
    }

    function test_mouse_hold_on_empty_space() {
      mouseHold(empty)
      compare(homeStub.editRequests, 1)
      verify(homeStub.editing)
    }

    function test_touch_hold_on_empty_space() {
      touchHold(empty)
      compare(homeStub.editRequests, 1)
      verify(homeStub.editing)
    }

    function test_mouse_hold_in_landscape() {
      homeStub.landscape = true
      mouseHold(tile)
      compare(homeStub.editRequests, 1)
      compare(homeStub.notices, ["Turn the phone upright to edit"], "the notice shows once")
      compare(homeStub.launched, [], "and the release launches nothing")
    }

    function test_touch_hold_in_landscape() {
      homeStub.landscape = true
      touchHold(tile)
      compare(homeStub.editRequests, 1)
      compare(homeStub.notices, ["Turn the phone upright to edit"], "the notice shows once")
      compare(homeStub.launched, [], "and the release launches nothing")
    }

    function test_mouse_drag_turns_the_page() {
      mousePress(view, 350, 500)
      for (var i = 1; i <= 12; i++) {
        mouseMove(view, 350 - i * 25, 500)
        wait(30)
      }
      wait(600)
      mouseRelease(view, 50, 500)
      compare(homeStub.editRequests, 0, "a drag is not a long press")
      tryCompare(pager, "currentIndex", 1)
    }

    function test_no_long_press_while_a_sheet_is_open() {
      homeStub.sheet = "apps"
      mouseHold(empty)
      touchHold(empty)
      compare(homeStub.editRequests, 0)
    }
  }
}
