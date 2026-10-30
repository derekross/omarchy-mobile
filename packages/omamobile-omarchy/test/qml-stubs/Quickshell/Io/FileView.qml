// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell

// Stand-in for Quickshell's FileView: the test's Quickshell.files when it
// names the path (an empty text is no file), else the disk through
// XMLHttpRequest (QML_XHR_ALLOW_FILE_READ=1). Quickshell.diskChanged()
// stands in for a change on disk.
QtObject {
  id: view
  property string path: ""
  property bool watchChanges: false
  property bool printErrors: true
  property bool blockLoading: false
  property bool preload: true
  property string content: ""
  signal loaded()
  signal loadFailed(int error)
  signal fileChanged()

  function text() { return content }
  function setText(value) { content = String(value) }
  function reload() {
    if (!path) return
    if (Quickshell.files[path] !== undefined) {
      content = String(Quickshell.files[path])
      if (content.length > 0) loaded()
      else loadFailed(1)
      return
    }
    var x = new XMLHttpRequest()
    x.open("GET", "file://" + path, false)
    try { x.send() } catch (e) { content = ""; loadFailed(1); return }
    if (x.responseText.length > 0) {
      content = x.responseText
      loaded()
    } else {
      content = ""
      loadFailed(1)
    }
  }

  // blockLoading reads at once, as Quickshell's does; otherwise a moment later.
  property bool ready: false
  onPathChanged: if (ready) { if (blockLoading) reload(); else Qt.callLater(reload) }
  Component.onCompleted: { ready = true; if (blockLoading) reload(); else Qt.callLater(reload) }

  property Connections watcher: Connections {
    target: Quickshell
    function onDiskChanged() { if (view.watchChanges && view.path) view.fileChanged() }
  }
}
