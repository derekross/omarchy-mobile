// SPDX-License-Identifier: MIT
import QtQuick
import QtTest
import "launcher"

Item {
  id: view
  width: 420
  height: 900
  QtObject {
    id: library
    property var all: [({ id: "example.calendar", name: "Calendar", icon: "" }),
                       ({ id: "example.notes", name: "Notes", icon: "" }),
                       ({ id: "example.files", name: "Files", icon: "" })]
    property string lastQuery: ""
    function sortedEntries(query) {
      lastQuery = query
      return all.filter(function(entry) { return entry.name.toLowerCase().indexOf(query.toLowerCase()) >= 0 })
        .map(function(entry) { return {entry: entry} })
    }
    function entryName(entry) { return entry.name }
    function iconSource(icon) { return "" }
  }
  SearchFocus { id: focus; opened: search.opened; requestGeneration: search.focusGeneration; backingWindowVisible: true }
  AppsSearch { inputReady: focus.inputReady; id: search; anchors.fill: parent; appLibrary: library; surfaceActive: true; transitionDuration: 0 }
  SignalSpy { id: inputSpy; target: search; signalName: "inputRequested" }
  SignalSpy { id: closeSpy; target: search; signalName: "dismissed" }
  SignalSpy { id: appSpy; target: search; signalName: "activated" }
  TestCase {
    name: "AppsSearch"
    when: windowShown
    property Item field: null
    function initTestCase() { field = findChild(search, "appsSearchInput"); verify(field) }
    function init() {
      search.close()
      search.sessionLocked = false
      search.surfaceActive = true
      focus.backingWindowVisible = true
      view.width = 420; view.height = 900
      inputSpy.clear(); closeSpy.clear(); appSpy.clear()
    }
    function test_known_lock_cancels_initial_prime_and_requires_new_tap() {
      search.surfaceActive = false
      search.open("")
      var generation = search.focusGeneration
      compare(focus.mode, "exclusive")
      search.sessionLocked = true
      verify(!search.opened)
      verify(search.focusGeneration > generation)
      compare(focus.mode, "none")
      verify(!search.focusPending)
      search.open("ignored")
      verify(!search.opened)
      search.sessionLocked = false
      search.surfaceActive = true
      wait(110)
      compare(inputSpy.count, 0)
      verify(!search.opened)
      search.open("fresh")
      tryCompare(inputSpy, "count", 1)
    }
    function test_known_lock_cancels_actual_queued_input_callback() {
      search.surfaceActive = false
      search.open("")
      tryCompare(focus, "mode", "on-demand")
      search.surfaceActive = true // actual callback queued, not yet delivered
      search.sessionLocked = true
      search.sessionLocked = false
      wait(100)
      compare(inputSpy.count, 0)
      verify(!search.opened)
      verify(!field.activeFocus)
      compare(focus.mode, "none")
    }
    function test_known_lock_closes_after_input_focus() {
      search.open("")
      tryCompare(inputSpy, "count", 1)
      search.sessionLocked = true
      verify(!search.opened)
      compare(focus.mode, "none")
      verify(!field.activeFocus)
      search.sessionLocked = false
      wait(100)
      verify(!search.opened)
      compare(inputSpy.count, 2) // one show, one release; no unlock show
    }
    function test_mapped_surface_is_primed_on_each_open_and_releases_on_close() {
      search.open("")
      compare(focus.mode, "exclusive")
      tryCompare(focus, "mode", "on-demand")
      tryCompare(inputSpy, "count", 1)
      search.close()
      compare(focus.mode, "none")
      search.open("")
      compare(focus.mode, "exclusive")
      tryCompare(focus, "mode", "on-demand")
      tryVerify(function() { return inputSpy.count >= 3 })
    }
    function test_prime_waits_for_the_actual_backing_window() {
      focus.backingWindowVisible = false
      search.open("")
      wait(100)
      compare(focus.mode, "exclusive")
      verify(!focus.inputReady)
      compare(inputSpy.count, 0)
      focus.backingWindowVisible = true
      tryCompare(focus, "mode", "on-demand")
      tryCompare(inputSpy, "count", 1)
    }
    function test_explicit_open_waits_for_its_surface_focus() {
      search.surfaceActive = false
      search.open("")
      wait(30)
      compare(inputSpy.count, 0)
      verify(search.focusPending)
      search.surfaceActive = true
      tryCompare(inputSpy, "count", 1)
      verify(field.activeFocus)
      compare(inputSpy.signalArguments[0][0], true)
    }
    function test_close_cancels_deferred_focus() {
      search.surfaceActive = false
      search.open("")
      tryCompare(focus, "mode", "on-demand")
      search.surfaceActive = true // queues the real deferred focus callback
      search.close()             // closes before that callback can execute
      wait(30)
      compare(inputSpy.count, 0)
      verify(!search.opened)
      verify(!field.activeFocus)
    }
    function test_manual_hide_is_not_reopened_by_a_late_focus_callback() {
      search.open("")
      tryCompare(inputSpy, "count", 1)
      // The user can hide the OSK while the text field retains focus.
      // Further queued callbacks must not issue another show request.
      Qt.inputMethod.hide()
      search.queueFocus(); search.queueFocus()
      wait(30)
      compare(inputSpy.count, 1)
      verify(!search.focusPending)
    }
    function test_close_reopen_does_not_adopt_the_previous_focus_request() {
      search.open("Notes"); search.close(); search.open("Files")
      tryCompare(inputSpy, "count", 1)
      compare(search.query, "Files")
      compare(library.lastQuery, "Files")
      compare(search.entries.length, 1)
    }
    function test_keyboard_query_uses_the_shared_app_library() {
      search.open("")
      tryCompare(inputSpy, "count", 1)
      keyClick(Qt.Key_N)
      keyClick(Qt.Key_O); keyClick(Qt.Key_T); keyClick(Qt.Key_E); keyClick(Qt.Key_S)
      tryCompare(search, "query", "notes")
      compare(library.lastQuery, "notes")
      compare(search.entries[0].id, "example.notes")
    }
    function test_no_match_stays_in_search_without_an_agent_action() {
      search.open("No matching application")
      tryCompare(inputSpy, "count", 1)
      compare(search.entries.length, 0)
      var empty = findChild(search, "searchEmpty")
      verify(empty.visible)
      compare(empty.text, "No apps found")
      keyClick(Qt.Key_Return)
      compare(appSpy.count, 0)
      verify(search.opened)
    }
    function test_enter_releases_input_before_the_launch_signal() {
      search.open("Notes")
      tryCompare(inputSpy, "count", 1)
      keyClick(Qt.Key_Return)
      compare(appSpy.count, 1)
      compare(appSpy.signalArguments[0][0].id, "example.notes")
      verify(!search.opened)
      verify(!field.activeFocus)
      compare(inputSpy.signalArguments[inputSpy.count - 1][0], false)
    }
    function test_escape_closes_the_native_panel() {
      search.open("")
      tryCompare(inputSpy, "count", 1)
      keyClick(Qt.Key_Escape)
      compare(closeSpy.count, 1)
      verify(!search.opened)
    }
    function test_foreground_change_releases_without_hiding_foreign_input() {
      search.open("")
      tryCompare(inputSpy, "count", 1)
      search.surfaceActive = false
      compare(closeSpy.count, 1)
      compare(inputSpy.count, 1, "no hide request after another window took focus")
      verify(!search.opened)
      verify(!field.activeFocus)
    }
    function test_short_keyboard_viewport_keeps_the_input_in_bounds() {
      search.open("")
      tryCompare(inputSpy, "count", 1)
      view.width = 740; view.height = 88
      waitForPolish(search)
      tryVerify(function() {
        var at = field.mapToItem(search, 0, 0)
        return field.height >= 44 && at.y >= 0 && at.y + field.height <= search.height
      }, 1000)
      verify(!findChild(search, "searchResults").visible)
    }
    function test_layout_tracks_the_actual_available_viewport() {
      search.open("")
      tryCompare(inputSpy, "count", 1)
      view.width = 740; view.height = 320
      waitForPolish(search)
      verify(field.height >= 44)
      verify(field.y + field.height <= search.height)
      var list = findChild(search, "searchResults")
      verify(list.height > 0)
      verify(list.y + list.height <= field.y)
      var close = findChild(search, "searchClose")
      verify(close.width >= 44 && close.height >= 44)
    }
  }
}
