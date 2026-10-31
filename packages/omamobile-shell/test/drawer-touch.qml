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

  // The clock finger speeds are measured by: advanced by the tests with
  // each move, so a speed never depends on how busy the machine is.
  property real now: 1000
  DrawerHarness { id: harness; anchors.fill: parent; clock: function() { return view.now } }

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
      tryCompare(harness, "progress", 0, 3000)
      harness.calls = []
      harness.launched = []
      grid.contentY = 0
    }

    function openSettled() {
      harness.open("{}")
      tryCompare(harness, "progress", 1, 3000)
      harness.calls = []
      waitForRendering(sheet)
    }

    // A finger from p, moved by dy in `steps` moves `ms` apart, then held
    // `hold` ms and lifted (lift: false leaves it down).
    function drag(t, p, dy, steps, ms) {
      for (var i = 1; i <= steps; i++) {
        wait(ms)
        view.now += ms
        t.move(0, view, p.x, p.y + dy * i / steps).commit()
      }
    }

    function handleCentre() { return handle.mapToItem(view, handle.width / 2, handle.height / 2) }

    function test_open_settles_with_the_field_focused() {
      openSettled()
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
      t.release(0, view, c.x, c.y).commit()
      compare(harness.calls, ["hide"])
      verify(!harness.opened)
      tryCompare(harness, "progress", 0, 3000)
    }

    function test_handle_drag_follows_and_springs_back() {
      openSettled()
      var c = handleCentre()
      var t = touchEvent(view)
      t.press(0, view, c.x, c.y).commit()
      drag(t, c, 200, 10, 20)
      tryVerify(function() { return harness.pulling }, 5000, "the handle pulls the drawer")
      tryVerify(function() { return harness.progress < 0.85 && harness.progress > 0.7 }, 5000, "it follows the finger: " + harness.progress)
      fuzzyCompare(sheet.y, (1 - harness.progress) * sheet.height, 1)
      // Back up, held still, lifted: it stays open.
      for (var i = 1; i <= 10; i++) { wait(20); view.now += 20; t.move(0, view, c.x, c.y + 200 - i * 19).commit() }
      tryVerify(function() { return harness.progress > 0.97 }, 5000, "and back up with it: " + harness.progress)
      wait(150)
      view.now += 150
      t.release(0, view, c.x, c.y + 10).commit()
      compare(harness.calls, [])
      tryCompare(harness, "progress", 1, 3000)
      verify(harness.opened)
    }

    function test_slow_pull_past_a_tenth_closes() {
      openSettled()
      var c = handleCentre()
      var t = touchEvent(view)
      t.press(0, view, c.x, c.y).commit()
      drag(t, c, 200, 10, 20)
      wait(150)
      view.now += 150
      t.release(0, view, c.x, c.y + 200).commit()
      compare(harness.calls, ["hide"])
      tryCompare(harness, "progress", 0, 3000)
    }

    function test_short_slow_pull_springs_back() {
      openSettled()
      var c = Qt.point(300, 120)
      var t = touchEvent(view)
      t.press(0, view, c.x, c.y).commit()
      drag(t, c, 50, 5, 30)
      tryVerify(function() { return harness.progress < 1 }, 5000, "the grid at its top pulls the drawer")
      wait(150)
      view.now += 150
      t.release(0, view, c.x, c.y + 50).commit()
      compare(harness.calls, [])
      tryCompare(harness, "progress", 1, 3000)
    }

    function test_flick_down_on_the_grid_closes() {
      openSettled()
      var c = Qt.point(300, 120)
      var t = touchEvent(view)
      t.press(0, view, c.x, c.y).commit()
      drag(t, c, 60, 5, 16)
      t.release(0, view, c.x, c.y + 60).commit()
      compare(harness.calls, ["hide"], "a short flick down closes")
      tryCompare(harness, "progress", 0, 3000)
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
      for (var i = 1; i <= 15; i++) { wait(20); view.now += 20; t.move(0, view, c.x, c.y + 100 + i * 20).commit() }
      tryCompare(grid, "contentY", 0, 5000, "the grid reached its top")
      tryVerify(function() { return harness.progress < 0.95 }, 5000, "and the pull took over: " + harness.progress)
      wait(150)
      view.now += 150
      t.release(0, view, c.x, c.y + 400).commit()
      tryCompare(harness, "progress", 0, 3000)
    }

    function test_an_app_still_takes_its_tap() {
      openSettled()
      var t = touchEvent(view)
      t.press(0, view, 60, 110).commit()
      t.release(0, view, 60, 110).commit()
      tryCompare(harness, "launched", ["app00"])
    }

    function test_home_swipe_opens_from_under_the_finger() {
      verify(harness.gestureBegin(), "a closed drawer takes the swipe")
      harness.gestureMove(300)
      fuzzyCompare(harness.progress, 300 / sheet.height, 0.001)
      fuzzyCompare(sheet.y, sheet.height - 300, 1, "the sheet's top is where the finger has brought it")
      verify(harness.gestureEnd(-800), "a flick up opens it")
      compare(harness.calls, ["summon {\"gesture\":true}"], "through the host")
      verify(harness.opened)
      tryCompare(harness, "progress", 1, 3000)
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
      tryCompare(harness, "progress", 0, 3000)
    }

    // Where the grid, its first cell, the header and the search row sit on
    // the sheet, and the sheet's size: none of it may change as the drawer
    // moves (only the sheet's y does), or the first row jumps at the start
    // of a pull or the end of a slide.
    function layoutOf() {
      var cell = findChild(grid, "app-app00")
      var inputRow = findChild(harness, "inputRow")
      return JSON.stringify({
        sheet: [sheet.width, sheet.height],
        grid: [grid.x, grid.y, grid.width, grid.height],
        cell: cell ? [cell.mapToItem(sheet, 0, 0).x, cell.mapToItem(sheet, 0, 0).y] : null,
        header: findChild(harness, "drawerHeader").height,
        input: [inputRow.y, inputRow.height, inputRow.opacity, inputRow.visible]
      })
    }

    function test_nothing_moves_on_the_sheet_but_the_sheet() {
      var closed = layoutOf()
      harness.gestureBegin()
      harness.gestureMove(300)
      compare(layoutOf(), closed, "mid-swipe")
      harness.gestureEnd(-800)
      compare(layoutOf(), closed, "settling open")
      tryCompare(harness, "progress", 1, 3000)
      wait(200)
      compare(layoutOf(), closed, "open and settled")
      var c = handleCentre()
      var t = touchEvent(view)
      t.press(0, view, c.x, c.y).commit()
      compare(layoutOf(), closed, "a finger on the handle")
      drag(t, c, 120, 6, 20)
      tryVerify(function() { return harness.pulling }, 5000)
      compare(layoutOf(), closed, "mid-pull")
      view.now += 150
      t.release(0, view, c.x, c.y + 120).commit()
      tryCompare(harness, "progress", 0, 3000)
      compare(layoutOf(), closed, "closed again")
    }

    function test_no_home_swipe_while_open() {
      openSettled()
      verify(!harness.gestureBegin(), "an open drawer ignores the home screen's swipe")
    }
  }
}
