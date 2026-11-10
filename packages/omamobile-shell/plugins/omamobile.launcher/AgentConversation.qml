// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// The phone's conversation hierarchy, with no authentication or voice facade.
Item {
  id: root
  property var controller: null
  property string agentName: "Agent"
  property string draft: ""
  onDraftChanged: if (composer.text !== draft) composer.text = draft
  property color foreground: Commons.Color.menu.text
  property color muted: Commons.Color.muted
  property color cardColor: Commons.Color.menu.background
  readonly property var inputField: composer
  signal backRequested()
  signal closeRequested()
  signal sendRequested(string prompt)
  signal handoffRequested(string prompt)
  signal chooseAgentRequested()
  signal newChatRequested()
  readonly property int touch: Math.max(44, Style.space(44))

  component Action: Rectangle {
    id: action
    property string label: ""
    signal tapped()
    implicitWidth: Math.max(root.touch, actionText.implicitWidth + Style.space(24))
    implicitHeight: root.touch
    radius: Style.cornerRadius
    color: actionTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : root.cardColor
    opacity: enabled ? 1 : 0.45
    Accessible.name: label
    Accessible.role: Accessible.Button
    Text { id: actionText; anchors.centerIn: parent; text: action.label; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; textFormat: Text.PlainText }
    MouseArea { id: actionTouch; anchors.fill: parent; onClicked: action.tapped() }
  }
  ColumnLayout {
    anchors.fill: parent
    anchors.leftMargin: Math.min(Style.space(24), root.width / 8)
    anchors.rightMargin: anchors.leftMargin
    anchors.topMargin: Style.space(root.height < 400 ? 8 : 12)
    anchors.bottomMargin: Style.space(root.height < 400 ? 8 : 16)
    spacing: Style.space(root.height < 400 ? 8 : 16)
    RowLayout {
      Layout.fillWidth: true
      Layout.preferredHeight: root.touch
      Layout.maximumHeight: root.touch
      spacing: Style.spacing.lg
      Action { objectName: "agentBack"; label: "‹"; Accessible.name: "Back to search"; onTapped: root.backRequested() }
      Text { Layout.fillWidth: true; text: root.agentName; textFormat: Text.PlainText; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true; elide: Text.ElideRight; Accessible.name: "Choose agent"; Accessible.role: Accessible.Button; MouseArea { anchors.fill: parent; enabled: !root.controller || !root.controller.busy; onClicked: root.chooseAgentRequested() } }
      Action { objectName: "agentClose"; label: "×"; Accessible.name: "Close search"; onTapped: root.closeRequested() }
    }
    ListView {
      id: history
      objectName: "agentMessages"
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      clip: true
      spacing: Style.space(16)
      model: root.controller ? root.controller.messages : []
      boundsBehavior: Flickable.StopAtBounds
      onCountChanged: Qt.callLater(function() { history.positionViewAtEnd() })
      Connections { target: root.controller; function onMessagesChanged() { if (history.atYEnd || root.controller.busy) Qt.callLater(function() { history.positionViewAtEnd() }) } }
      delegate: Item {
        required property var modelData
        width: history.width
        height: bubble.height
        Rectangle {
          id: bubble
          anchors.right: modelData.role === "user" ? parent.right : undefined
          anchors.left: modelData.role !== "user" ? parent.left : undefined
          width: modelData.role === "user" ? Math.min(Style.space(290), parent.width * 0.85) : parent.width
          height: message.implicitHeight + Style.space(32)
          radius: Style.cornerRadius
          color: modelData.role === "user" ? root.cardColor : "transparent"
          Text {
            id: message
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(16) }
            text: modelData.text
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
          }
        }
      }
      Text {
        parent: history
        anchors.centerIn: parent
        width: parent.width
        visible: !root.controller || root.controller.messages.length === 0
        text: "Ask " + root.agentName + "\nYour draft stays editable. Send when you are ready."
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        color: root.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
    Text {
      objectName: "agentStatus"
      Layout.fillWidth: true
      visible: root.controller && (root.controller.busy || root.controller.resetPending || root.controller.error || !root.controller.capabilityKnown || !root.controller.available)
      text: !root.controller ? "" : root.controller.error || (root.controller.resetPending ? "Resetting conversation…" : root.controller.stoppingId ? "Stopping…" : root.controller.busy ? "Working…" : !root.controller.capabilityKnown ? "Checking agent…" : root.controller.reason || "Native conversation is unavailable for this agent. Continue in its terminal app.")
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Rectangle {
      Layout.fillWidth: true
      implicitHeight: composerLayout.implicitHeight + Style.space(24)
      radius: Style.cornerRadius
      color: root.cardColor
      ColumnLayout {
        id: composerLayout
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.spacing.sm
        Controls.TextArea {
          id: composer
          objectName: "agentDraft"
          Layout.fillWidth: true
          Layout.preferredHeight: Math.max(root.touch, Math.min(Style.space(root.height < 400 ? 44 : 108), contentHeight + Style.space(16)))
          clip: true
          padding: Style.spacing.lg
          background: null
          onTextChanged: if (root.draft !== text) root.draft = text
          placeholderText: "Message " + root.agentName
          placeholderTextColor: root.muted
          color: root.foreground
          selectionColor: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: TextEdit.Wrap
          Accessible.name: "Message " + root.agentName
          Keys.onPressed: function(event) {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
              if (root.controller && !root.controller.busy && root.controller.available) root.sendRequested(text)
              event.accepted = true
            }
          }
        }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.lg
          Action { label: root.width >= Style.space(360) ? "New chat" : "+"; Accessible.name: "New chat"; enabled: !root.controller || !root.controller.busy; onTapped: root.newChatRequested() }
          Item { Layout.fillWidth: true }
          Action {
            objectName: "agentSend"
            label: root.controller && root.controller.busy ? "Stop" : root.controller && root.controller.capabilityKnown && !root.controller.available ? "Open in terminal" : "Send →"
            enabled: root.controller && !root.controller.stoppingId && (root.controller.busy || !root.controller.resetPending && root.controller.capabilityKnown && root.draft.trim().length > 0)
            onTapped: {
              if (root.controller.busy) root.controller.cancel()
              else if (!root.controller.available) root.handoffRequested(root.draft)
              else root.sendRequested(root.draft)
            }
          }
        }
      }
    }
  }
}
