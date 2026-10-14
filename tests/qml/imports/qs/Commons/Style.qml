pragma Singleton
import QtQuick
QtObject {
  readonly property int cornerRadius: 4
  readonly property var font: ({ family: "sans-serif", body: 14, caption: 12 })
  function space(n) { return n }
}
