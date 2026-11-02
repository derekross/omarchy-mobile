// SPDX-License-Identifier: MIT
import QtQuick
import "DrawerLink.js" as DrawerLink

// The home screen's handle on the app drawer (DrawerLink.js says why it
// exists). omamobile.home loads this file from here, beside DrawerLink.js,
// so both plugins share the one script; `drawer` is the launcher's root
// while it is loaded, else null.
Item {
  id: client
  property var drawer: null
  Component.onCompleted: DrawerLink.watch(client, function(d) { client.drawer = d })
  Component.onDestruction: DrawerLink.unwatch(client)
}
