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
    function openNotification(entry) { opened = opened.concat([entry.key]) }
    function forgetNotification(entry) {
      forgotten = forgotten.concat([entry.file])
      Qt.callLater(function() { sheet.notifications = NotificationsModel.without(sheet.notifications, entry.key) })
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
          swipeEnabled: !list.moving
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
