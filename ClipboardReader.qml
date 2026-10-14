import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property var recipient: null
  property int revision: -1

  function paste(field) {
    if (!field.inputActive || !field.activeFocus || reader.running) return
    recipient = field
    revision = field.revision
    field.errorText = ""
    reader.running = true
  }

  Process {
    id: reader
    objectName: "clipboardProvider"
    running: false
    command: ["/usr/bin/python", Quickshell.env("HOME") + "/.config/omarchy/plugins/cbayschm.openclash/clipboard_read.py"]
    stdout: StdioCollector { id: output; waitForEnd: true }
    onExited: function(exitCode) {
      var field = root.recipient
      root.recipient = null
      // Closing, hiding, editing, or moving focus invalidates the request.
      if (!field || !field.inputActive || !field.activeFocus || field.revision !== root.revision) return
      try {
        var result = JSON.parse(output.text)
        if (exitCode === 0 && result.ok === true && typeof result.text === "string") field.insertText(result.text)
        else field.errorText = "Paste failed or exceeded the clipboard limits"
      } catch (error) { field.errorText = "Paste failed" }
    }
  }
}
