// SPDX-License-Identifier: MIT
import QtQuick
import "paint.js" as Paint

// Canvas: asks the widget for this frame's drawing calls and paints them,
// in dp. One that read `time` repaints on the view's frame clock (30 fps at
// most, and only while the view is shown); any other only when its node,
// size or the theme changes. Its paint time counts toward the frame's cost
// (OwlView.addWork), so a heavy one drops to half rate.
OwlNodeBase {
  id: canvasNode

  property bool readsTime: false
  readonly property var draw: canvasNode.node ? canvasNode.node.draw : null
  readonly property int frame: canvasNode.readsTime && canvasNode.view ? canvasNode.view.frame : 0

  onReadsTimeChanged: if (canvasNode.view) canvasNode.view.noteAnimating(canvasNode, canvasNode.readsTime)
  Component.onDestruction: if (canvasNode.view) canvasNode.view.noteAnimating(canvasNode, false)

  Canvas {
    id: art
    x: canvasNode.innerX
    y: canvasNode.innerY
    width: canvasNode.innerW
    height: canvasNode.innerH
    renderStrategy: Canvas.Cooperative
    readonly property var deps: [canvasNode.draw, width, height, canvasNode.frame, canvasNode.view ? canvasNode.view.inkVersion : 0]
    onDepsChanged: requestPaint()
    onImageLoaded: requestPaint()

    function image(src) {
      const url = canvasNode.view ? canvasNode.view.imageUrl(src) : ""
      if (!url) return null
      if (art.isImageLoaded(url)) return url
      if (!art.isImageLoading(url) && !art.isImageError(url)) art.loadImage(url)
      return null
    }

    onPaint: {
      const began = Date.now()
      const ctx = getContext("2d")
      ctx.reset()
      if (!canvasNode.draw || width <= 0 || height <= 0) return
      const dp = canvasNode.dp
      const ops = canvasNode.draw(width / dp, height / dp)
      // Told after this paint: a frame requested during a paint is lost.
      const reads = !!ops.readsTime
      if (reads !== canvasNode.readsTime) Qt.callLater(function() { canvasNode.readsTime = reads })
      ctx.scale(dp, dp)
      const ratio = canvasNode.view ? canvasNode.view.devicePixelRatio : 1
      Paint.paintList(ctx, ops, { foreground: canvasNode.ink("foreground") },
                      canvasNode.view ? canvasNode.view.family("sans") : "sans-serif", art.image, dp * ratio)
      if (canvasNode.view) canvasNode.view.addWork(Date.now() - began)
    }
  }
}
