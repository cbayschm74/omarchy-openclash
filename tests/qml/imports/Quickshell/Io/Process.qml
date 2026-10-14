import QtQuick
Item {
  property bool running: false
  property var command: []
  property QtObject stdout
  signal exited(int exitCode)
  function complete(text, code) { stdout.text=text; running=false; exited(code) }
}
