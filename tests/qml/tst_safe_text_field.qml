import QtQuick
import QtTest
import "../../" as Plugin

Item {
  width: 400; height: 200
  property string value: ""
  Plugin.SafeTextField {
    id: field
    width: 300
    inputActive: true
    text: parent.value
    onEdited: function(v) { parent.value = v }
  }
  Plugin.SafeTextField { id: second; y: 70; width: 300; inputActive: true }
  Plugin.ClipboardReader { id: clipboard }
  SignalSpy { id: pasted; target: field; signalName: "pasteRequested" }
  SignalSpy { id: accepted; target: field; signalName: "accepted" }
  TestCase {
    name: "SafeTextField"
    when: windowShown
    function init() {
      field.parent.value = ""; field.inputActive = true; field.maximumLength = 2048
      field.password = false; field.errorText = ""; pasted.clear(); accepted.clear()
      field.forceActiveFocus(); wait(1)
      var proc=findChild(clipboard,"clipboardProvider")
      if (proc.running) proc.complete('{"ok":false}',0)
    }
    function test_typing_selection_and_external_clear() {
      keyClick(Qt.Key_A); keyClick(Qt.Key_B); keyClick(Qt.Key_C); keyClick(Qt.Key_D)
      compare(field.text,"abcd")
      keyClick(Qt.Key_Left); keyClick(Qt.Key_Backspace); compare(field.text,"abd")
      keyClick(Qt.Key_A,Qt.ControlModifier); keyClick(Qt.Key_X); compare(field.text,"x")
      field.parent.value=""; compare(field.text,"")
    }
    function test_paste_is_explicit_and_inactive_fields_do_nothing() {
      keyClick(Qt.Key_V,Qt.ControlModifier); compare(pasted.count,1); compare(field.text,"")
      field.inputActive=false; field.insertText("should-not-appear"); compare(field.text,"")
    }
    function test_length_password_enter_and_tab() {
      field.maximumLength=2
      keyClick(Qt.Key_A); keyClick(Qt.Key_B); keyClick(Qt.Key_C); compare(field.text,"ab")
      verify(field.errorText.length>0)
      field.password=true; compare(field.displayText,"••")
      keyClick(Qt.Key_Return); compare(accepted.count,1)
      keyClick(Qt.Key_Tab); verify(second.activeFocus)
    }
    function test_late_paste_is_discarded_after_edit_hide_and_focus_change() {
      var proc=findChild(clipboard,"clipboardProvider")
      clipboard.paste(field); verify(proc.running)
      field.insertText("typed")
      proc.complete('{"ok":true,"text":"late"}',0); compare(field.text,"typed")
      clipboard.paste(field); field.inputActive=false
      proc.complete('{"ok":true,"text":"late"}',0); compare(field.text,"typed")
      field.inputActive=true; field.forceActiveFocus()
      clipboard.paste(field); second.forceActiveFocus()
      proc.complete('{"ok":true,"text":"late"}',0); compare(field.text,"typed")
      field.forceActiveFocus(); clipboard.paste(field)
      proc.complete('{"ok":true,"text":" pasted"}',0); compare(field.text,"typed pasted")
    }
  }
}
