// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell.Io

// Both widget formats share the same command-output bound. Once a pipe
// reaches 64 KiB, detaching its collector makes QProcess discard further
// output without interrupting the command. Collect raw bytes until then:
// decoding arbitrary SplitParser chunks would corrupt split UTF-8.
Process {
  id: proc
  property var done: null
  property string out: ""
  property string err: ""

  stdout: StdioCollector {
    id: stdoutCollector
    waitForEnd: false
    onDataChanged: if (data.byteLength >= 65536) { proc.out = proc.prefix(text); proc.stdout = null }
  }
  stderr: StdioCollector {
    id: stderrCollector
    waitForEnd: false
    onDataChanged: if (data.byteLength >= 65536) { proc.err = proc.prefix(text); proc.stderr = null }
  }

  // Trim on a character boundary, counting UTF-8 bytes, not UTF-16 units.
  function prefix(text) {
    let end = 0, remaining = 65536
    while (end < text.length) {
      const point = text.codePointAt(end)
      const bytes = point < 0x80 ? 1 : point < 0x800 ? 2 : point < 0x10000 ? 3 : 4
      if (bytes > remaining) break
      remaining -= bytes
      end += point > 0xffff ? 2 : 1
    }
    return text.slice(0, end)
  }

  function stop() {
    proc.done = null
    // GNU timeout forwards TERM to the command's process group, with its
    // existing -k grace period. Keep the Process alive until it exits.
    proc.running = false
  }
  onExited: function(code) {
    const finish = proc.done
    proc.done = null
    if (proc.stdout) proc.out = proc.prefix(stdoutCollector.text)
    if (proc.stderr) proc.err = proc.prefix(stderrCollector.text)
    if (finish) finish(code, proc.out, proc.err)
    proc.destroy()
  }
}
