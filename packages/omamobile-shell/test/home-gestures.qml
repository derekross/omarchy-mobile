// SPDX-License-Identifier: MIT
// The home screen's swipes (test/home-gestures runs this): the real
// HomePager.qml, DrawerSwipe.qml, AppTile.qml and LongPressEdit.qml, laid
// out as Home.qml lays them out, and the real DrawerLink.js and
// DrawerLinkClient.qml from omamobile.launcher, with a stand-in drawer that
// publishes itself through DrawerLink.js the way Launcher.qml does, from
// another file, and decides with the real LauncherModel.drawerEndsOpen.
import QtQuick
import QtTest
import "omamobile.home"

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
    property int editRequests: 0
    property int touches: 0
    function entryFor(app) { return { id: app + ".desktop", name: app, icon: "" } }
    function launch(app) { launched = launched.concat([app]); return true }
    function flash(text) { }
    function sawTouch() { touches++ }
    function requestEdit() { editRequests++; editing = true; return "editing" }
  }

  // The launcher's side: DrawerLinkClient.qml loaded from the launcher's
  // folder, as Home.qml loads it, and a drawer published from elsewhere.
  Loader { id: link; source: "omamobile.launcher/DrawerLinkClient.qml" }
  FakeDrawer { id: fakeDrawer }
  property bool linkOn: true
  readonly property var drawer: linkOn && link.item ? link.item.drawer : null
  property int fallbacks: 0
  // The clock finger speeds are measured by: advanced by the tests with
  // each move, so a speed never depends on how busy the machine is.
  property real now: 1000

  HomePager {
    id: pager
    anchors.fill: parent
    anchors.topMargin: 12
    anchors.bottomMargin: 28
    interactive: !homeStub.editing && homeStub.sheet === ""
    clock: function() { return view.now }
    model: 3

    delegate: Item {
      id: page
      required property int index
      width: pager.width
      height: pager.height

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
      // A widget that scrolls: a swipe up on it is its own.
      Flickable {
        objectName: "scroller" + page.index
        x: 0
        y: 400
        width: 412
        height: 200
        clip: true
        contentHeight: 800
        boundsBehavior: Flickable.StopAtBounds
        Rectangle { width: 412; height: 800; color: "#24283b" }
      }
    }
  }

  LongPressEdit {
    anchors.fill: pager
    z: 50
    home: homeStub
    active: !homeStub.editing && homeStub.sheet === ""
  }

  DrawerSwipe {
    id: swipe
    anchors.fill: pager
    z: 51
    home: homeStub
    pages: pager
    drawer: view.drawer
    clock: function() { return view.now }
    active: !homeStub.editing && homeStub.sheet === ""
    onFallbackOpen: view.fallbacks++
  }

  TestCase {
    id: test
    name: "HomeGestures"
    when: windowShown

    readonly property point tile: Qt.point(51, 12 + 55)
    readonly property point empty: Qt.point(300, 300)
    readonly property point scroller: Qt.point(200, 12 + 500)

    function init() {
      homeStub.editing = false
      homeStub.sheet = ""
      homeStub.launched = []
      homeStub.editRequests = 0
      view.linkOn = true
      view.fallbacks = 0
      fakeDrawer.reset()
      pager.goTo(0, false)
      waitForRendering(pager)
    }

    // A finger from p, moved by (dx, dy) in `steps` moves `ms` apart, then
    // held `hold` ms and lifted.
    function swipeFinger(p, dx, dy, steps, ms, hold) {
      var t = touchEvent(view)
      t.press(0, view, p.x, p.y).commit()
      for (var i = 1; i <= steps; i++) {
        wait(ms)
        view.now += ms
        t.move(0, view, p.x + dx * i / steps, p.y + dy * i / steps).commit()
      }
      if (hold) { wait(hold); view.now += hold }
      t.release(0, view, p.x + dx, p.y + dy).commit()
    }

    function test_link_reaches_the_drawer() {
      verify(link.item, "DrawerLinkClient.qml loads from the launcher's folder")
      compare(view.drawer, fakeDrawer, "the drawer published from another file is the client's: one DrawerLink.js")
    }

    function test_swipe_up_on_empty_space_follows_the_finger() {
      var t = touchEvent(view)
      t.press(0, view, empty.x, 700).commit()
      for (var i = 1; i <= 10; i++) {
        wait(20)
        view.now += 20
        t.move(0, view, empty.x, 700 - i * 30).commit()
      }
      // Touch moves are delivered with the next frame: wait for the last.
      tryVerify(function() { return Math.abs(fakeDrawer.travel - 300) <= 1 }, 5000, "the drawer follows the finger 1:1: " + fakeDrawer.travel)
      compare(fakeDrawer.begins, 1, "the drawer swipe began once")
      verify(swipe.swiping)
      wait(150)
      view.now += 150
      t.release(0, view, empty.x, 400).commit()
      compare(fakeDrawer.ends.length, 1)
      verify(Math.abs(fakeDrawer.ends[0]) < 50, "a finger held still lets go with no speed: " + fakeDrawer.ends[0])
      verify(fakeDrawer.opened, "past a quarter of the way it opens")
      compare(pager.page, 0, "and the page didn't move")
      compare(homeStub.launched, [])
      verify(homeStub.touches > 0, "a swipe proves the home screen shows")
    }

    function test_short_swipe_up_springs_back() {
      swipeFinger(empty, 0, -60, 6, 20, 150)
      compare(fakeDrawer.begins, 1)
      verify(!fakeDrawer.opened, "a short, slow swipe lets the drawer fall back")
    }

    function test_flick_up_opens() {
      swipeFinger(empty, 0, -80, 5, 16, 0)
      compare(fakeDrawer.begins, 1)
      verify(fakeDrawer.ends[0] < -350, "a flick up has its speed: " + fakeDrawer.ends[0])
      verify(fakeDrawer.opened, "a short flick up opens it")
    }

    function test_swipe_up_from_a_tile_does_not_launch() {
      swipeFinger(tile, 0, -250, 10, 20, 0)
      compare(fakeDrawer.begins, 1, "a swipe up from a tile is the drawer's")
      compare(homeStub.launched, [], "and the tile under it doesn't launch")
      compare(homeStub.editRequests, 0)
    }

    function test_tap_and_hold_still_work() {
      var t = touchEvent(view)
      // A tap with no wait in between: a busy machine can't stretch it
      // into a hold.
      t.press(0, view, tile.x, tile.y).commit()
      t.release(0, view, tile.x, tile.y).commit()
      tryCompare(homeStub, "launched", ["app0"])
      t.press(0, view, empty.x, empty.y).commit()
      tryCompare(homeStub, "editRequests", 1, 5000, "a hold still asks for edit mode")
      t.release(0, view, empty.x, empty.y).commit()
      compare(fakeDrawer.begins, 0, "neither is a drawer swipe")
    }

    function test_sideways_swipe_turns_the_page() {
      swipeFinger(Qt.point(350, 300), -300, -40, 12, 20, 0)
      compare(fakeDrawer.begins, 0, "a mostly sideways swipe is not the drawer's")
      compare(pager.page, 1)
      tryCompare(pager, "contentX", pager.width, 3000, "the slide settles within a short ease")
      compare(pager.currentIndex, 1)
    }

    function test_short_flick_turns_the_page() {
      swipeFinger(Qt.point(300, 300), -70, 0, 6, 16, 0)
      compare(pager.page, 1, "a short sideways flick turns the page")
      tryCompare(pager, "contentX", pager.width, 3000)
    }

    function test_short_slow_drag_springs_back() {
      swipeFinger(Qt.point(300, 300), -90, 0, 6, 25, 200)
      compare(pager.page, 0, "a short slow drag lets go back on its page")
      tryCompare(pager, "contentX", 0, 3000)
    }

    function test_flick_back_returns() {
      pager.goTo(1, false)
      swipeFinger(Qt.point(100, 300), 80, 0, 6, 16, 0)
      compare(pager.page, 0, "a flick toward the first page turns back to it")
      tryCompare(pager, "contentX", 0, 3000)
    }

    function test_settle_is_short() {
      swipeFinger(Qt.point(350, 300), -260, 0, 10, 20, 0)
      verify(pager.settling, "the release slides")
      tryCompare(pager, "contentX", pager.width, 3000)
      verify(!pager.settling)
    }

    function test_goTo_animates_and_jumps() {
      pager.goTo(2, true)
      compare(pager.page, 2)
      verify(pager.settling, "goTo with animation slides")
      tryCompare(pager, "contentX", pager.width * 2, 3000)
      pager.goTo(0, false)
      compare(pager.contentX, 0, "goTo without animation jumps")
    }

    function test_swipe_up_on_a_scrolling_widget_scrolls_it() {
      var flick = findChild(pager, "scroller0")
      verify(flick)
      swipeFinger(scroller, 0, -150, 10, 20, 0)
      compare(fakeDrawer.begins, 0, "a widget that scrolls keeps its swipe")
      verify(flick.contentY > 0, "and scrolls: " + flick.contentY)
    }

    function test_swipe_down_is_not_the_drawer() {
      swipeFinger(Qt.point(300, 200), 0, 200, 10, 20, 0)
      compare(fakeDrawer.begins, 0)
      compare(pager.page, 0)
    }

    function test_no_swipe_while_editing_or_with_a_sheet() {
      homeStub.editing = true
      swipeFinger(empty, 0, -250, 10, 20, 0)
      homeStub.editing = false
      homeStub.sheet = "apps"
      swipeFinger(empty, 0, -250, 10, 20, 0)
      compare(fakeDrawer.begins, 0)
    }

    function test_without_the_link_the_host_opens_it() {
      view.linkOn = false
      swipeFinger(empty, 0, -200, 10, 20, 0)
      compare(view.fallbacks, 1, "a swipe up opens the drawer through the host")
      swipeFinger(empty, 0, -40, 4, 30, 150)
      compare(view.fallbacks, 1, "a short one doesn't")
    }

    function test_mouse_drag_turns_the_page() {
      mousePress(view, 350, 500)
      for (var i = 1; i <= 12; i++) {
        mouseMove(view, 350 - i * 25, 500)
        wait(20)
        view.now += 20
      }
      mouseRelease(view, 50, 500)
      compare(pager.page, 1, "a mouse drag still turns the page")
      compare(fakeDrawer.begins, 0)
      tryCompare(pager, "contentX", pager.width, 3000)
    }
  }
}
