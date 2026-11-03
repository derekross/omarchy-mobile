// SPDX-License-Identifier: MIT
import QtQuick
import "VoiceLink.js" as VoiceLink

// The launcher's handle on voice input (VoiceLink.js says why it exists).
// omamobile.launcher loads this file from here, beside VoiceLink.js, so
// both plugins share the one script; `voice` is omamobile.voice's root
// while it is loaded, else null.
Item {
  id: client
  property var voice: null
  Component.onCompleted: VoiceLink.watch(client, function(v) { client.voice = v })
  Component.onDestruction: VoiceLink.unwatch(client)
}
