// SPDX-License-Identifier: MIT
// The quick-settings shade's rows under a finger (test/shade-touch runs
// this): NotificationRow.qml in a list built as the shade builds it (a
// Flickable over a Column of a Repeater), with a stand-in for the sheet that
// records what the rows ask of it and forgets as QuickSettings.qml does.
import QtQuick
import QtTest
import "quicksettings/NotificationsModel.js" as NotificationsModel
import "quicksettings"

Item {
  id: top
  width: 412
  height: 892

  QtObject {
    id: sheet
    property color foreground: "#c0caf5"
    property double nowMs: Date.now()
    property var notifications: []
    property var opened: []
    property var forgotten: []
    property bool clearing: false
    property bool rejectForget: false
    property bool holdReply: false
    property var pendingEntry: null
    function openNotification(entry) { opened = opened.concat([entry.key]) }
    function forgetNotification(entry) {
      if (clearing || rejectForget) return false
      forgotten = forgotten.concat([entry.file])
      if (holdReply) pendingEntry = entry
      else Qt.callLater(function() { sheet.notifications = NotificationsModel.without(sheet.notifications, entry.key) })
      return true
    }
  }

  Flickable {
    id: list
    x: 16
    y: 100
    width: 380
    height: 300
    contentWidth: width
    contentHeight: rows.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: rows
      width: list.width
      spacing: 4

      Repeater {
        id: repeater
        model: sheet.notifications
        delegate: NotificationRow {
          host: sheet
          entry: modelData
          width: rows.width
          swipeEnabled: !list.moving && !sheet.clearing
          clearing: sheet.clearing
        }
      }
    }
  }

  TestCase {
    id: test
    name: "ShadeTouch"
    when: windowShown

    function fill(n) {
      var lines = []
      for (var i = 0; i < n; i++)
        lines.push(JSON.stringify({ id: i + 1, originalId: i + 1, app: "app" + i, summary: "Note " + i,
                                    body: "Body of note " + i + " that runs on to a second line of text",
                                    execArgv: JSON.stringify(["omarchy-launch-" + i]), urgency: 1,
                                    timestamp: 1760000000000 + i * 1000 }))
      sheet.notifications = NotificationsModel.parse(lines.join("\n"))
      sheet.clearing = false
      sheet.rejectForget = false
      sheet.holdReply = false
      sheet.pendingEntry = null
      sheet.opened = []
      sheet.forgotten = []
      list.contentY = 0
      tryCompare(repeater, "count", n)
      waitForRendering(list)
    }

    function rowAt(i) { return repeater.itemAt(i) }

    // A finger from (x, y) on the row, moved by (dx, dy) in steps.
    function drag(item, x, y, dx, dy, steps, stepMs) {
      var t = touchEvent(top)
      var p = item.mapToItem(top, x, y)
      t.press(0, top, p.x, p.y).commit()
      for (var s = 1; s <= steps; s++) {
        wait(stepMs)
        t.move(0, top, p.x + dx * s / steps, p.y + dy * s / steps).commit()
      }
      wait(stepMs)
      t.release(0, top, p.x + dx, p.y + dy).commit()
    }

    function test_a_tap_runs_the_rows_action() {
      fill(3)
      var row = rowAt(1)
      var t = touchEvent(top)
      var p = row.mapToItem(top, row.width / 2, row.height / 2)
      t.press(0, top, p.x, p.y).commit()
      t.release(0, top, p.x, p.y).commit()
      tryVerify(function() { return sheet.opened.length === 1 })
      compare(sheet.opened[0], row.entry.key)
      compare(sheet.forgotten.length, 0)
      compare(row.swipeOffset, 0)
    }

    function test_a_swipe_takes_one_notification_away() {
      fill(3)
      var row = rowAt(0)
      var key = row.entry.key, file = row.entry.file
      drag(row, 40, row.height / 2, 260, 0, 12, 16)
      tryVerify(function() { return sheet.forgotten.length === 1 }, 2000)
      compare(sheet.forgotten[0], file)
      tryCompare(repeater, "count", 2)
      compare(sheet.opened.length, 0, "the swipe didn't also tap")
      for (var i = 0; i < repeater.count; i++) verify(rowAt(i).entry.key !== key)
    }

    function test_a_swipe_left_also_takes_it_away() {
      fill(2)
      var row = rowAt(1)
      var file = row.entry.file
      drag(row, row.width - 40, row.height / 2, -260, 0, 12, 16)
      tryVerify(function() { return sheet.forgotten.length === 1 }, 2000)
      compare(sheet.forgotten[0], file)
    }

    function test_the_gap_closes_as_it_goes() {
      fill(3)
      var row = rowAt(0)
      var below = rowAt(1)
      var start = below.y
      drag(row, 40, row.height / 2, 260, 0, 12, 16)
      tryVerify(function() { return row.fold < 1 }, 1000, "the row folds")
      tryVerify(function() { return sheet.forgotten.length === 1 }, 2000)
      tryCompare(repeater, "count", 2)
      tryVerify(function() { return rowAt(0).y < start }, 1000, "the next row moves up")
    }

    function test_clear_in_progress_keeps_the_row_visible() {
      fill(3)
      sheet.clearing = true
      var row = rowAt(0)
      drag(row, 40, row.height / 2, 260, 0, 12, 16)
      wait(400)
      compare(row.fold, 1)
      compare(row.swipeOffset, 0)
      verify(row.visible)
      compare(sheet.forgotten.length, 0)
      compare(repeater.count, 3)
    }

    function test_clear_starting_during_fly_off_restores_the_row() {
      fill(3)
      var row = rowAt(0)
      drag(row, 40, row.height / 2, 260, 0, 12, 16)
      verify(row.dismissing)
      sheet.clearing = true
      tryCompare(row, "swipeOffset", 0, 1000)
      compare(row.fold, 1)
      verify(row.visible)
      verify(!row.dismissing)
      compare(sheet.forgotten.length, 0)
      compare(repeater.count, 3)
    }

    function test_refused_forget_restores_fold_and_position_without_refresh() {
      fill(3)
      sheet.rejectForget = true
      var row = rowAt(0)
      drag(row, 40, row.height / 2, 260, 0, 12, 16)
      tryVerify(function() { return !row.dismissing }, 2000)
      tryCompare(row, "swipeOffset", 0, 1000)
      compare(row.fold, 1)
      verify(row.visible)
      compare(sheet.forgotten.length, 0)
      compare(repeater.count, 3)
    }

    function test_swipe_then_immediate_scroll_still_forgets_the_row() {
      fill(10)
      var row = rowAt(0)
      var key = row.entry.key, file = row.entry.file
      drag(row, 40, row.height / 2, 260, 0, 12, 16)
      verify(row.dismissing)
      compare(sheet.forgotten.length, 0, "the fly-off has not sent the request yet")
      // Start a real vertical gesture while the dismissed row is flying off.
      drag(list, list.width / 2, 220, 0, -180, 12, 16)
      tryVerify(function() { return list.contentY > 40 }, 1000)
      tryVerify(function() { return sheet.forgotten.length === 1 }, 2000)
      compare(sheet.forgotten[0], file)
      tryCompare(repeater, "count", 9)
      for (var i = 0; i < repeater.count; i++) verify(rowAt(i).entry.key !== key)
    }

    function test_scrolling_while_reply_is_pending_keeps_the_row_folded() {
      fill(10)
      sheet.holdReply = true
      var row = rowAt(0)
      var key = row.entry.key
      drag(row, 40, row.height / 2, 260, 0, 12, 16)
      tryVerify(function() { return sheet.forgotten.length === 1 }, 2000)
      compare(row.fold, 0)
      compare(repeater.count, 10, "the service reply is still pending")
      drag(list, list.width / 2, 220, 0, -180, 12, 16)
      tryVerify(function() { return list.contentY > 40 }, 1000)
      compare(row.fold, 0, "scrolling does not unfold an accepted swipe")
      verify(!row.visible)
      compare(sheet.forgotten.length, 1)
      // Clear all also cannot resurrect a row whose request was accepted.
      sheet.clearing = true
      compare(row.fold, 0)
      sheet.notifications = NotificationsModel.without(sheet.notifications, sheet.pendingEntry.key)
      tryCompare(repeater, "count", 9)
      for (var i = 0; i < repeater.count; i++) verify(rowAt(i).entry.key !== key)
    }

    function test_a_short_swipe_springs_back() {
      fill(3)
      var row = rowAt(0)
      drag(row, 40, row.height / 2, 80, 0, 16, 40)
      tryCompare(row, "swipeOffset", 0, 1000)
      wait(300)
      compare(sheet.forgotten.length, 0)
      compare(sheet.opened.length, 0, "nor is it a tap")
      compare(repeater.count, 3)
      verify(!row.dismissing)
    }

    function test_a_vertical_drag_scrolls_the_list() {
      fill(8)
      verify(list.contentHeight > list.height, "more rows than fit")
      var row = rowAt(1)
      drag(row, row.width / 2, row.height / 2, 0, -180, 12, 16)
      tryVerify(function() { return list.contentY > 40 }, 1000, "the list scrolled")
      wait(400)
      compare(sheet.forgotten.length, 0)
      compare(sheet.opened.length, 0)
      for (var i = 0; i < repeater.count; i++) compare(rowAt(i).swipeOffset, 0)
    }
  }
}
