// SPDX-License-Identifier: MIT
import QtQuick
import "HomeModel.js" as HomeModel

// Swipe up anywhere on the home screen for the app drawer, as on Android:
// the drawer (omamobile.launcher, reached through its DrawerLink.js) rises
// with the finger, and letting go opens it on an upward flick or past a
// quarter of the way, or lets it fall back (the drawer decides, in
// gestureEnd). Home.qml lays this over the pages, above LongPressEdit.
//
// The direction is Qt's own decision at its drag threshold (about 10 px):
// a DragHandler with its x axis off activates only on a mostly vertical
// drag, so a mostly sideways one stays the pager's and turns the page, and
// a tap or a hold never moves that far, so tiles, widgets and the long
// press keep theirs; once it activates it takes the touch, and whatever
// was pressed under it lets go without a click. It takes touch only: a
// DragHandler stops a mouse press from reaching the tiles under it (as
// LongPressEdit found, issue #147).
//
// A touch that lands on something that drags vertically itself (an OWL
// column that scrolls, a widget's own drag, a slider) is that widget's:
// the press is checked first, from the item above, and this swipe sits
// that touch out.
Item {
  id: swipe

  // The home screen (sawTouch), the pager the widgets are in, and the
  // drawer (DrawerLinkClient's), or null when it is out of reach.
  property var home: null
  property Item pages: null
  property var drawer: null
  // HomeModel.drawerSwipeAllowed: nothing over the home screen.
  property bool active: true

  // The finger is moving the drawer now, and how far up it has gone (px).
  readonly property bool swiping: drag.active && drag.up
  property real travel: 0
  // This touch landed on a widget's own vertical gesture.
  property bool blocked: false
  // The time (ms) the finger's speed is measured by; the tests set their own.
  property var clock: function() { return Date.now() }

  // Without the drawer in reach: open it through the host.
  signal fallbackOpen()

  // The item under a point (scene coordinates) that claims vertical drags
  // for itself, if any, below `pages`.
  function innerGestureAt(scenePos) {
    if (!pages) return false
    var p = pages.mapFromItem(null, scenePos.x, scenePos.y)
    var item = pages
    while (true) {
      var child = item.childAt(p.x, p.y)
      if (!child) break
      p = item.mapToItem(child, p.x, p.y)
      item = child
    }
    for (; item && item !== pages; item = item.parent)
      if (claimsVertical(item)) return true
    return false
  }

  function claimsVertical(item) {
    if (item.enabled === false) return false
    // A Flickable with somewhere to scroll up or down.
    if (item.flickableDirection !== undefined && item.interactive === true
        && item.flickableDirection !== Flickable.HorizontalFlick && item.contentHeight > item.height + 1) return true
    // An OWL node with an onDrag handler.
    if (item.handlers && item.handlers.onDrag) return true
    // A MouseArea that keeps its drags (an OWL slider).
    if (item.preventStealing === true) return true
    return false
  }

  // Decides at the press, before the DragHandler below sees it.
  Item {
    anchors.fill: parent
    z: 1
    PointHandler {
      acceptedDevices: PointerDevice.TouchScreen
      enabled: swipe.active
      onActiveChanged: {
        if (!active) return
        swipe.blocked = swipe.innerGestureAt(point.scenePressPosition)
        // Wake the drawer's window now, while the finger hasn't moved, so
        // its first frame of the swipe isn't a wake-up from idle.
        if (!swipe.blocked && swipe.drawer && typeof swipe.drawer.gesturePrepare === "function") {
          try { swipe.drawer.gesturePrepare() } catch (e) { }
        }
      }
    }
  }

  Item {
    anchors.fill: parent

    DragHandler {
      id: drag
      target: null
      xAxis.enabled: false
      acceptedDevices: PointerDevice.TouchScreen
      enabled: swipe.active && !swipe.blocked

      // Going up (decided at activation), the drawer took the swipe, and
      // the finger's recent positions (scene y), for its speed.
      property bool up: false
      property bool linked: false
      property var samples: []

      onActiveChanged: {
        if (active) {
          up = centroid.scenePosition.y < centroid.scenePressPosition.y
          samples = HomeModel.addSample([], swipe.clock(), centroid.scenePosition.y)
          swipe.travel = 0
          linked = false
          if (!up) return
          if (swipe.home && typeof swipe.home.sawTouch === "function") swipe.home.sawTouch()
          try { linked = !!swipe.drawer && swipe.drawer.gestureBegin() === true } catch (e) { linked = false }
          return
        }
        if (!up) return
        up = false
        var speed = HomeModel.speedOf(samples, swipe.clock())
        var travel = swipe.travel
        swipe.travel = 0
        if (linked) {
          linked = false
          try { swipe.drawer.gestureEnd(speed) } catch (e) { }
        } else if (HomeModel.drawerFallbackOpens(travel, speed)) {
          swipe.fallbackOpen()
        }
      }

      onCentroidChanged: {
        if (!active || !up) return
        swipe.travel = Math.max(0, centroid.scenePressPosition.y - centroid.scenePosition.y)
        samples = HomeModel.addSample(samples, swipe.clock(), centroid.scenePosition.y)
        if (linked) {
          try { swipe.drawer.gestureMove(swipe.travel) } catch (e) { linked = false }
        }
      }
    }
  }
}
