// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HomeModel.js" as HomeModel
import "UserWidgets.js" as UserWidgets
import "owl/catalog.js" as OwlCatalog
import "owl/phone.js" as OwlPhone
import "owl" as Owl
import "Readable.js" as Readable

// Edit mode's sheets, sliding up from the bottom of the home screen: add a
// widget, add an app, manage pages, and one widget's settings. `home` is
// Home.qml's root, which owns the layout and every edit.
Item {
  id: sheets

  property var home: null
  readonly property string which: home ? home.sheet : ""
  readonly property color fg: home ? home.foreground : "white"
  readonly property color dim: home ? home.dimForeground : "white"
  readonly property int touch: Math.max(44, Style.space(44))

  visible: which !== ""

  function close() { if (home) home.sheet = "" }

  // Scroll into view (TOUCH-PLAN 1.7). The home surface shrinks above the
  // on-screen keyboard, and so do the sheets, but nothing moved a sheet's
  // Flickable to the field being typed in. keepInView scrolls `flick` so the
  // focused item inside it shows with a margin: the whole field when it
  // fits, else the text cursor (a note longer than the sheet). The settings
  // and create sheets call it when the focus moves, the cursor moves or the
  // sheet changes height (the keyboard coming up).
  readonly property Item focusedItem: Window.activeFocusItem
  function keepInView(flick) {
    Qt.callLater(function() { sheets.scrollTo(flick, sheets.focusedItem) })
  }
  function scrollTo(flick, item) {
    if (!flick || !item || !flick.contentItem || flick.height <= 0) return
    var p = item
    while (p && p !== flick.contentItem) p = p.parent
    if (!p) return
    var margin = Style.spacing.xxl
    var r = Qt.rect(0, 0, item.width, item.height)
    if (item.height + margin * 2 > flick.height && item.cursorRectangle !== undefined) r = item.cursorRectangle
    var top = item.mapToItem(flick.contentItem, r.x, r.y).y - margin
    var bottom = top + r.height + margin * 2
    var y = flick.contentY
    if (bottom > y + flick.height) y = bottom - flick.height
    if (top < y) y = top
    flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height))
  }

  // The scrim: a tap outside the sheet closes it.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.35)
    MouseArea { anchors.fill: parent; onClicked: sheets.close() }
  }

  Rectangle {
    id: panel
    objectName: "sheetPanel"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Math.min(parent.height * 0.82, Math.max(parent.height * 0.4, body.implicitHeight + header.height + Style.spacing.xxl * 2))
    radius: Math.max(Style.cornerRadius, 14)
    color: Commons.Color.menu.background
    border.width: 1
    border.color: Util.alpha(sheets.fg, 0.15)

    // Taps on the sheet stay on the sheet.
    MouseArea { anchors.fill: parent }

    Item {
      id: header
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.xxl
      anchors.rightMargin: Style.spacing.sm
      height: sheets.touch + Style.spacing.md

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: sheets.which === "widgets" ? "Add a widget"
          : sheets.which === "apps" ? "Add an app"
          : sheets.which === "pages" ? "Pages"
          : sheets.which === "settings" ? sheets.settingsTitle
          : sheets.which === "create" ? sheets.createTitle
          : sheets.which === "owl-approve" ? sheets.approveTitle
          : sheets.which === "owl-store" ? sheets.storeTitle : ""
        color: sheets.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Button {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: sheets.touch
        height: sheets.touch
        iconText: "󰅖"
        iconSize: Style.font.iconLarge
        foreground: sheets.fg
        onClicked: sheets.close()
      }
    }

    Loader {
      id: body
      anchors.top: header.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.spacing.xxl
      anchors.topMargin: 0
      readonly property real implicitHeight: item ? item.implicitHeight : 0
      sourceComponent: sheets.which === "widgets" ? widgetsSheet
        : sheets.which === "apps" ? appsSheet
        : sheets.which === "pages" ? pagesSheet
        : sheets.which === "settings" ? settingsSheet
        : sheets.which === "create" ? createSheet
        : sheets.which === "owl-approve" ? approveSheet
        : sheets.which === "owl-store" ? storeSheet : null
    }
  }

  // ---------------------------------------------------------------- shared parts

  component Label: Text {
    textFormat: Text.PlainText
    color: sheets.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    wrapMode: Text.Wrap
  }

  component SheetButton: BorderSurface {
    id: sb
    property string label: ""
    property bool primary: false
    property bool danger: false
    // A danger button waiting for its second tap: filled in the urgent colour.
    property bool armed: false
    signal clicked()
    implicitWidth: Math.max(sheets.touch * 2, sbText.implicitWidth + Style.spacing.xxl * 2)
    implicitHeight: sheets.touch
    radius: Style.cornerRadius
    color: sbTap.pressed ? Style.pressedFillFor(sheets.fg, Commons.Color.accent)
      : primary ? Commons.Color.accent : armed ? Commons.Color.urgent
      : danger ? Util.alpha(Commons.Color.urgent, 0.18) : Style.normalFill
    borderSpec: Border.controlSpec("normal", sheets.fg, Commons.Color.accent)
    opacity: enabled ? 1 : 0.4
    Text {
      id: sbText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: sb.label
      color: sb.primary || sb.armed ? Commons.Color.background : sb.danger ? Commons.Color.urgent : sheets.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
    }
    MouseArea { id: sbTap; anchors.fill: parent; onClicked: sb.clicked() }
  }

  // A row with an icon, a title and a line under it.
  component Row2: Item {
    id: r2
    property string glyph: ""
    property url image: ""
    property string title: ""
    property string subtitle: ""
    signal clicked()
    width: parent ? parent.width : 0
    height: Math.max(sheets.touch + 8, 56)
    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: r2Tap.pressed ? Style.pressedFillFor(sheets.fg, Commons.Color.accent) : "transparent"
    }
    Item {
      id: r2Icon
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      width: 36; height: 36
      Text {
        anchors.centerIn: parent
        visible: r2.glyph !== ""
        textFormat: Text.PlainText
        text: r2.glyph
        color: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: 26
      }
      Image {
        anchors.fill: parent
        visible: r2.glyph === ""
        source: r2.image
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
      }
    }
    Column {
      anchors.left: r2Icon.right
      anchors.leftMargin: Style.spacing.xl
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: r2.title
        color: sheets.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: r2.subtitle !== ""
        textFormat: Text.PlainText
        text: r2.subtitle
        color: sheets.dim
        font.family: Style.font.family
        font.pixelSize: Readable.px(Style.font.caption)
        elide: Text.ElideRight
      }
    }
    MouseArea { id: r2Tap; anchors.fill: parent; onClicked: r2.clicked() }
  }

  // ---------------------------------------------------------------- add a widget

  component SectionLabel: Text {
    width: parent ? parent.width : 0
    topPadding: Style.spacing.lg
    textFormat: Text.PlainText
    color: sheets.dim
    font.family: Style.font.family
    font.pixelSize: Readable.px(Style.font.caption)
    font.bold: true
  }

  // A user widget or example: like Row2, with a warning look and actions
  // (Edit with AI, Remove) on the right.
  component WidgetRow: Item {
    id: wr
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property bool warn: false
    property bool actions: false
    property bool confirming: false
    signal clicked()
    signal edit()
    signal remove()
    width: parent ? parent.width : 0
    height: Math.max(sheets.touch + 8, 56)
    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: wrTap.pressed ? Style.pressedFillFor(sheets.fg, Commons.Color.accent) : "transparent"
    }
    MouseArea { id: wrTap; anchors.fill: parent; onClicked: wr.clicked() }
    Text {
      id: wrIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      width: 36
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: wr.glyph
      color: wr.warn ? Commons.Color.urgent : Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: 26
    }
    Column {
      anchors.left: wrIcon.right
      anchors.leftMargin: Style.spacing.xl
      anchors.right: wrActions.left
      anchors.verticalCenter: parent.verticalCenter
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: wr.title
        color: sheets.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: wr.subtitle !== ""
        textFormat: Text.PlainText
        text: wr.subtitle
        color: wr.warn ? Commons.Color.urgent : sheets.dim
        font.family: Style.font.family
        font.pixelSize: Readable.px(Style.font.caption)
        elide: Text.ElideRight
      }
    }
    Row {
      id: wrActions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: wr.actions
      width: visible ? implicitWidth : 0
      Button {
        width: sheets.touch; height: sheets.touch
        iconText: "󰚩"; iconSize: Style.font.iconLarge
        foreground: sheets.fg
        onClicked: wr.edit()
      }
      Button {
        width: sheets.touch; height: sheets.touch
        // Removing asks first: the second tap moves the folder out.
        iconText: wr.confirming ? "󰄬" : "󰆴"; iconSize: Style.font.iconLarge
        foreground: wr.confirming ? Commons.Color.urgent : sheets.fg
        onClicked: { if (!wr.confirming) { wr.confirming = true; return } wr.confirming = false; wr.remove() }
      }
    }
  }

  Component {
    id: widgetsSheet
    Flickable {
      implicitHeight: widgetsColumn.implicitHeight
      contentHeight: widgetsColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      readonly property var scan: sheets.home ? sheets.home.userScan : UserWidgets.emptyScan()

      Column {
        id: widgetsColumn
        width: parent.width

        // Yours and built-in, or the OWL store (with OWL widgets on).
        Row {
          visible: sheets.home.owlEnabled
          width: parent.width
          height: visible ? sheets.touch : 0
          spacing: Style.spacing.sm
          bottomPadding: Style.spacing.md
          Repeater {
            model: [{ tab: "", label: "Widgets" }, { tab: "store", label: "Store" }]
            delegate: SheetButton {
              required property var modelData
              width: (widgetsColumn.width - Style.spacing.sm) / 2
              label: modelData.label
              primary: sheets.widgetsTab === modelData.tab
              onClicked: sheets.widgetsTab = modelData.tab
            }
          }
        }

        Column {
          visible: sheets.widgetsTab === "store" && sheets.home.owlEnabled
          width: parent.width
          spacing: Style.spacing.xs
          Label {
            width: parent.width
            text: "Widgets from the OWL widget store, the ones that run on this phone. Each asks before it runs anything."
          }
          Flow {
            width: parent.width
            spacing: Style.spacing.sm
            Repeater {
              model: [""].concat(OwlCatalog.CATEGORIES)
              delegate: SheetButton {
                required property var modelData
                label: modelData || "all"
                primary: sheets.storeCategory === modelData
                onClicked: sheets.storeCategory = modelData
              }
            }
          }
          Repeater {
            model: sheets.home.owlStoreRows.filter(function(r) { return !sheets.storeCategory || r.category === sheets.storeCategory })
            delegate: WidgetRow {
              required property var modelData
              width: widgetsColumn.width
              glyph: modelData.status === "unsupported" ? "󰀦" : OwlCatalog.ICON
              title: modelData.name + "  \u00b7  " + modelData.author
              subtitle: (modelData.update ? "update to " + modelData.version + "  \u00b7  " : modelData.owned ? "added  \u00b7  " : "")
                + (modelData.sizeText ? modelData.sizeText + "  \u00b7  " : "") + modelData.summary
              warn: modelData.status === "unsupported"
              onClicked: sheets.home.openStoreWidget(modelData.id)
            }
          }
          SheetButton {
            width: parent.width
            label: "Check the store now"
            enabled: !sheets.home.helperBusy
            onClicked: sheets.home.fetchStore()
          }
          Label {
            visible: sheets.home.owlStoreMessage !== ""
            width: parent.width
            text: sheets.home.owlStoreMessage
          }
        }

        SheetButton {
          visible: sheets.widgetsTab === "" || !sheets.home.owlEnabled
          width: parent.width
          label: "󰚩  Create a widget with AI"
          primary: true
          onClicked: sheets.home.openCreate("create", "")
        }

        SectionLabel { visible: widgetsColumn.mine && widgetsColumn.yours.length > 0; text: "YOURS" }
        readonly property bool mine: sheets.widgetsTab === "" || !sheets.home.owlEnabled
        // OWL widgets only while the feature is on (features.json).
        readonly property var yours: scan.widgets.filter(function(r) { return r.kind !== "owl" || sheets.home.owlEnabled })
        Repeater {
          model: widgetsColumn.mine ? widgetsColumn.yours : []
          delegate: WidgetRow {
            required property var modelData
            readonly property bool isOwl: modelData.kind === "owl"
            readonly property var owlCard: isOwl ? sheets.home.owlCard(modelData.id) : null
            width: widgetsColumn.width
            glyph: isOwl ? (owlCard.state === "error" ? "󰀦" : OwlCatalog.ICON) : modelData.manifest ? modelData.manifest.icon : "󰀦"
            title: isOwl ? (owlCard.info && owlCard.info.name ? owlCard.info.name : modelData.id) : modelData.manifest ? modelData.manifest.name : modelData.id
            subtitle: isOwl ? sheets.owlLine(owlCard) : UserWidgets.statusLine(modelData)
            warn: isOwl ? owlCard.state === "error" : modelData.status !== "ok"
            actions: true
            // A broken widget can still be placed: its card shows what's wrong.
            // An OWL widget asks first, once, for what it runs.
            onClicked: {
              if (isOwl && owlCard.state === "approve") sheets.home.openOwlApproval(modelData.id)
              else sheets.home.addWidgetHere(UserWidgets.typeFor(modelData.id))
            }
            onEdit: sheets.home.openCreate("edit", modelData.id)
            onRemove: sheets.home.removeUserWidget(modelData.id)
          }
        }

        SectionLabel { visible: widgetsColumn.mine; text: "BUILT IN" }
        Repeater {
          model: widgetsColumn.mine ? HomeModel.widgetTypes() : []
          delegate: Row2 {
            required property var modelData
            width: widgetsColumn.width
            glyph: modelData.icon
            title: modelData.name
            subtitle: modelData.w + "×" + modelData.h + (modelData.network ? "  ·  uses the internet once you allow it" : "")
            onClicked: {
              if (HomeModel.isOwlType(modelData.type) && sheets.home.owlCard(modelData.type).state === "approve") sheets.home.openOwlApproval(modelData.type)
              else sheets.home.addWidgetHere(modelData.type)
            }
          }
        }

        SectionLabel { visible: widgetsColumn.mine && scan.examples.length > 0; text: "EXAMPLES" }
        Repeater {
          model: widgetsColumn.mine ? scan.examples : []
          delegate: WidgetRow {
            required property var modelData
            width: widgetsColumn.width
            readonly property bool copied: !!UserWidgets.findRecord(scan, modelData.id)
            glyph: modelData.manifest ? modelData.manifest.icon : "󰕰"
            title: modelData.manifest ? modelData.manifest.name : modelData.id
            subtitle: copied ? "Already in your widgets" : (modelData.manifest ? modelData.manifest.description : "")
            onClicked: sheets.home.copyExample(modelData.id)
          }
        }

      }
    }
  }

  property string widgetsTab: ""
  property string storeCategory: ""

  // ---------------------------------------------------------------- one store widget

  readonly property var storeRow: home && which === "owl-store"
    ? home.owlStoreRows.filter(function(r) { return r.id === home.owlStoreDetail })[0] || null : null
  readonly property string storeTitle: storeRow ? storeRow.name : "Store"

  Component {
    id: storeSheet
    Flickable {
      id: storeFlick
      implicitHeight: storeColumn.implicitHeight
      contentHeight: storeColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      readonly property var row: sheets.storeRow
      readonly property var info: row && sheets.home ? OwlCatalog.describe(row.widgetId, storeFile.text(), sheets.home.layout.grid, sheets.home.owlCellHeight, sheets.home.owlDp) : null

      FileView {
        id: storeFile
        path: storeFlick.row ? sheets.home.owlStoreDir + "/widgets/" + storeFlick.row.id + "/widget.owl" : ""
        blockLoading: true
        printErrors: false
      }

      Column {
        id: storeColumn
        width: parent.width
        spacing: Style.spacing.xl

        Label {
          width: parent.width
          text: storeFlick.row ? storeFlick.row.description + "\n\nBy " + storeFlick.row.author + ", version " + storeFlick.row.version
            + (storeFlick.row.category ? ", " + storeFlick.row.category : "") + ". From the OWL widget store, reviewed there." : ""
        }

        Label {
          visible: !!storeFlick.info && storeFlick.info.ok && storeFlick.row.status !== "unsupported"
          width: parent.width
          text: "Preview, in your theme, with no data yet: nothing runs until you add and allow it."
        }
        // A preview drawn here, in your theme, with no data: nothing runs.
        Rectangle {
          visible: !!storeFlick.info && storeFlick.info.ok && storeFlick.row.status !== "unsupported"
          width: storeFlick.info && storeFlick.info.ok ? Math.min(parent.width, storeFlick.info.spec.size[0] * parent.width / 4) : 0
          height: storeFlick.info && storeFlick.info.ok ? storeFlick.info.spec.size[1] * (sheets.home.owlCellHeight) - Style.spacing.md * 2 : 0
          anchors.horizontalCenter: parent.horizontalCenter
          radius: Math.max(Style.cornerRadius, 12)
          color: sheets.home.cardColor
          clip: true
          Owl.OwlWidget {
            id: preview
            text: storeFlick.info && storeFlick.info.ok ? storeFile.text() : ""
            host: ({ loadState: function() { return {} }, saveState: function() {}, report: function() {} })
            themeColors: sheets.home.owlPalette
            active: false
            tileVars: OwlPhone.tileVars(parent.width, parent.height, sheets.home.owlDp, sheets.home.owlScreenWidth, sheets.home.owlScreenHeight, Style.cornerRadius)
          }
          Owl.OwlView {
            anchors.fill: parent
            anchors.margins: (preview.program ? preview.program.padding : 12) * sheets.home.owlDp
            tree: preview.tree
            colors: sheets.home.owlInk
            dp: sheets.home.owlDp
            corners: OwlPhone.cornersFor(Style.cornerRadius)
            monoFamily: Style.font.family
            iconFamily: Style.font.family
            interactive: false
          }
        }

        Section {
          visible: !!storeFlick.row
          title: storeFlick.row && storeFlick.row.status === "unsupported" ? "Not on this phone yet" : "What it does"
          Label {
            width: parent.width
            text: storeFlick.row ? storeFlick.row.summary + (storeFlick.row.note && storeFlick.row.status === "partial" ? ". Partly: " + storeFlick.row.note : "") : ""
          }
        }

        Row {
          spacing: Style.spacing.lg
          SheetButton {
            visible: !!storeFlick.row && storeFlick.row.status !== "unsupported" && !storeFlick.row.owned
            label: "Add"
            primary: true
            enabled: !sheets.home.helperBusy
            onClicked: sheets.home.addFromStore(storeFlick.row.id)
          }
          SheetButton {
            visible: !!storeFlick.row && storeFlick.row.update
            label: "Update to " + (storeFlick.row ? storeFlick.row.version : "")
            primary: true
            onClicked: sheets.home.updateFromStore(storeFlick.row.widgetId)
          }
          SheetButton {
            label: "Back"
            onClicked: sheets.home.sheet = "widgets"
          }
        }
      }
    }
  }

  // The line under an OWL widget in the Widgets sheet.
  function owlLine(card) {
    if (!card) return ""
    const info = card.info
    const size = info && info.ok ? info.spec.size[0] + "\u00d7" + info.spec.size[1] + "  \u00b7  " : ""
    if (card.state === "error") return "OWL  \u00b7  \u26a0 " + String(card.message).split("\n")[0]
    if (card.state === "approve") return "OWL  \u00b7  " + size + "needs your OK: " + OwlCatalog.summary(info.caps)
    return "OWL  \u00b7  " + size + OwlCatalog.summary(info ? info.caps : null)
      + (info && info.caps.network && !(card.approval && card.approval.network) ? " (off)" : "")
  }

  // ---------------------------------------------------------------- allow an OWL widget

  readonly property var approveCard: home && which === "owl-approve" ? home.owlCard(home.owlApproveId) : null
  readonly property string approveTitle: approveCard && approveCard.info && approveCard.info.name
    ? "Allow \u201c" + approveCard.info.name + "\u201d?" : "Allow this widget?"

  component Section: Column {
    id: section
    property string title: ""
    property bool warn: false
    width: parent ? parent.width : 0
    spacing: Style.spacing.xs
    Text {
      width: section.width
      textFormat: Text.PlainText
      text: section.title
      color: section.warn ? Commons.Color.urgent : sheets.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      font.bold: true
      wrapMode: Text.Wrap
    }
  }

  component CodeLine: Rectangle {
    id: codeLine
    property string code: ""
    width: parent ? parent.width : 0
    height: codeText.implicitHeight + Style.spacing.md * 2
    radius: Style.cornerRadius
    color: Util.alpha(sheets.fg, 0.06)
    Text {
      id: codeText
      x: Style.spacing.md
      y: Style.spacing.md
      width: codeLine.width - Style.spacing.md * 2
      textFormat: Text.PlainText
      text: codeLine.code
      color: sheets.fg
      font.family: Style.font.family
      font.pixelSize: Readable.px(Style.font.caption)
      wrapMode: Text.WrapAnywhere
      maximumLineCount: 8
      elide: Text.ElideRight
    }
  }

  Component {
    id: approveSheet
    Flickable {
      id: approveFlick
      implicitHeight: approveColumn.implicitHeight
      contentHeight: approveColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      readonly property var card: sheets.approveCard
      readonly property var info: card ? card.info : null
      readonly property var caps: info && info.ok ? info.caps : null
      readonly property var program: info && info.ok ? info.program : null
      readonly property var packages: program && program.requires && program.requires.pacman ? program.requires.pacman : []
      property bool internet: false
      readonly property bool builtin: HomeModel.isOwlType(sheets.home.owlApproveId)
      readonly property string placeType: builtin ? sheets.home.owlApproveId : UserWidgets.typeFor(sheets.home.owlApproveId)
      readonly property bool placed: {
        const type = approveFlick.placeType
        return sheets.home.layout.pages.some(function(p) { return p.items.some(function(i) { return i.type === type }) })
      }

      Column {
        id: approveColumn
        width: parent.width
        spacing: Style.spacing.xl

        Label {
          width: parent.width
          text: "This OWL widget runs inside the home screen, as you. Omarchy Mobile read its file and lists everything it can do below. Nothing runs until you allow it, and if the widget changes what it runs, it asks again."
        }

        Section {
          visible: !!approveFlick.caps && approveFlick.caps.commands.length > 0
          title: approveFlick.caps ? "Runs " + (approveFlick.caps.commands.length === 1 ? "this command" : "these " + approveFlick.caps.commands.length + " commands") : ""
          Repeater {
            model: approveFlick.caps ? approveFlick.caps.commands : []
            delegate: CodeLine { required property var modelData; code: modelData }
          }
        }

        Section {
          visible: !!approveFlick.caps && approveFlick.caps.network
          title: "Uses the internet"
          Label {
            width: parent.width
            text: approveFlick.caps && approveFlick.caps.hosts.length
              ? "It talks to " + approveFlick.caps.hosts.join(", ") + "."
              : "Its commands reach the network."
          }
          Item {
            width: parent.width
            height: sheets.touch
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Use the internet"
              color: sheets.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.title
            }
            ToggleSwitch {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: approveFlick.internet
              onToggled: approveFlick.internet = !checked
            }
          }
          Label {
            width: parent.width
            text: "Off: whatever uses the internet waits until you turn it on, as for the built-in widgets."
          }
        }

        Section {
          visible: !!approveFlick.caps && approveFlick.caps.files.length > 0
          title: "Reads these files"
          Repeater {
            model: approveFlick.caps ? approveFlick.caps.files : []
            delegate: CodeLine { required property var modelData; code: modelData }
          }
        }

        Section {
          visible: !!approveFlick.caps && (approveFlick.caps.devices.length > 0 || approveFlick.caps.terminal)
          title: "Uses the phone"
          Repeater {
            model: approveFlick.caps ? approveFlick.caps.devices : []
            delegate: Label {
              required property var modelData
              width: parent.width
              text: modelData === "haptic" ? "It vibrates (a short tap, as your feedback setting allows)." : "It switches the torch on and off."
            }
          }
          Label {
            visible: !!approveFlick.caps && approveFlick.caps.terminal
            width: parent.width
            text: "It has a terminal in its tile: what you type there runs as you. Its command is listed above."
          }
        }

        Section {
          visible: approveFlick.packages.length > 0
          title: "Needs " + approveFlick.packages.join(", ")
          Label {
            width: parent.width
            text: "It never installs anything. If a package is missing, install it yourself (Omarchy's Install package)."
          }
        }

        Section {
          visible: !!approveFlick.caps && approveFlick.caps.risks.length > 0
          warn: true
          title: "\u26a0 Look twice"
          Repeater {
            model: approveFlick.caps ? approveFlick.caps.risks : []
            delegate: Label {
              required property var modelData
              width: parent.width
              color: Commons.Color.urgent
              text: "It " + modelData.says + ": " + OwlCatalog.shortCommand(modelData.line, 60)
            }
          }
        }

        Section {
          visible: !!approveFlick.caps && approveFlick.caps.commands.length === 0 && !approveFlick.caps.network && approveFlick.caps.files.length === 0
          title: "Runs no commands and reaches nothing outside itself"
        }

        Label {
          width: parent.width
          text: (approveFlick.builtin
            ? "A built-in widget: " + HomeModel.owlStoreId(sheets.home.owlApproveId) + " from the OWL widget store, reviewed there and shipped with Omarchy Mobile."
            : "From your widgets folder (" + UserWidgets.tildePath(sheets.home.widgetsDir, sheets.home.homeDir) + "/" + sheets.home.owlApproveId + "). Nobody reviewed it.")
            + " This is a guard rail, not a sandbox: an allowed command runs with your rights."
        }

        Row {
          spacing: Style.spacing.lg
          SheetButton {
            label: approveFlick.placed ? "Allow" : "Allow and add"
            primary: true
            enabled: !!approveFlick.info && approveFlick.info.ok
            onClicked: {
              const id = sheets.home.owlApproveId
              sheets.home.approveOwl(id, approveFlick.internet)
              if (!approveFlick.placed) sheets.home.addWidgetHere(approveFlick.placeType)
              else sheets.home.sheet = ""
            }
          }
          SheetButton {
            label: "Not now"
            onClicked: sheets.home.sheet = approveFlick.placed ? "" : "widgets"
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- create or change a widget with AI

  readonly property var createRecord: home && home.createMode === "edit" ? UserWidgets.findRecord(home.userScan, home.createTarget) : null
  readonly property string createTitle: !home ? ""
    : home.createMode === "edit" ? "Change " + (createRecord && createRecord.manifest ? createRecord.manifest.name : home.createTarget)
    : "Create a widget"

  Component {
    id: createSheet
    Item {
      implicitHeight: createColumn.implicitHeight + Style.spacing.lg + createFooter.height

      Flickable {
        id: createFlick
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: createFooter.top
        anchors.bottomMargin: Style.spacing.lg
        contentHeight: createColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        readonly property bool editMode: sheets.home.createMode === "edit"
        Connections { target: sheets; function onFocusedItemChanged() { sheets.keepInView(createFlick) } }
        Connections {
          target: sheets.focusedItem
          ignoreUnknownSignals: true
          function onCursorRectangleChanged() { sheets.keepInView(createFlick) }
        }
        onHeightChanged: sheets.keepInView(createFlick)

        function go() {
          if (editMode) sheets.home.editWidget(sheets.home.createTarget, sheets.home.createText)
          else sheets.home.createWidgetNow(sheets.home.createText)
        }

        Column {
          id: createColumn
          width: parent.width
          spacing: Style.spacing.lg

          Label {
            width: parent.width
            text: createFlick.editMode ? "Describe what to change." : "Describe the widget you want."
          }
          TextField {
            id: describe
            width: parent.width
            height: sheets.touch
            font.pixelSize: Style.font.title
            foreground: sheets.fg
            placeholderText: createFlick.editMode ? "What should change?" : "What should it show or do?"
            text: sheets.home.createText
            onTextEdited: sheets.home.createText = text
            Keys.onReturnPressed: createFlick.go()
            Component.onCompleted: Qt.callLater(function() { describe.forceActiveFocus() })
          }
          Text {
            visible: sheets.home.createError !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: sheets.home.createError
            color: Commons.Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }
        }
      }

      // Pinned under the field, above the keyboard.
      Row {
        id: createFooter
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: sheets.touch
        spacing: Style.spacing.lg
        SheetButton {
          label: sheets.home.helperBusy ? "Starting…" : (createFlick.editMode ? "Edit with AI" : "Create")
          primary: true
          enabled: !sheets.home.helperBusy && (createFlick.editMode || sheets.home.createText.trim() !== "")
          onClicked: createFlick.go()
        }
        SheetButton {
          label: "Back"
          onClicked: sheets.home.sheet = "widgets"
        }
      }
    }
  }

  // ---------------------------------------------------------------- add an app

  Component {
    id: appsSheet
    Item {
      implicitHeight: 9999
      property string query: ""

      TextField {
        id: search
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: sheets.touch
        font.pixelSize: Style.font.title
        placeholderText: "Search apps"
        foreground: sheets.fg
        onTextEdited: parent.query = text
        Component.onCompleted: Qt.callLater(function() { search.forceActiveFocus() })
        Keys.onReturnPressed: if (list.count > 0) sheets.home.addAppHere(list.model[0].entry.id)
      }

      ListView {
        id: list
        anchors.top: search.bottom
        anchors.topMargin: Style.spacing.lg
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: sheets.home && sheets.home.appLibrary ? sheets.home.appLibrary.sortedEntries(parent.query) : []
        delegate: Row2 {
          required property var modelData
          width: ListView.view.width
          image: sheets.home.appLibrary.iconSource(modelData.entry.icon)
          title: sheets.home.appLibrary.entryName(modelData.entry)
          subtitle: sheets.home.appLibrary.entrySubtext(modelData.entry) || ""
          onClicked: sheets.home.addAppHere(modelData.entry.id)
        }
      }
    }
  }

  // ---------------------------------------------------------------- pages

  Component {
    id: pagesSheet
    Flickable {
      implicitHeight: pagesColumn.implicitHeight
      contentHeight: pagesColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: pagesColumn
        width: parent.width
        spacing: Style.spacing.sm

        Repeater {
          model: sheets.home.layout.pages.length
          delegate: Item {
            required property int index
            readonly property var layout: sheets.home.layout
            width: pagesColumn.width
            height: sheets.touch + 8
            property bool confirm: false

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: index === sheets.home.currentPage ? Style.selectedFillFor(sheets.fg, Commons.Color.accent) : "transparent"
            }

            MouseArea { anchors.fill: parent; onClicked: sheets.home.goToPage(index, true) }

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              Text {
                textFormat: Text.PlainText
                text: "Page " + (index + 1) + (index === layout.home ? "  󰋜" : "")
                color: sheets.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.title
              }
              Text {
                textFormat: Text.PlainText
                text: layout.pages[index].items.length === 1 ? "1 item" : layout.pages[index].items.length + " items"
                color: sheets.dim
                font.family: Style.font.family
                font.pixelSize: Readable.px(Style.font.caption)
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              Button {
                width: sheets.touch; height: sheets.touch
                iconText: "󰋜"; iconSize: Style.font.iconLarge
                foreground: index === layout.home ? Commons.Color.accent : sheets.fg
                onClicked: sheets.home.commit(HomeModel.setHome(layout, index))
              }
              Button {
                width: sheets.touch; height: sheets.touch
                iconText: "󰁍"; iconSize: Style.font.iconLarge
                foreground: sheets.fg
                opacity: index > 0 ? 1 : 0.3
                onClicked: if (index > 0) { sheets.home.commit(HomeModel.movePage(layout, index, index - 1)); sheets.home.goToPage(index - 1, false) }
              }
              Button {
                width: sheets.touch; height: sheets.touch
                iconText: "󰁔"; iconSize: Style.font.iconLarge
                foreground: sheets.fg
                opacity: index < layout.pages.length - 1 ? 1 : 0.3
                onClicked: if (index < layout.pages.length - 1) { sheets.home.commit(HomeModel.movePage(layout, index, index + 1)); sheets.home.goToPage(index + 1, false) }
              }
              Button {
                width: sheets.touch; height: sheets.touch
                // A page with things on it asks first.
                iconText: parent.parent.confirm ? "󰄬" : "󰆴"; iconSize: Style.font.iconLarge
                foreground: parent.parent.confirm ? Commons.Color.urgent : sheets.fg
                opacity: layout.pages.length > 1 ? 1 : 0.3
                onClicked: {
                  var row = parent.parent
                  if (layout.pages.length <= 1) return
                  if (layout.pages[index].items.length > 0 && !row.confirm) { row.confirm = true; return }
                  row.confirm = false
                  sheets.home.commit(HomeModel.removePage(layout, index))
                }
              }
            }
          }
        }

        SheetButton {
          width: pagesColumn.width
          label: "Add a page"
          enabled: sheets.home.layout.pages.length < HomeModel.LIMITS.maxPages
          onClicked: {
            sheets.home.commit(HomeModel.addPage(sheets.home.layout))
            sheets.home.goToPage(sheets.home.layout.pages.length - 1, true)
          }
        }

        Item { width: 1; height: Style.spacing.lg }

        // Grid size. Shrinking re-places what no longer fits.
        Repeater {
          model: [
            { label: "Columns", key: "columns", min: HomeModel.LIMITS.minColumns, max: HomeModel.LIMITS.maxColumns },
            { label: "Rows", key: "rows", min: HomeModel.LIMITS.minRows, max: HomeModel.LIMITS.maxRows }
          ]
          delegate: Item {
            required property var modelData
            width: pagesColumn.width
            height: sheets.touch
            readonly property int value: sheets.home.layout.grid[modelData.key]
            function set(v) {
              var g = sheets.home.layout.grid
              sheets.home.commit(HomeModel.setGrid(sheets.home.layout,
                modelData.key === "columns" ? v : g.columns, modelData.key === "rows" ? v : g.rows, sheets.home.userCatalog))
            }
            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.label
              color: sheets.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.title
            }
            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              Button {
                width: sheets.touch; height: sheets.touch
                iconText: "󰍴"; iconSize: Style.font.iconLarge; foreground: sheets.fg
                opacity: value > modelData.min ? 1 : 0.3
                onClicked: if (value > modelData.min) set(value - 1)
              }
              Text {
                width: sheets.touch; height: sheets.touch
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: value
                color: sheets.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
              }
              Button {
                width: sheets.touch; height: sheets.touch
                iconText: "󰐕"; iconSize: Style.font.iconLarge; foreground: sheets.fg
                opacity: value < modelData.max ? 1 : 0.3
                onClicked: if (value < modelData.max) set(value + 1)
              }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- one widget's settings

  readonly property var settingsItem: {
    if (!home || which !== "settings") return null
    var found = HomeModel.findItem(home.layout, home.settingsId)
    return found ? found.item : null
  }
  readonly property var settingsSpec: settingsItem && home ? HomeModel.specFor(settingsItem.type, home.userCatalog) : null
  readonly property string settingsTitle: settingsSpec ? settingsSpec.name : ""
  // A user widget's id and scan record, when the settings are a user widget's.
  readonly property string settingsUserId: settingsItem ? UserWidgets.idOf(settingsItem.type) : ""
  readonly property var settingsRecord: settingsUserId && home ? UserWidgets.findRecord(home.userScan, settingsUserId) : null
  readonly property var settingsCard: settingsUserId && home ? home.userCard(settingsUserId) : null

  Component {
    id: settingsSheet
    Item {
      implicitHeight: form.implicitHeight + Style.spacing.lg + settingsFooter.height

      Flickable {
        id: settingsFlick
        readonly property var item: sheets.settingsItem
        readonly property var config: item ? item.config : ({})
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: settingsFooter.top
        anchors.bottomMargin: Style.spacing.lg
        contentHeight: form.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // The focused field (or a note's cursor) stays above the keyboard.
        Connections { target: sheets; function onFocusedItemChanged() { sheets.keepInView(settingsFlick) } }
        Connections {
          target: sheets.focusedItem
          ignoreUnknownSignals: true
          function onCursorRectangleChanged() { sheets.keepInView(settingsFlick) }
        }
        onHeightChanged: sheets.keepInView(settingsFlick)

        // Fields write here; Save hands the patch to the layout.
        property var patch: ({})
        function put(key, value) { var p = Object.assign({}, patch); p[key] = value; patch = p }
        function value(key) { return patch[key] !== undefined ? patch[key] : config[key] }
        property string failure: ""
        property bool busy: false
        // Remove's first tap; a different widget's settings start over.
        property bool confirmRemove: false
        onItemChanged: confirmRemove = false

        function save() {
          if (!item) return
          var p = Object.assign({}, patch)
          if (item.type === "command" && p.interval !== undefined) p.interval = Math.max(0, parseInt(p.interval, 10) || 0)
          // A user widget's fields are typed by its manifest's schema, and a
          // ported built-in's by its registry schema (the same format).
          if (sheets.settingsSpec && sheets.settingsSpec.schema) {
            var schema = sheets.settingsSpec && sheets.settingsSpec.schema ? sheets.settingsSpec.schema : []
            Object.keys(p).forEach(function(key) {
              var field = schema.filter(function(f) { return f.key === key })[0]
              var typed = UserWidgets.coerceSetting(field, p[key])
              if (typed === null) delete p[key]
              else p[key] = typed
            })
          }
          // The weather widget looks its place up once, when it is saved. With
          // "Use my location" on, the place is only the fallback, and may be empty.
          if (item.type === "weather" && value("enabled") === true
              && (p.place !== undefined || (typeof config.latitude !== "number" && value("useLocation") === false))) {
            var place = String(value("place") || "").trim()
            if (!place && value("useLocation") !== false) {
              p.place = ""; p.latitude = null; p.longitude = null
              sheets.home.setConfig(item.id, p)
              sheets.close()
              return
            }
            if (!place) { failure = "Name a place, or use your location"; return }
            busy = true
            var xhr = new XMLHttpRequest()
            var id = item.id
            xhr.onreadystatechange = function() {
              if (xhr.readyState !== XMLHttpRequest.DONE) return
              settingsFlick.busy = false
              var found = xhr.status === 200 ? HomeModel.parseGeocode(xhr.responseText) : null
              if (!found) { settingsFlick.failure = xhr.status === 200 ? "Place not found" : "No connection to open-meteo.com"; return }
              p.place = found.name; p.latitude = found.latitude; p.longitude = found.longitude
              sheets.home.setConfig(id, p)
              sheets.close()
            }
            xhr.open("GET", HomeModel.geocodeUrl(place))
            xhr.send()
            return
          }
          sheets.home.setConfig(item.id, p)
          sheets.close()
        }

        Column {
          id: form
          width: parent.width
          spacing: Style.spacing.lg

          // -- clock
          Label { visible: settingsFlick.item && settingsFlick.item.type === "clock"; width: parent.width
                  text: "Time and date formats use Qt's patterns: HH:mm, h:mm AP, dddd d MMMM, yyyy-MM-dd." }
          TextField {
            visible: settingsFlick.item && settingsFlick.item.type === "clock"
            width: parent.width; height: sheets.touch; font.pixelSize: Style.font.title; foreground: sheets.fg
            placeholderText: "Time format (empty: follow the system)"
            text: settingsFlick.config.timeFormat || ""
            onTextEdited: settingsFlick.put("timeFormat", text)
          }
          TextField {
            visible: settingsFlick.item && settingsFlick.item.type === "clock"
            width: parent.width; height: sheets.touch; font.pixelSize: Style.font.title; foreground: sheets.fg
            placeholderText: "Date format"
            text: settingsFlick.config.dateFormat || ""
            onTextEdited: settingsFlick.put("dateFormat", text)
          }

          // -- weather
          Item {
            visible: settingsFlick.item && settingsFlick.item.type === "weather"
            width: parent.width; height: sheets.touch
            Text {
              anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText; text: "Show the weather"
              color: sheets.fg; font.family: Style.font.family; font.pixelSize: Style.font.title
            }
            ToggleSwitch {
              anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
              checked: settingsFlick.value("enabled") === true
              onToggled: settingsFlick.put("enabled", !checked)
            }
          }
          Item {
            visible: settingsFlick.item && settingsFlick.item.type === "weather"
            width: parent.width; height: sheets.touch
            Text {
              anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText; text: "Use my location"
              color: sheets.fg; font.family: Style.font.family; font.pixelSize: Style.font.title
            }
            ToggleSwitch {
              anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
              checked: settingsFlick.value("useLocation") !== false
              onToggled: settingsFlick.put("useLocation", !checked)
            }
          }
          Label {
            visible: settingsFlick.item && settingsFlick.item.type === "weather"; width: parent.width
            text: "Turned on, the phone asks open-meteo.com for the forecast every 30 minutes, sending only coordinates rounded to about 1 km: the phone's position (from Location, at city accuracy) when \"Use my location\" is on and one is known, otherwise the place below, which open-meteo.com looks up once. No account, no key, nothing else is sent."
          }
          TextField {
            visible: settingsFlick.item && settingsFlick.item.type === "weather"
            width: parent.width; height: sheets.touch; font.pixelSize: Style.font.title; foreground: sheets.fg
            placeholderText: settingsFlick.value("useLocation") !== false ? "Place when there is no location" : "City or place"
            text: settingsFlick.config.place || ""
            onTextEdited: settingsFlick.put("place", text)
          }
          Row {
            visible: settingsFlick.item && settingsFlick.item.type === "weather"
            spacing: Style.spacing.lg
            Repeater {
              model: [{ label: "°C", value: "celsius" }, { label: "°F", value: "fahrenheit" }]
              delegate: SheetButton {
                required property var modelData
                label: modelData.label
                primary: settingsFlick.value("units") === modelData.value
                onClicked: settingsFlick.put("units", modelData.value)
              }
            }
          }

          // -- note
          Rectangle {
            visible: settingsFlick.item && settingsFlick.item.type === "notes"
            width: parent.width
            height: Math.max(sheets.touch * 3, noteEdit.implicitHeight + Style.spacing.lg * 2)
            radius: Style.cornerRadius
            color: Style.normalFill
            border.width: 1
            border.color: noteEdit.activeFocus ? Commons.Color.accent : Util.alpha(sheets.fg, 0.3)
            TextEdit {
              id: noteEdit
              anchors.fill: parent
              anchors.margins: Style.spacing.lg
              text: settingsFlick.config.text || ""
              color: sheets.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              wrapMode: TextEdit.Wrap
              selectByMouse: true
              onTextChanged: if (activeFocus) settingsFlick.put("text", text)
              Component.onCompleted: if (settingsFlick.item && settingsFlick.item.type === "notes") Qt.callLater(function() { noteEdit.forceActiveFocus() })
            }
          }

          // -- text or command
          Repeater {
            model: settingsFlick.item && settingsFlick.item.type === "command" ? [
              { key: "title", hint: "Title (optional)" },
              { key: "text", hint: "Text to show (when there's no command)" },
              { key: "command", hint: "Command (sh -c), e.g. uptime -p" },
              { key: "interval", hint: "Run every N seconds (0: once)" },
              { key: "tap", hint: "Command on tap (optional)" }
            ] : []
            delegate: TextField {
              required property var modelData
              width: form.width; height: sheets.touch; font.pixelSize: Style.font.title; foreground: sheets.fg
              placeholderText: modelData.hint
              text: settingsFlick.config[modelData.key] !== undefined && settingsFlick.config[modelData.key] !== "" ? String(settingsFlick.config[modelData.key]) : ""
              inputMethodHints: modelData.key === "interval" ? Qt.ImhDigitsOnly : Qt.ImhNone
              onTextEdited: settingsFlick.put(modelData.key, text)
            }
          }
          Label {
            visible: settingsFlick.item && settingsFlick.item.type === "command"; width: parent.width
            text: "The command runs as you, through sh, with a 10 second limit; its first lines are shown."
          }

          // -- a user widget: what's wrong, its manifest's settings, where it lives
          Text {
            visible: !!sheets.settingsCard && sheets.settingsCard.state !== "ok"
            width: parent.width
            textFormat: Text.PlainText
            text: sheets.settingsCard ? sheets.settingsCard.message : ""
            color: Commons.Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }
          Repeater {
            model: sheets.settingsSpec && sheets.settingsSpec.schema ? sheets.settingsSpec.schema : []
            delegate: Column {
              id: fieldColumn
              required property var modelData
              width: form.width
              spacing: Style.spacing.xs
              readonly property string fieldKey: modelData.key
              readonly property var current: settingsFlick.value(modelData.key)

              Item {
                width: parent.width
                height: modelData.type === "boolean" ? sheets.touch : fieldLabel.implicitHeight
                Text {
                  id: fieldLabel
                  anchors.left: parent.left
                  anchors.right: modelData.type === "boolean" ? toggle.left : parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: sheets.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  elide: Text.ElideRight
                }
                ToggleSwitch {
                  id: toggle
                  visible: modelData.type === "boolean"
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  checked: current === true
                  onToggled: settingsFlick.put(modelData.key, !checked)
                }
              }
              TextField {
                visible: ["string", "path", "integer", "number"].indexOf(modelData.type) >= 0
                width: parent.width; height: visible ? sheets.touch : 0
                font.pixelSize: Style.font.title; foreground: sheets.fg
                placeholderText: modelData.description || ""
                text: current === undefined || current === null ? "" : String(current)
                inputMethodHints: modelData.type === "integer" || modelData.type === "number" ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
                onTextEdited: settingsFlick.put(modelData.key, text)
              }
              Flow {
                visible: modelData.type === "enum"
                width: parent.width
                spacing: Style.spacing.sm
                Repeater {
                  model: modelData.type === "enum" ? modelData.options : []
                  delegate: SheetButton {
                    required property var modelData
                    label: modelData
                    primary: fieldColumn.current === modelData
                    onClicked: settingsFlick.put(fieldColumn.fieldKey, modelData)
                  }
                }
              }
              Label {
                visible: !!modelData.description && modelData.type !== "string" && modelData.type !== "path"
                width: parent.width
                text: modelData.description || ""
              }
            }
          }
          Label {
            visible: !!sheets.settingsUserId
            width: parent.width
            text: !sheets.settingsRecord ? "" : UserWidgets.tildePath(sheets.settingsRecord.dir, Quickshell.env("HOME"))
              + (sheets.settingsRecord.manifest && sheets.settingsRecord.manifest.capabilities.length
                 ? "\nIt " + UserWidgets.capabilityText(sheets.settingsRecord.manifest.capabilities) + " (declared)." : "\nNo commands, no network.")
              + (sheets.settingsRecord.warnings.length ? "\n" + sheets.settingsRecord.warnings.slice(0, 4).join("\n") : "")
          }

          // -- a built-in ported from omarchy-widgets: what it talks to, and whose it is
          Label {
            visible: !sheets.settingsUserId && !!sheets.settingsSpec && !!sheets.settingsSpec.credit
            width: parent.width
            text: !sheets.settingsSpec || !sheets.settingsSpec.credit ? ""
              : (sheets.settingsSpec.network ? "Uses the internet once turned on: " + (sheets.settingsSpec.source || "") + ".\n" : "")
                + "Ported from " + sheets.settingsSpec.credit + " in Simon Schubert's omarchy-widgets (MIT)."
          }

          // -- the rest
          Label {
            visible: settingsFlick.item && ["battery", "media", "agenda", "toggles"].indexOf(settingsFlick.item.type) >= 0
            width: parent.width
            text: !settingsFlick.item ? "" : settingsFlick.item.type === "agenda"
              ? "Events come from khal (the local calendar vdirsyncer syncs), when it's installed. Without it, the month is shown."
              : "Nothing to set. Drag the corner handle to resize."
          }

          Text {
            visible: settingsFlick.failure !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: settingsFlick.failure
            color: Commons.Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }

      // Save on the left, Remove at the far right: removing deletes the
      // widget with its settings, so it asks first, as the Widgets and
      // Pages sheets do (the second tap removes), and the home screen then
      // offers Undo. Pinned under the form, so they never scroll away or
      // under the keyboard.
      Item {
        id: settingsFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: sheets.touch
        Row {
          spacing: Style.spacing.lg
          SheetButton {
            label: settingsFlick.busy ? "Looking up…" : "Save"
            primary: true
            enabled: !settingsFlick.busy
            onClicked: settingsFlick.save()
          }
          SheetButton {
            visible: !!sheets.settingsUserId
            label: "Edit with AI"
            onClicked: sheets.home.openCreate("edit", sheets.settingsUserId)
          }
        }
        SheetButton {
          anchors.right: parent.right
          label: settingsFlick.confirmRemove ? "Remove?" : "Remove"
          danger: true
          armed: settingsFlick.confirmRemove
          onClicked: {
            if (!settingsFlick.confirmRemove) { settingsFlick.confirmRemove = true; return }
            settingsFlick.confirmRemove = false
            sheets.home.removeItem(settingsFlick.item.id)
          }
        }
      }
    }
  }
}
