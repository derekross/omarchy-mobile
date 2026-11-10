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
  AppsSearch { chatTransportEnabled: false; inputReady: focus.inputReady; id: search; anchors.fill: parent; appLibrary: library; surfaceActive: true; transitionDuration: 0 }
  SignalSpy { id: inputSpy; target: search; signalName: "inputRequested" }
  SignalSpy { id: closeSpy; target: search; signalName: "dismissed" }
  SignalSpy { id: appSpy; target: search; signalName: "activated" }
  SignalSpy { id: handoffSpy; target: search; signalName: "handoffAgent" }
  SignalSpy { id: chooseSpy; target: search; signalName: "chooseAgent" }
  Component { id: largeMetricConversation; AgentConversation { controller: search.chatController; foreground: search.foreground; muted: search.muted; cardColor: search.cardColor } }
  TestCase {
    name: "AppsSearch"
    when: windowShown
    property Item field: null
    function initTestCase() { field = findChild(search, "appsSearchInput"); verify(field) }
    function init() {
      search.close()
      search.sessionLocked = false
      search.page = "search"
      search.agentId = ""
      search.chatController.reset()
      search.chatController.receive({type:"reset"})
      findChild(search,"agentDraft").text = ""
      search.surfaceActive = true
      focus.backingWindowVisible = true
      view.width = 420; view.height = 900
      inputSpy.clear(); closeSpy.clear(); appSpy.clear(); handoffSpy.clear(); chooseSpy.clear()
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
    function test_ask_card_opens_editable_draft_without_submission() {
      search.agentId = "fixture"
      search.agentName = "Fixture Agent"
      search.open("Plan tomorrow")
      search.openAgent()
      compare(search.page, "agent")
      var draft = findChild(search, "agentDraft")
      compare(draft.text, "Plan tomorrow")
      compare(search.chatController.busy, false)
      compare(search.chatController.messages.length, 0)
      tryVerify(function() { return draft.activeFocus })
      search.back()
      compare(search.page, "search")
      verify(search.opened)
      search.openAgent()
      compare(draft.text, "Plan tomorrow")
    }
    function test_native_chat_requires_explicit_send_and_discards_late_cancelled_events() {
      search.agentId = "fixture"
      search.open("Draft")
      search.openAgent()
      var chat = search.chatController
      chat.receive({type:"reset"})
      chat.receive({type:"capabilities",provider:"fixture",nativeChat:true,installed:true})
      verify(!chat.busy)
      search.sendAgent("Explicit request")
      verify(chat.busy)
      var id = chat.activeId
      chat.receive({type:"started",id:id})
      chat.receive({type:"delta",id:id,text:"Part"})
      chat.receive({type:"reply",id:id,text:"Part complete"})
      compare(chat.messages[1].text,"Part complete")
      search.back()
      verify(chat.busy)
      verify(!chat.send("blocked while stopping"))
      chat.receive({type:"delta",id:id,text:" stale"})
      compare(chat.messages[1].text,"Part complete")
      chat.receive({type:"cancelled",id:id})
      verify(!chat.busy)
      verify(search.opened)
      search.openAgent()
      compare(chat.messages.length,2)
    }
    function test_lock_cancels_chat_work_and_never_refocuses_composer_on_unlock() {
      search.agentId = "fixture"
      search.open("Draft")
      search.openAgent()
      var chat=search.chatController
      chat.receive({type:"reset"})
      chat.receive({type:"capabilities",provider:"fixture",nativeChat:true,installed:true})
      search.sendAgent("Explicit request")
      var id=chat.activeId
      chat.receive({type:"started",id:id})
      search.sessionLocked=true
      verify(!search.opened)
      verify(chat.busy)
      chat.receive({type:"cancelled",id:id})
      verify(!chat.busy)
      chat.receive({type:"delta",id:id,text:"stale"})
      compare(chat.messages[1].text,"")
      search.sessionLocked=false
      wait(100)
      verify(!search.opened)
      verify(!findChild(search,"agentDraft").activeFocus)
    }
    function test_unsupported_agent_never_starts_native_work() {
      search.agentId="terminal-fixture"
      search.open("Draft")
      search.openAgent()
      var chat=search.chatController
      chat.receive({type:"reset"})
      chat.receive({type:"capabilities",provider:"terminal-fixture",nativeChat:false,installed:true,reason:"Use terminal"})
      search.sendAgent("Not submitted")
      verify(!chat.busy)
      compare(chat.messages.length,0)
    }
    function test_reset_requires_ack_before_matching_capabilities_can_enable_send() {
      search.agentId="fixture"
      search.open("Draft")
      search.openAgent()
      var chat=search.chatController
      chat.receive({type:"reset"})
      chat.receive({type:"capabilities",provider:"fixture",nativeChat:true,installed:true})
      chat.reset()
      verify(chat.resetPending)
      chat.receive({type:"capabilities",provider:"fixture",nativeChat:true,installed:true})
      verify(!chat.send("blocked until acknowledgement"))
      chat.receive({type:"reset"})
      verify(!chat.resetPending)
      verify(!chat.send("blocked until fresh capabilities"))
      chat.receive({type:"capabilities",provider:"fixture",nativeChat:true,installed:true})
      verify(chat.send("accepted after reset"))
      verify(/^[A-Za-z0-9_-]{1,80}$/.test(chat.activeId))
    }
    function test_unaccepted_or_oversize_request_keeps_editable_draft_and_hides_raw_error() {
      search.agentId="fixture"
      search.open("")
      search.openAgent()
      var chat=search.chatController,draft=findChild(search,"agentDraft")
      chat.receive({type:"reset"})
      chat.receive({type:"capabilities",provider:"fixture",nativeChat:true,installed:true})
      draft.text="Keep this editable"
      search.sendAgent(draft.text)
      compare(draft.text,"Keep this editable")
      var id=chat.activeId
      chat.receive({type:"error",id:id,code:"busy",text:"PRIVATE_DIAGNOSTIC_MUST_NOT_RENDER"})
      compare(draft.text,"Keep this editable")
      compare(chat.messages.length,0)
      verify(chat.error.indexOf("PRIVATE_DIAGNOSTIC")<0)
      draft.text=new Array(8194).join("x")
      search.sendAgent(draft.text)
      verify(!chat.busy)
      compare(draft.text.length,8193)
      verify(chat.error.indexOf("too long")>=0)
    }
    function test_account_reset_before_started_does_not_drop_explicit_request() {
      search.agentId="fixture"
      search.open("Draft")
      search.openAgent()
      var chat=search.chatController
      chat.receive({type:"reset"})
      chat.receive({type:"capabilities",provider:"fixture",nativeChat:true,installed:true})
      search.sendAgent("Explicit request")
      var id=chat.activeId
      chat.receive({type:"reset"}) // backend account-home transition, not our reset
      compare(chat.activeId,id)
      chat.receive({type:"started",id:id})
      compare(chat.messages[0].text,"Explicit request")
      chat.receive({type:"reply",id:id,text:"Answer"})
      chat.receive({type:"done",id:id})
      verify(!chat.busy)
      compare(chat.messages[1].text,"Answer")
    }
    function test_conversation_contains_large_platform_control_width() {
      var panel = createTemporaryObject(largeMetricConversation, view, {width:320, height:240})
      verify(panel !== null)
      var draft = findChild(panel, "agentDraft")
      var action = findChild(panel, "agentSend")
      action.implicitWidth = 400
      panel.draft = "A draft with a platform-preferred width larger than the viewport"
      waitForPolish(panel)
      wait(50)
      var pos = draft.mapToItem(panel, 0, 0)
      verify(pos.x >= 0 && pos.x + draft.width <= panel.width,
             "Platform button metrics must not push the composer outside the conversation")
      var actionPos = action.mapToItem(panel, 0, 0)
      verify(actionPos.x >= 0 && actionPos.x + action.width <= panel.width,
             "Long platform button labels stay inside their row")
    }
    function test_conversation_compact_viewports_keep_editable_draft_and_terminal_action_inside() {
      search.agentId="terminal-fixture"
      search.open("")
      search.openAgent()
      var chat=search.chatController
      chat.receive({type:"reset"})
      chat.receive({type:"capabilities",provider:"terminal-fixture",nativeChat:false,installed:true})
      var draft=findChild(search,"agentDraft")
      draft.text=new Array(301).join("A long editable draft ")
      var sizes=[[320,240],[740,320]]
      for(var i=0;i<sizes.length;i++) {
        view.width=sizes[i][0];view.height=sizes[i][1]
        wait(50)
        var names=["agentDraft","agentSend","agentBack","agentClose"]
        for(var j=0;j<names.length;j++) {
          var item=findChild(search,names[j]);verify(item!==null)
          var pos=item.mapToItem(search,0,0)
          verify(pos.x>=0&&pos.y>=0&&pos.x+item.width<=search.width+1&&pos.y+item.height<=search.height+1,names[j]+" stays inside "+sizes[i]+" at "+pos.x+","+pos.y+" "+item.width+"x"+item.height)
        }
      }
    }
    function test_actual_send_button_waits_for_acceptance_before_clearing_draft() {
      search.agentId="fixture"
      search.open("")
      search.openAgent()
      var chat=search.chatController,draft=findChild(search,"agentDraft")
      chat.receive({type:"reset"})
      chat.receive({type:"capabilities",provider:"fixture",nativeChat:true,installed:true})
      draft.text="An explicit button request"
      var send=findChild(search,"agentSend")
      wait(50);mouseClick(send,send.width/2,send.height/2)
      verify(chat.busy);compare(draft.text,"An explicit button request");compare(chat.messages.length,0)
      chat.receive({type:"started",id:chat.activeId})
      compare(draft.text,"");compare(chat.messages[0].text,"An explicit button request")
    }
    function test_terminal_handoff_click_is_explicit_and_closes_own_input() {
      search.agentId="terminal-fixture"
      search.open("Editable terminal draft")
      search.openAgent()
      var chat=search.chatController
      chat.receive({type:"reset"})
      chat.receive({type:"capabilities",provider:"terminal-fixture",nativeChat:false,installed:true})
      var send=findChild(search,"agentSend")
      wait(50);mouseClick(send,send.width/2,send.height/2)
      compare(handoffSpy.count,1)
      compare(handoffSpy.signalArguments[0][0],"Editable terminal draft")
      verify(!search.opened);verify(!chat.busy)
    }
    function test_without_configured_agent_card_requests_choice_without_submission() {
      search.open("Draft")
      search.openAgent()
      compare(chooseSpy.count,1)
      compare(search.page,"search")
      compare(search.chatController.messages.length,0)
      verify(!search.chatController.busy)
    }
    function test_transport_exit_releases_stop_wait_and_keeps_draft_for_terminal() {
      search.agentId="fixture"
      search.open("Retained draft")
      search.openAgent()
      var chat=search.chatController
      chat.receive({type:"reset"})
      chat.receive({type:"capabilities",provider:"fixture",nativeChat:true,installed:true})
      search.sendAgent("Retained draft")
      var id=chat.activeId
      chat.transportEnded() // actual onExited handler, with inert transport
      verify(!chat.busy);compare(chat.stoppingId,"");verify(!chat.available)
      compare(findChild(search,"agentDraft").text,"Retained draft")
      chat.receive({type:"reply",id:id,text:"stale"});compare(chat.messages.length,0)
      chat.reset() // explicit New chat may restart only the local serve process
      verify(chat.processWanted);verify(chat.resetPending);verify(!chat.send("not before restart ACK"))
      chat.receive({type:"reset"})
      chat.receive({type:"capabilities",provider:"fixture",nativeChat:true,installed:true})
      verify(chat.send("fresh explicit request"))
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
    function test_clear_returns_to_suggestions_without_a_new_focus_request() {
      search.open("Notes")
      tryCompare(inputSpy, "count", 1)
      var clear = findChild(search, "searchClear")
      verify(clear.visible)
      mouseClick(clear, clear.width / 2, clear.height / 2)
      compare(search.query, "")
      compare(search.entries.length, 3)
      verify(field.activeFocus)
      wait(100)
      compare(inputSpy.count, 1)
      verify(!clear.visible)
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
      var inputAt = field.mapToItem(search, 0, 0)
      var listAt = list.mapToItem(search, 0, 0)
      verify(listAt.y >= inputAt.y + field.height)
      verify(listAt.y + list.height <= search.height)
      var close = findChild(search, "searchClose")
      verify(close.width >= 44 && close.height >= 44)
    }
  }
}
