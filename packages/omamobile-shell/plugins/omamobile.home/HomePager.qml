// SPDX-License-Identifier: MIT
import QtQuick
import "HomeModel.js" as HomeModel

// The home screen's pages, swiped sideways. The drag is the ListView's own,
// so the pages follow the finger 1:1, under a mouse as under a finger; the
// settle is this file's. With StrictlyEnforceRange the ListView settled
// through its highlight animation, which starts from rest whatever the
// finger was doing (the page stopped, then sped up), and a short flick
// needed a long way to turn the page. Here a release settles on
// HomeModel.pageAfterSwipe's page (a flick of 300 px/s turns it, slower the
// nearer page wins) with one Easing.OutCubic slide of 120-250 ms that
// starts at the finger's speed (HomeModel.settleMs): no stop, no
// overshoot, nothing laid out again, only contentX moves.
//
// `page` is the page on screen, or the one a slide is going to; goTo(i,
// animate) is the way to change it.
ListView {
  id: pager

  orientation: ListView.Horizontal
  boundsBehavior: Flickable.StopAtBounds
  snapMode: ListView.NoSnap
  highlightRangeMode: ListView.NoHighlightRange
  // The neighbours are built and kept, so a swipe never waits for one.
  cacheBuffer: width * 2

  property int page: 0
  // A finger moves the pages, or they slide to a page.
  readonly property bool swiping: moving || settle.running
  readonly property bool settling: settle.running

  // The drag's recent scroll positions, for its speed at release.
  property var samples: []

  function pageX(i) { return originX + i * width }

  function clampPage(i) { return Math.max(0, Math.min(count - 1, Math.round(Number(i) || 0))) }

  function goTo(index, animate) {
    var i = clampPage(index)
    if (animate === false || width <= 0) {
      settle.stop()
      page = i
      contentX = pageX(i)
      currentIndex = i
      return
    }
    slideTo(i, 0)
  }

  function slideTo(index, speed) {
    settle.stop()
    page = clampPage(index)
    var to = pageX(page)
    var ms = HomeModel.settleMs(to - contentX, width, speed)
    if (ms <= 0) {
      contentX = to
      currentIndex = page
      return
    }
    settle.from = contentX
    settle.to = to
    settle.duration = ms
    settle.start()
  }

  NumberAnimation {
    id: settle
    target: pager
    property: "contentX"
    easing.type: Easing.OutCubic
    // The page settled on is the current item too, so a model change (a
    // page added or removed) keeps the view where it is.
    onFinished: pager.currentIndex = pager.page
  }

  onDraggingChanged: {
    if (!dragging) return
    settle.stop()
    samples = HomeModel.addSample([], Date.now(), contentX)
  }
  onContentXChanged: if (dragging) samples = HomeModel.addSample(samples, Date.now(), contentX)
  onDragEnded: {
    var speed = HomeModel.speedOf(samples, Date.now())
    slideTo(HomeModel.pageAfterSwipe(contentX - originX, width, count, speed), speed)
  }
  // The ListView's own flick would carry on past the page: the slide above
  // has already taken over.
  onFlickStarted: cancelFlick()

  // A new width (the phone turned) or a page more or fewer: back onto the
  // page, after the ListView has laid itself out again.
  function realign() {
    if (settle.running || dragging) return
    if (page > count - 1) page = Math.max(0, count - 1)
    contentX = pageX(page)
    currentIndex = page
  }
  onWidthChanged: Qt.callLater(realign)
  onCountChanged: Qt.callLater(realign)
}
