// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import "home" as Home

ShellRoot {
  id: test
  Home.OwlPhoneHost { id: owlHost }
  Home.WidgetHost { id: qmlHost; capabilities: ["commands"] }
  property string url: Quickshell.env("FIXTURE_URL")
  property int remaining: 7
  property var cancelCommand: null
  property var cancelRequest: null
  property var captured: null

  function check(ok, message) {
    if (ok) return
    console.error("widget-host: " + message)
    Qt.exit(1)
    throw new Error(message)
  }
  function pass() {
    remaining--
    if (!remaining) { console.log("widget-host: PASS"); Qt.quit() }
  }

  Component.onCompleted: {
    // Upstream's new board information must keep a cancellable source.
    for (const kind of ["system", "device"]) {
      const request = owlHost.android(null, kind, function() { check(false, "cancelled board-info callback") })
      check(request && typeof request.stop === "function", kind + " returns its cancellation handle")
      request.stop()
    }
    owlHost.command(null, "python3 -c 'import sys; sys.stdout.write(\"x\"*3000000); sys.stderr.write(\"y\"*3000000)'", 5, function(r) {
      check(r.ok && r.out === "x".repeat(65536) && r.err === "y".repeat(65536), "command output is bounded on both pipes")
      pass()
    })
    qmlHost.run(["python3", "-c", "import sys,time; b='☕'.encode(); sys.stdout.buffer.write(b[:1]); sys.stdout.flush(); time.sleep(.05); sys.stdout.buffer.write(b[1:]+('é'*200000).encode())"], function(r) {
      check(r.code === 0 && r.stdout === "☕" + "é".repeat(32766), "QML commands preserve split UTF-8 and use the same byte bound")
      pass()
    })
    owlHost.get(url + "/small", {}, 3, {}, function(r) {
      check(r.ok && r.out === "small café ☕", "small HTTP response decodes correctly")
      pass()
    })
    owlHost.get(url + "/large", {}, 3, {}, function(r) {
      check(r.error === "the answer is over 1 MB", "HTTP is rejected during receipt, before timeout or EOF")
      pass()
    })
    owlHost.get(url + "/slow", {}, 0.1, { status: true }, function(r) {
      check(r.code === 124 && !r.ok && r.err === "timed out", "HTTP timeout retains status semantics")
      pass()
    })
    cancelRequest = owlHost.get(url + "/slow", {}, 3, {}, function() { check(false, "cancelled HTTP callback") })
    cancelCommand = owlHost.command(null, "sleep 1; touch \"$FIXTURE_DIR/cancelled-command-finished\"", 5,
                                    function() { check(false, "cancelled command callback") })
    // Inspect the collector while the command is still running, not just
    // its final callback: truncating only at exit would miss the problem.
    captured = collector.createObject(test)
    captured.running = true
    cancel.start()
    settle.start()
    deadline.start()
  }
  Component {
    id: collector
    Home.BoundedProcess {
      command: ["timeout", "-k", "2", "5", "bash", "-c", "python3 -c 'print(\"x\"*3000000, end=\"\")'; sleep 5"]
    }
  }
  Timer {
    id: cancel
    interval: 100
    onTriggered: { test.cancelRequest.stop(); test.cancelCommand.stop() }
  }
  Timer {
    id: settle
    interval: 1500
    onTriggered: {
      test.check(test.captured.running && test.captured.stdout === null && test.captured.out.length === 65536, "collector is bounded before exit")
      test.captured.stop()
      test.pass()
      owlHost.saveState("fixture", { count: 7 })
      stateCheck.start()
    }
  }
  Timer {
    id: stateCheck
    interval: 150
    onTriggered: {
      test.check(owlHost.loadState("fixture").count === 7, "first state save reaches disk")
      test.pass()
    }
  }
  Timer { id: deadline; interval: 6000; onTriggered: test.check(false, "test timed out") }
}
