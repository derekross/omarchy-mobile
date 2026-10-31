// SPDX-License-Identifier: MIT
// The app drawer under a finger (test/drawer-touch runs this): the drawer
// window's content and its position, open, close and gesture functions
// from Launcher.qml (launcher/DrawerHarness.qml, cut out by the script).
import QtQuick
import QtTest
import "launcher"

Item {
  id: view
  width: 412
  height: 892

  DrawerHarness { id: harness; anchors.fill: parent }

  TestCase {
    id: test
    name: "DrawerTouch"
    when: windowShown

    property Item sheet: null
    property Item grid: null
    property Item handle: null
    property Item input: null

    function initTestCase() {
      var apps = []
      for (var i = 0; i < 40; i++) apps.push({ id: "app" + (i < 10 ? "0" : "") + i, name: "App " + i, icon: "" })
      harness.apps = apps
      sheet = findChild(harness, "drawer")
      grid = findChild(harness, "drawerGrid")
      handle = findChild(harness, "drawerHandle")
      input = findChild(harness, "inputRow").children[0]
      verify(sheet && grid && handle && input)
    }

    function init() {
      harness.close()
      tryCompare(harness, "progress", 0, 1000)
      tryCompare(harness, "dockAway", false, 1000)
      harness.calls = []
      harness.launched = []
      grid.contentY = 0
    }

    function openSettled() {
      harness.open("{}")
      tryCompare(harness, "progress", 1, 1000)
      tryCompare(harness, "dockAway", true, 1000)
      harness.calls = []
      waitForRendering(sheet)
    }

    // A finger from p, moved by dy in `steps` moves `ms` apart, then held
    // `hold` ms and lifted (lift: false leaves it down).
    function drag(t, p, dy, steps, ms) {
      for (var i = 1; i <= steps; i++) {
        wait(ms)
        t.move(0, view, p.x, p.y + dy * i / steps).commit()
      }
    }

    function handleCentre() { return handle.mapToItem(view, handle.width / 2, handle.height / 2) }

    function test_open_settles_with_the_field_focused() {
      var started = Date.now()
      openSettled()
      verify(Date.now() - started < 1000, "opened in " + (Date.now() - started) + " ms")
      verify(harness.opened)
      verify(input.activeFocus, "a tap on the dock focuses the search field")
      compare(sheet.y, 0)
    }

    function test_the_handle_is_a_centred_pill_with_a_full_target() {
      openSettled()
      verify(handle.height >= 44 && handle.width >= 44, "handle " + handle.width + "x" + handle.height)
      fuzzyCompare(handleCentre().x, view.width / 2, 1, "centred")
      verify(handleCentre().y < 50, "at the top")
      compare(findChild(harness, "collapse"), null, "no chevron any more")
    }

    function test_tap_on_the_handle_closes() {
      openSettled()
      var c = handleCentre()
      var t = touchEvent(view)
      t.press(0, view, c.x, c.y).commit()
      wait(40)
      t.release(0, view, c.x, c.y).commit()
      compare(harness.calls, ["hide"])
      verify(!harness.opened)
      tryCompare(harness, "progress", 0, 1000)
    }

    function test_handle_drag_follows_and_springs_back() {
      openSettled()
      var c = handleCentre()
      var t = touchEvent(view)
      t.press(0, view, c.x, c.y).commit()
      drag(t, c, 200, 10, 20)
      verify(harness.pulling, "the handle pulls the drawer")
      verify(harness.progress < 0.85 && harness.progress > 0.7, "it follows the finger: " + harness.progress)
      fuzzyCompare(sheet.y, (1 - harness.progress) * sheet.height, 1)
      // Back up, held still, lifted: it stays open.
      for (var i = 1; i <= 10; i++) { wait(20); t.move(0, view, c.x, c.y + 200 - i * 19).commit() }
      verify(harness.progress > 0.97, "and back up with it: " + harness.progress)
      wait(150)
      t.release(0, view, c.x, c.y + 10).commit()
      compare(harness.calls, [])
      tryCompare(harness, "progress", 1, 1000)
      verify(harness.opened)
    }

    function test_slow_pull_past_a_tenth_closes() {
      openSettled()
      var c = handleCentre()
      var t = touchEvent(view)
      t.press(0, view, c.x, c.y).commit()
      drag(t, c, 200, 10, 20)
      wait(150)
      t.release(0, view, c.x, c.y + 200).commit()
      compare(harness.calls, ["hide"])
      tryCompare(harness, "progress", 0, 1000)
    }

    function test_short_slow_pull_springs_back() {
      openSettled()
      var c = Qt.point(300, 120)
      var t = touchEvent(view)
      t.press(0, view, c.x, c.y).commit()
      drag(t, c, 50, 5, 30)
      verify(harness.progress < 1, "the grid at its top pulls the drawer")
      wait(150)
      t.release(0, view, c.x, c.y + 50).commit()
      compare(harness.calls, [])
      tryCompare(harness, "progress", 1, 1000)
    }

    function test_flick_down_on_the_grid_closes() {
      openSettled()
      var c = Qt.point(300, 120)
      var t = touchEvent(view)
      t.press(0, view, c.x, c.y).commit()
      drag(t, c, 60, 5, 16)
      t.release(0, view, c.x, c.y + 60).commit()
      compare(harness.calls, ["hide"], "a short flick down closes")
      tryCompare(harness, "progress", 0, 1000)
    }

    function test_a_scrolled_grid_scrolls_first() {
      openSettled()
      grid.contentY = 150
      var c = Qt.point(200, 300)
      var t = touchEvent(view)
      t.press(0, view, c.x, c.y).commit()
      drag(t, c, 100, 5, 20)
      compare(harness.progress, 1, "the grid scrolls, the drawer stays")
      verify(grid.contentY < 150 && grid.contentY > 0, "grid at " + grid.contentY)
      for (var i = 1; i <= 15; i++) { wait(20); t.move(0, view, c.x, c.y + 100 + i * 20).commit() }
      compare(grid.contentY, 0, "the grid reached its top")
      verify(harness.progress < 0.95, "and the pull took over: " + harness.progress)
      wait(150)
      t.release(0, view, c.x, c.y + 400).commit()
      tryCompare(harness, "progress", 0, 1000)
    }

    function test_an_app_still_takes_its_tap() {
      openSettled()
      var t = touchEvent(view)
      t.press(0, view, 60, 110).commit()
      wait(40)
      t.release(0, view, 60, 110).commit()
      tryCompare(harness, "launched", ["app00"])
    }

    function test_home_swipe_opens_from_under_the_finger() {
      verify(harness.gestureBegin(), "a closed drawer takes the swipe")
      harness.gestureMove(300)
      fuzzyCompare(harness.progress, 300 / sheet.height, 0.001)
      fuzzyCompare(sheet.y, sheet.height - 300, 1, "the sheet's top is where the finger has brought it")
      verify(!harness.dockAway, "the dock stays under the sliding sheet")
      verify(harness.gestureEnd(-800), "a flick up opens it")
      compare(harness.calls, ["summon {\"gesture\":true}"], "through the host")
      verify(harness.opened)
      verify(!harness.dockAway, "the dock stays until it is open")
      tryCompare(harness, "progress", 1, 1000)
      tryCompare(harness, "dockAway", true, 1000)
      verify(!input.activeFocus, "no keyboard after a swipe")
      keyClick(Qt.Key_A)
      compare(harness.query, "a", "typing on a keyboard still searches")
      verify(input.activeFocus)
    }

    function test_home_swipe_falls_back() {
      harness.gestureBegin()
      harness.gestureMove(100)
      verify(!harness.gestureEnd(0), "a short slow swipe doesn't open it")
      compare(harness.calls, [])
      verify(!harness.opened)
      tryCompare(harness, "progress", 0, 1000)
    }

    function test_no_home_swipe_while_open() {
      openSettled()
      verify(!harness.gestureBegin(), "an open drawer ignores the home screen's swipe")
    }
  }
}
