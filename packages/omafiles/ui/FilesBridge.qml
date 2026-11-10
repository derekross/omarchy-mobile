// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell.Io
Item {
  id: root
  property string backendPath: decodeURIComponent(String(Qt.resolvedUrl("files_backend.py")).replace("file://", ""))
  property int generation: 0
  property var pending: null
  property bool querying: false
  property bool operating: false
  readonly property bool loading: querying || pending !== null
  readonly property bool busy: operating
  property bool cancelling: false
  property var progress: ({})
  signal answer(string action, var result, var request)
  signal failure(string action, string code, string message, var details)
  signal completed(string action, var result)

  function query(action, payload) {
    generation++
    pending = {action: action, payload: payload || {}, generation: generation}
    if (querying) { if (queryProcess.running && queryProcess.processId>0) queryProcess.signal(15) }
    else startPending()
  }
  function startPending() {
    if (!pending || querying) return
    queryProcess.request = pending
    pending = null
    querying = true
    queryProcess.running = true
  }
  function act(action, payload) {
    if (busy) return false
    progress = ({})
    cancelling = false
    operating = true
    operation.request = {action: action, payload: payload || {}, cancelRequested: false}
    operation.running = true
    return true
  }
  function cancel() {
    if (!busy || cancelling) return
    cancelling = true
    operation.request.cancelRequested = true
    if (operation.running && operation.processId>0) operation.signal(15)
  }
  function reply(request, text, mutation) {
    if (!mutation && request.generation !== generation) return
    var response
    try { response = JSON.parse(text) } catch (_) {
      if (mutation && request.cancelRequested) failure(request.action, "cancelled", "Operation cancelled.", {})
      else failure(request.action, "invalid_response", "The file service could not be reached.", {})
      return
    }
    if (!response.ok) {
      var error = response.error || {}
      failure(request.action, error.code || "failed", error.message || "This action could not be completed.", error.details || {})
    } else if (mutation) completed(request.action, response.result)
    else answer(request.action, response.result, request)
  }
  Process {
    id: queryProcess
    property var request: ({})
    command: ["/usr/bin/python3", "-B", root.backendPath]
    stdinEnabled: true
    onStarted: write(JSON.stringify(request) + "\n")
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.reply(queryProcess.request, text, false) }
    onExited: { root.querying=false; Qt.callLater(root.startPending) }
  }
  Process {
    id: operation
    property var request: ({})
    command: ["/usr/bin/python3", "-B", root.backendPath]
    stdinEnabled: true
    onStarted: {
      write(JSON.stringify(request) + "\n")
      if (request.cancelRequested && processId>0) signal(15)
    }
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.reply(operation.request, text, true) }
    stderr: SplitParser {
      onRead: function(line) {
        try { var update=JSON.parse(line);if(update.type==="progress")root.progress=update } catch (_) {}
      }
    }
    onExited: { root.operating=false; root.cancelling=false }
  }
}
