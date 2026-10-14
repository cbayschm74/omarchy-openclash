import QtQuick
import qs.Commons
import qs.Commons as Commons
import "InputModel.js" as InputModel

// Item + plain Text deliberately avoids Qt's native editable clipboard path.
Item {
  id: root
  property string text: ""
  property string placeholderText: ""
  property bool password: false
  property int maximumLength: 2048
  property bool inputActive: false
  property string errorText: ""
  property int cursor: text.length
  property int anchor: cursor
  property int revision: 0
  readonly property string displayText: password ? Array(text.length + 1).join("•") : text
  signal accepted()
  signal edited(string value)
  signal pasteRequested()
  signal escapeRequested()
  implicitHeight: Style.space(32) + (errorText ? Style.space(18) : 0)
  activeFocusOnTab: inputActive
  enabled: inputActive

  function applyEdit(result) {
    if (!result) { errorText = "Input is too long or contains a line break"; return }
    edited(result.text)
    cursor = result.cursor
    anchor = result.anchor
    errorText = ""
  }
  function insertText(value) {
    if (inputActive) applyEdit(InputModel.insert(text, cursor, anchor, value, maximumLength))
  }
  onTextChanged: {
    revision += 1
    cursor = text.length
    anchor = cursor
  }
  onActiveFocusChanged: { revision += 1; anchor = cursor }
  onInputActiveChanged: { revision += 1; if (!inputActive) focus = false }

  Keys.onPressed: function(event) {
    if (!inputActive) return
    revision += 1
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    event.accepted = true
    if (ctrl && event.key === Qt.Key_V) { pasteRequested(); return }
    if (ctrl && event.key === Qt.Key_A) { anchor = 0; cursor = text.length; return }
    if (event.key === Qt.Key_Escape) { escapeRequested(); return }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { accepted(); return }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      var next = nextItemInFocusChain(!shift && event.key !== Qt.Key_Backtab)
      if (next) next.forceActiveFocus()
      return
    }
    if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
      applyEdit(InputModel.remove(text, cursor, anchor, event.key === Qt.Key_Backspace)); return
    }
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Home || event.key === Qt.Key_End) {
      if (event.key === Qt.Key_Home) cursor = 0
      else if (event.key === Qt.Key_End) cursor = text.length
      else cursor = event.key === Qt.Key_Left ? InputModel.previous(text, cursor) : InputModel.next(text, cursor)
      if (!shift) anchor = cursor
      revision += 1
      return
    }
    if (!ctrl && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier)) && event.text) insertText(event.text)
  }

  Rectangle {
    id: surface
    width: parent.width
    height: Style.space(32)
    radius: Style.cornerRadius
    color: root.activeFocus ? Util.alpha(Commons.Color.foreground, 0.10) : Util.alpha(Commons.Color.foreground, 0.04)
    border.width: 1
    border.color: root.activeFocus ? Commons.Color.accent : Util.alpha(Commons.Color.foreground, 0.3)
    Item {
      anchors.fill: parent
      anchors.margins: Style.space(8)
      clip: true
      TextMetrics { id: prefix; font: label.font; text: root.displayText.slice(0, root.cursor) }
      TextMetrics { id: selectionStart; font: label.font; text: root.displayText.slice(0, Math.min(root.cursor, root.anchor)) }
      TextMetrics { id: selectionEnd; font: label.font; text: root.displayText.slice(0, Math.max(root.cursor, root.anchor)) }
      readonly property real offset: Math.max(0, prefix.advanceWidth - width + 2)
      Rectangle {
        x: selectionStart.advanceWidth - parent.offset
        width: selectionEnd.advanceWidth - selectionStart.advanceWidth
        height: parent.height
        color: Util.alpha(Commons.Color.accent, 0.3)
        visible: root.activeFocus && root.cursor !== root.anchor
      }
      Text {
        id: label
        x: -parent.offset
        anchors.verticalCenter: parent.verticalCenter
        text: root.text ? root.displayText : root.placeholderText
        textFormat: Text.PlainText
        color: root.text ? Commons.Color.foreground : Qt.darker(Commons.Color.foreground, 1.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Rectangle {
        x: prefix.advanceWidth - parent.offset
        width: 1
        height: parent.height
        color: Commons.Color.foreground
        visible: root.activeFocus
      }
    }
    MouseArea {
      anchors.fill: parent
      enabled: root.inputActive
      cursorShape: Qt.IBeamCursor
      onClicked: { root.forceActiveFocus(); root.cursor = root.text.length; root.anchor = root.cursor }
    }
  }
  Text {
    anchors.top: surface.bottom
    width: parent.width
    text: root.errorText
    textFormat: Text.PlainText
    color: Commons.Color.urgent
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }
}
