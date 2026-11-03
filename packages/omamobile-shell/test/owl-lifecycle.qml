// SPDX-License-Identifier: MIT
import QtQuick
import QtTest
import "owl"

TestCase {
  id: test
  name: "OwlLifecycle"
  when: windowShown
  property var widget: null
  property var requests: []
  property var writes: []
  property var saved: ({})
  property int cancelled: 0
  property bool setOnLoad: false

  QtObject {
    id: fixtureHost
    function now() { return 1000 }
    function interval(spec) { return spec.every }
    function loadState(key) { return test.saved }
    function saveState(key, data) {
      test.saved = data
      test.writes.push(data)
    }
    function report(widget, message) { console.warn(message) }
    function runSource(widget, spec, arg, headers, done) {
      test.requests.push(done)
      return { stop: function() { test.cancelled++ } }
    }
    function runInto(widget, command, done) { test.requests.push(done) }
    function stream(widget, spec, arg, onValue) {
      test.requests.push(onValue)
      return { stop: function() { test.cancelled++ } }
    }
  }

  Component {
    id: widgetComponent
    OwlWidget {
      host: fixtureHost
      stateKey: "fixture"
      // OwlCell fills the initial location from this signal.
      onInstanceChanged: if (test.setOnLoad && instance) setStateValue("count", 7)
    }
  }

  function init() {
    requests = []; writes = []; saved = ({}); cancelled = 0; setOnLoad = false
    widget = createTemporaryObject(widgetComponent, test)
    verify(widget !== null)
    load('source n = cmd("fixture") every 1s\nstate count = 0 persist')
  }
  function cleanup() { widget.destroy(); widget = null }
  function load(body) {
    widget.text = 'widget "test" {\n' + body + '\nText { text: "test" }\n}'
    wait(0)
    verify(widget.instance !== null, widget.error)
  }
  function answer(callback, value) { callback({ ok: true, code: 0, out: value, err: "" }) }

  function test_reload_discards_old_source_and_action_results() {
    widget.active = true
    const oldSource = requests[0]
    widget.bridge.runInto("fixture", widget.instance.stateSlot("count"))
    const oldAction = requests[1]
    load('source n = cmd("replacement") every 1s\nstate count = 0 persist')
    compare(requests.length, 3, "the replacement starts its own source")
    answer(oldSource, "old")
    oldAction("old")
    compare(widget.stateValue("count"), 0, "an old action cannot update the replacement")
    compare(widget.instance.values[0], null, "an old source cannot update the replacement")
    widget.tick(1002)
    compare(requests.length, 3, "an old completion cannot clear the new request's busy flag")
    answer(requests[2], "new")
    compare(widget.instance.values[0], "new")
    compare(cancelled, 1, "reload cancels the previous source")
  }

  function test_source_updates_do_not_write_unchanged_state() {
    widget.active = true
    answer(requests[0], "one")
    widget.tick(1001)
    answer(requests[1], "two")
    wait(1150)
    compare(writes.length, 0, "source values are not persisted")
    widget.setStateValue("count", 1)
    tryCompare(test, "saved", { count: 1 }, 1600)
    compare(writes.length, 1)
    widget.setStateValue("count", 1)
    wait(1150)
    compare(writes.length, 1, "setting the same persisted value does not write again")
  }

  function test_frequent_history_updates_cannot_postpone_saving_forever() {
    load('source n = stream("fixture")\nlet samples = history(n, 3) persist')
    widget.active = true
    for (let i = 0; i < 7; i++) { requests[0](String(i)); wait(200) }
    verify(writes.length > 0, "a busy stream saves within the interval")
    widget.saveNow()
    compare(saved.samples, ["4", "5", "6"], "persisted history keeps the newest samples")
  }

  function test_reload_flushes_pending_state() {
    widget.setStateValue("count", 8)
    load('state count = 0 persist')
    compare(widget.stateValue("count"), 8)
    compare(writes.length, 1)
  }

  function test_state_set_by_the_host_on_load_is_saved() {
    setOnLoad = true
    load('state count = 0 persist')
    compare(widget.stateValue("count"), 7)
    tryCompare(test, "saved", { count: 7 }, 1600)
  }

  function test_stopped_stream_cannot_update_a_new_subscription() {
    load('source n = stream("fixture")')
    widget.active = true
    const old = requests[0]
    widget.active = false
    widget.active = true
    old("stale")
    compare(widget.instance.values[0], null)
    requests[1]("fresh")
    compare(widget.instance.values[0], "fresh")
  }
}
