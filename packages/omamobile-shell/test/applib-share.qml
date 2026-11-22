// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import "omamobile.home" as Home
import "omamobile.launcher/DrawerLink.js" as DrawerLink
import "services/AppLibraryCount.js" as Count

// test/applib-share: the home screen uses the drawer's application library.
ShellRoot {
  id: harness
  function check(name, good, why) { console.log((good ? "ok - " : "not ok - ") + name + (good ? "" : ": " + why)) }

  // The stand-in drawer: what Launcher.qml publishes, with its library.
  Item {
    id: fakeDrawer
    property real progress: 0
    property int dockHeight: 72
    readonly property var appLibrary: QtObject {
      property bool drawers: true
      signal appsChanged()
      function entryName(e) { return "" }
      function iconSource(i) { return "" }
    }
  }

  FloatingWindow {
    implicitWidth: 480; implicitHeight: 1040
    Home.Home { id: home; width: 480; height: 900; shell: ({}) }
  }

  Process { id: writer; command: ["sh", "-c", "for i in 1 2 3 4 5 6; do printf '[Desktop Entry]\\nType=Application\\nName=App%s\\nExec=true\\n' $i > \"$APPS_DIR/app$i.desktop\"; done"] }

  property int step: 0
  property int revisionBefore: 0
  readonly property bool usesDrawer: home.appLibrary === fakeDrawer.appLibrary
  readonly property bool usesOwn: !!home.appLibrary && home.appLibrary.stub === true
  Timer {
    interval: 500; running: true; repeat: true
    onTriggered: {
      harness.step += 1
      var s = harness.step, st = Count.made + " made, " + Count.live + " live, " + String(home.appLibrary)
      if (s === 6) {          // 3 s, no drawer
        harness.check("no drawer: no own instance during the first 5 s", Count.made === 0 && !home.appLibrary, st)
      } else if (s === 13) {  // 6.5 s
        harness.check("no drawer: one own instance after 5 s", Count.live === 1 && harness.usesOwn, st)
        DrawerLink.publish(fakeDrawer)
      } else if (s === 15) {
        harness.check("the drawer's library once it is in reach, the own one gone", harness.usesDrawer && Count.live === 0, st)
        DrawerLink.withdraw(fakeDrawer)
      } else if (s === 17) {  // 1 s after the drawer went
        harness.check("a drawer gone for a moment builds no library", Count.live === 0 && Count.made === 1, st)
      } else if (s === 28) {  // 6.5 s after
        harness.check("one own instance once the drawer is gone for 5 s", Count.live === 1 && Count.made === 2 && harness.usesOwn, st)
        DrawerLink.publish(fakeDrawer)
      } else if (s === 30) {
        harness.check("the drawer's library again when it comes back, the own one gone", harness.usesDrawer && Count.live === 0, st)
        harness.revisionBefore = home.appsRevision
        writer.running = true
      } else if (s === 38) {  // 4 s later
        var bumps = home.appsRevision - harness.revisionBefore
        var apps = (DesktopEntries.applications.values || []).length
        harness.check("six new entries at once bump appsRevision once", bumps === 1 && apps === 7, bumps + " bumps, " + apps + " apps")
        console.log("applib-share done")
        Qt.quit()
      }
    }
  }
}
