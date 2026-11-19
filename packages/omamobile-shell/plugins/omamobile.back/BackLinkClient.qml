// SPDX-License-Identifier: MIT
import QtQuick
import "BackLink.js" as BackLink

// A surface's place in Back's list (BackLink.js says why it exists). Another
// plugin loads this file from here, beside BackLink.js, so every plugin
// shares the one script:
//
//   Loader {
//     source: Qt.resolvedUrl("../omamobile.back/BackLinkClient.qml")
//     onLoaded: {
//       item.name = "my sheet"
//       item.handler = function() { root.close() }
//       item.active = Qt.binding(function() { return root.opened })
//     }
//   }
//
// While `active` is true the handler is on the list; the moment it is false,
// or this item goes, it is off. `handler` does one level of Back and returns
// false only when it found nothing to do. `tier` is "surface", "keyboard" for
// the on-screen keyboard, or "on-keyboard" for what sits on it.
Item {
  id: client

  property bool active: false
  property var handler: null
  property string tier: "surface"
  property string name: ""
  // Whether it is on the list now, for the tests.
  property bool registered: false

  function run() {
    if (typeof client.handler !== "function") return false
    return client.handler() !== false
  }

  function sync() {
    if (client.active && typeof client.handler === "function") {
      client.registered = BackLink.register(client, client.run, client.tier, client.name)
    } else {
      BackLink.unregister(client)
      client.registered = false
    }
  }

  onActiveChanged: sync()
  onHandlerChanged: sync()
  onTierChanged: sync()
  onNameChanged: sync()
  Component.onDestruction: BackLink.unregister(client)
}
