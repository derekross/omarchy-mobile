// SPDX-License-Identifier: MIT
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "UserWidgets.js" as UserWidgets
import "HomeModel.js" as HomeModel
import "owl/phone.js" as Phone
import "owl" as Owl
import "Readable.js" as Readable

// One placed OWL widget (docs/WIDGET-INTEROP-PLAN.md §2.7, §3). It runs
// only when its file compiles here and its exact list of commands, URLs and
// files is approved; anything else is a card that says why, in this cell
// only. Its first seconds are covered by the same crash guard as QML
// widgets: if the shell dies while it starts, it stays off at the next start
// until its file changes.
Item {
  id: owlCell

  // Set by Home.qml's cell, like every widget.
  property var home: null
  property var entry: null
  property bool editing: false
  // Its page shows and nothing covers the home screen (Home.qml's
  // pageShown): only then do its sources, `every` and frames run.
  property bool shown: false

  // A user widget's id, or a built-in's type ("owl:simonschubert.today").
  readonly property string widgetId: !owlCell.entry ? "" : HomeModel.isOwlType(owlCell.entry.type) ? owlCell.entry.type : UserWidgets.idOf(owlCell.entry.type)
  readonly property var config: owlCell.entry && owlCell.entry.config ? owlCell.entry.config : ({})
  readonly property var card: owlCell.home && owlCell.widgetId ? owlCell.home.owlCard(owlCell.widgetId)
    : ({ state: "waiting", message: "", record: null, info: null, approval: null })
  readonly property bool running: owlCell.card.state === "ok"
  readonly property real dp: owlCell.home ? owlCell.home.owlDp : 1

  Owl.OwlWidget {
    id: owl
    text: owlCell.running && owlCell.card.record && owlCell.card.record.owl ? owlCell.card.record.owl.text : ""
    // Persisted state is per placement: the same widget placed twice keeps two states.
    stateKey: owlCell.entry ? owlCell.widgetId + "@" + owlCell.entry.id : ""
    // What the old port's settings become (HomeModel.owlConfigFor), until the widget saves its own.
    seedState: owlCell.config.owlState || ({})
    host: owlCell.home ? owlCell.home.owlHost : null
    themeColors: owlCell.home ? owlCell.home.owlPalette : ({})
    approval: owlCell.card.approval
    active: owlCell.running && owlCell.shown && !!owlCell.home && !!owlCell.entry
    // While its screen is open, the screen's size is the view's own.
    tileVars: Phone.tileVars(owlCell.width, owlCell.height, owlCell.dp,
                             owl.screenOpen ? view.width : owlCell.home ? owlCell.home.owlScreenWidth : owlCell.width,
                             owl.screenOpen ? view.height : owlCell.home ? owlCell.home.owlScreenHeight : owlCell.height, Style.cornerRadius)
  }

  // The tile's own onTap, under the nodes (a node that handles taps wins).
  TapHandler {
    enabled: owlCell.running && !owlCell.editing && !owl.screenOpen && !!owl.tree && !!owl.tree.onTap
    gesturePolicy: TapHandler.ReleaseWithinBounds
    onTapped: function(point) {
      if (owlCell.home) owlCell.home.owlScheduler.touched()
      owl.runHandler(owl.tree.onTap, [point.position.x / owlCell.dp, point.position.y / owlCell.dp])
    }
  }

  // The screen's title and the way back, as our built-ins show their
  // longer view in place ("‹" goes back). Back also comes from close().
  Item {
    id: screenBar
    visible: owl.screenOpen
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: owl.screenOpen ? Math.max(44, Style.font.subtitle * 2.2) : 0
    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.xl
      anchors.rightMargin: Style.spacing.xl
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "\u2039  " + (owl.screenTree && owl.screenTree.title ? owl.screenTree.title : "")
      color: owlCell.home ? owlCell.home.foreground : Commons.Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      font.bold: true
      elide: Text.ElideRight
    }
    MouseArea { anchors.fill: parent; enabled: !owlCell.editing; onClicked: owl.closeScreen() }
  }

  Owl.OwlView {
    id: view
    anchors.fill: parent
    anchors.margins: (owl.program ? owl.program.padding : 12) * owlCell.dp
    anchors.topMargin: owl.screenOpen ? screenBar.height : (owl.program ? owl.program.padding : 12) * owlCell.dp
    visible: owlCell.running && owl.error === ""
    tree: owl.screenOpen ? owl.screenTree : owl.tree
    terminals: owlCell.home && owlCell.home.owlHost ? owlCell.home.owlHost.terminalFor(owl) : null
    colors: owlCell.home ? owlCell.home.owlInk : ({})
    dp: owlCell.dp
    corners: Phone.cornersFor(Style.cornerRadius)
    monoFamily: Style.font.family
    iconFamily: Style.font.family
    homeDir: owlCell.home ? owlCell.home.homeDir : ""
    interactive: !owlCell.editing
    onHandlerRun: function(handler, args) {
      // A finger on the widget: its animation runs at the touch rate a moment.
      if (owlCell.home) owlCell.home.owlScheduler.touched()
      owl.runHandler(handler, args)
    }
    onKeyboardWanted: function(on) { if (owlCell.home && owlCell.home.owlKeyboard) owlCell.home.owlKeyboard(on) }
  }

  // ---------- location, for the weather built-ins

  // The ports used the phone's position (GeoClue, about 1 km); their OWL
  // originals take a place as `city`, and wttr.in reads "lat,lon" as one.
  // The coordinates go in while the city is empty or still the last ones put
  // in, so a city the user types wins. Needs its internet allowed.
  readonly property bool wantsLocation: owlCell.running && owlCell.shown && owlCell.config.useLocation === true
    && !!owlCell.card.approval && owlCell.card.approval.network === true
  GeoLocation { id: geo; active: owlCell.wantsLocation }
  onLocationTextChanged: owlCell.fillLocation()
  readonly property string locationText: geo.fix ? Number(geo.fix.lat).toFixed(2) + "," + Number(geo.fix.lon).toFixed(2) : ""
  Connections { target: owl; function onInstanceChanged() { owlCell.fillLocation() } }
  function fillLocation() {
    if (!owlCell.wantsLocation || !owlCell.locationText || !owl.instance) return
    const city = owl.stateValue("city")
    if (city === undefined) return
    if (city !== "" && city !== owlCell.config.locationText) return
    if (city === owlCell.locationText) return
    owl.setStateValue("city", owlCell.locationText)
    if (owlCell.home && owlCell.entry) owlCell.home.setConfig(owlCell.entry.id, { locationText: owlCell.locationText })
  }

  // Opens the widget's screen, as its own screen() does (tests, IPC).
  function openScreen() { owl.openScreen() }

  // ---------- the scheduler and the crash guard

  readonly property var client: ({
    key: owlCell.widgetId + "@" + (owlCell.entry ? owlCell.entry.id : ""),
    tick: function(now) { owl.tick(now) },
    frame: function(t) { owl.frame(t); view.frame++ },
    cost: function() { return view.takeWork() },
    get active() { return owl.active }
  })
  readonly property bool animates: owl.active && view.animating
  onAnimatesChanged: if (owlCell.home) owlCell.home.owlScheduler.setAnimating(owlCell.client, owlCell.animates)

  property bool guarding: false
  onRunningChanged: owlCell.startGuard()
  Component.onCompleted: {
    if (owlCell.home) owlCell.home.owlScheduler.add(owlCell.client)
    owlCell.startGuard()
  }
  Component.onDestruction: {
    if (owlCell.home) {
      owlCell.home.owlScheduler.remove(owlCell.client)
      if (owlCell.guarding) owlCell.home.guardEnd(owlCell.widgetId)
    }
  }
  function startGuard() {
    if (!owlCell.running || !owlCell.home || owlCell.guarding) return
    owlCell.guarding = true
    owlCell.home.guardBegin(owlCell.widgetId, owlCell.card.record ? owlCell.card.record.hash : "")
    settled.restart()
  }
  Timer {
    id: settled
    interval: 3000
    onTriggered: if (owlCell.home) { owlCell.home.guardEnd(owlCell.widgetId, true); owlCell.guarding = false }
  }

  // ---------- a card instead of the widget

  readonly property bool showsCard: !owlCell.running || owl.error !== ""
  readonly property string cardState: owl.error !== "" ? "error" : owlCell.card.state
  readonly property string cardMessage: owl.error !== "" ? owl.error : owlCell.card.message

  Column {
    visible: owlCell.showsCard
    anchors.fill: parent
    anchors.margins: Style.spacing.xl
    spacing: Style.spacing.xs

    Row {
      width: parent.width
      spacing: Style.spacing.md
      Text {
        id: glyph
        textFormat: Text.PlainText
        text: owlCell.cardState === "approve" ? "󰒃" : owlCell.cardState === "waiting" || owlCell.cardState === "off" ? "󰕰" : "󰀦"
        color: owlCell.cardState === "error" || owlCell.cardState === "missing" ? Commons.Color.urgent : Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.iconLarge
      }
      Text {
        width: parent.width - glyph.width - parent.spacing
        anchors.verticalCenter: glyph.verticalCenter
        textFormat: Text.PlainText
        text: owlCell.card.info && owlCell.card.info.name ? owlCell.card.info.name : owlCell.widgetId
        color: owlCell.home ? owlCell.home.foreground : Commons.Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }
    }
    Text {
      width: parent.width
      height: Math.max(0, parent.height - glyph.height - hint.height - parent.spacing * 2)
      visible: height >= Readable.px(Style.font.caption)
      textFormat: Text.PlainText
      text: owlCell.cardMessage
      color: owlCell.home ? owlCell.home.dimForeground : Commons.Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Readable.px(Style.font.caption)
      wrapMode: owlCell.cardState === "error" ? Text.WrapAnywhere : Text.Wrap
      elide: Text.ElideRight
    }
    Text {
      id: hint
      width: parent.width
      visible: owlCell.cardState === "approve" || owlCell.cardState === "error"
      textFormat: Text.PlainText
      text: owlCell.cardState === "approve" ? "Tap to review" : "Tap to fix with AI"
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Readable.px(Style.font.caption)
      elide: Text.ElideRight
    }
  }

  MouseArea {
    anchors.fill: parent
    visible: owlCell.showsCard
    enabled: !owlCell.editing
    onClicked: {
      if (!owlCell.home) return
      if (owlCell.cardState === "approve") owlCell.home.openOwlApproval(owlCell.widgetId)
      else if (owlCell.cardState === "error") owlCell.home.openCreate("edit", owlCell.widgetId)
    }
  }
}
