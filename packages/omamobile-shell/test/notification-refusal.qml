// SPDX-License-Identifier: MIT
// Actual QuickSettings queue/completion/read callbacks are inserted by
// notification-refusal.py. Only process and IPC values are inert; rows and
// pointer gestures are real, including delegate preservation on unchanged reads.
import QtQuick
import QtTest
import Quickshell
import "quicksettings/NotificationsModel.js" as NotificationsModel
import "quicksettings"

Item {
  id: top
  width: 412
  height: 892

  QtObject {
    id: root
    property color foreground: "#c0caf5"
    property double nowMs: Date.now()
    property var notifications: []
    property bool clearing: false
    property var forgetQueue: []
    property var pendingForget: null
    property var hiddenNotifications: ({})
    property var notificationFiles: []
    property string notificationDeleteError: ""
    property bool opened: false
    property double seenStamp: 0
    property string rawNotifications: ""
    function writeSeen() {}

    function openNotification(entry) {}
    signal notificationForgetFailed(string key)

    // PRODUCTION_CALLBACKS

  }

  QtObject { id: clearProc; property bool running: false }
  QtObject { id: forgetProc; property bool running: false; property var command: [] }
  QtObject { id: forgetResult; property string text: "" }
  QtObject { id: notificationsLater; function restart() {} }
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
        model: root.notifications
        delegate: NotificationRow {
          host: root
          entry: modelData
          width: rows.width
          swipeEnabled: !list.moving && !root.clearing
          clearing: root.clearing
        }
      }
    }
  }

  TestCase {
    id: test
    name: "NotificationRefusal"
    when: windowShown

    function fill(n) {
      var lines = []
      for (var i = 0; i < n; i++)
        lines.push(JSON.stringify({ id: i + 1, originalId: i + 1, app: "app" + i, summary: "Note " + i,
                                    body: "Body of note " + i + " that runs on to a second line of text",
                                    execArgv: JSON.stringify(["omarchy-launch-" + i]), urgency: 1,
                                    timestamp: 1760000000000 + i * 1000 }))
      root.rawNotifications = lines.join("\n")
      root.notifications = NotificationsModel.parse(root.rawNotifications)
      root.clearing = false
      root.forgetQueue = []
      root.pendingForget = null
      root.hiddenNotifications = ({})
      root.notificationDeleteError = ""
      forgetProc.running = false
      forgetResult.text = ""
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

    function test_refusal_restores_only_the_rejected_row() {
      fill(3)
      var first = rowAt(0), second = rowAt(1)
      drag(first, 40, first.height / 2, 260, 0, 12, 16)
      tryVerify(function() { return root.pendingForget !== null }, 2000)
      var firstKey = first.entry.key, secondKey = second.entry.key
      drag(second, 40, second.height / 2, 260, 0, 12, 16)
      tryVerify(function() { return root.forgetQueue.length === 1 }, 2000)
      compare(first.fold, 0)
      compare(second.fold, 0)
      forgetProc.running = false
      forgetResult.text = "busy"
      root.forgetDone(1)
      root.readDone(root.rawNotifications)
      tryCompare(first, "swipeOffset", 0, 1000)
      compare(first.fold, 1, "the rejected row returns")
      compare(second.fold, 0, "the other accepted row stays folded")
      compare(rowAt(0), first)
      compare(rowAt(1), second)
      compare(root.pendingForget.key, secondKey, "the queue continues")
      verify(firstKey !== secondKey)
      forgetProc.running = false
      forgetResult.text = "ok"
      root.forgetDone(0)
      tryCompare(repeater, "count", 2)
      verify(root.notifications.some(function(entry) { return entry.key === firstKey }))
      verify(!root.notifications.some(function(entry) { return entry.key === secondKey }))
    }

    function test_async_refusal_restores_the_real_row() {
      fill(3)
      var row = rowAt(0)
      drag(row, 40, row.height / 2, 260, 0, 12, 16)
      tryVerify(function() { return root.pendingForget !== null }, 2000)
      compare(row.fold, 0, "row folded before reply")
      compare(root.notifications.length, 3)
      forgetProc.running = false
      forgetResult.text = "busy"
      root.forgetDone(1)
      verify(root.notificationDeleteError !== "")
      root.readDone(root.rawNotifications)
      compare(repeater.count, 3)
      compare(rowAt(0), row, "unchanged read preserves delegate")
      tryCompare(row, "swipeOffset", 0, 1000)
      compare(row.fold, 1, "IPC refusal must restore folded row")
      verify(row.visible)
      verify(!row.dismissing)
    }
  }
}
