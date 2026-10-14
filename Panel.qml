import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "cbayschm.openclash"
  ipcTarget: "cbayschm.openclash"
  manageIpc: false

  property string selectedGroupName: ""
  property string searchText: ""
  property bool sortByPing: false
  property bool editingSetup: false
  property string setupController: ""
  property string setupDashboard: ""
  property string setupSecret: ""
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: openclash.configured && openclash.online ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property var selectedGroup: findGroup(selectedGroupName)
  readonly property var visibleCandidates: filterCandidates(selectedGroup, searchText)

  function pingColor(delay) {
    var value = Number(delay || 0)
    if (value <= 0) return dim
    if (value < 300) return "#7fd88f"
    if (value <= 500) return "#e6c75c"
    return "#e06c75"
  }

  function dashboardLabel(url) {
    var value = String(url || "").toLowerCase()
    try { value = decodeURIComponent(value) } catch (error) {}
    if (value.indexOf("zashboard") !== -1) return "Zashboard"
    if (value.indexOf("metacubexd") !== -1 || value.indexOf("metacube-xd") !== -1) return "MetaCubeXD"
    if (value.indexOf("yacd") !== -1) return "Yacd"
    if (value.indexOf("razord") !== -1) return "Razord"
    return "Dashboard"
  }

  function findGroup(name) {
    for (var i = 0; i < openclash.groups.length; i++) {
      if (openclash.groups[i].name === name) return openclash.groups[i]
    }
    return null
  }

  function filterCandidates(group, query) {
    if (!group || !group.all) return []
    var needle = String(query || "").trim().toLowerCase()
    var result = []
    for (var i = 0; i < group.all.length; i++) {
      var candidate = group.all[i] || {}
      var name = String(candidate.name || "")
      if (needle === "" || name.toLowerCase().indexOf(needle) !== -1) {
        result.push({ name: name, delay: Number(candidate.delay || 0), order: i })
      }
    }
    if (sortByPing) {
      result.sort(function(a, b) {
        var aDelay = Number(a.delay || 0)
        var bDelay = Number(b.delay || 0)
        if (aDelay <= 0 && bDelay > 0) return 1
        if (aDelay > 0 && bDelay <= 0) return -1
        if (aDelay !== bDelay) return aDelay - bDelay
        return a.order - b.order
      })
    }
    return needle === "" && result.length > 120 ? result.slice(0, 120) : result
  }

  function showGroup(name) {
    selectedGroupName = String(name || "")
    searchText = ""
    if (panelFlick) panelFlick.contentY = 0
  }

  function showGroups() {
    selectedGroupName = ""
    searchText = ""
    if (panelFlick) panelFlick.contentY = 0
  }

  function showSetup() {
    setupController = openclash.apiBase
    setupDashboard = openclash.dashboardUrl
    setupSecret = ""
    editingSetup = true
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { if (root.opened) controllerField.forceActiveFocus() })
  }

  function submitSetup() {
    if (String(setupController).trim() === "") return
    if (!openclash.configured && String(setupSecret) === "") return
    openclash.configure(setupController, setupDashboard, setupSecret)
    setupSecret = ""
  }

  function cancelSetup() {
    if (!openclash.configured) return
    editingSetup = false
    setupSecret = ""
    showGroups()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    showGroups()
    openclash.loadSetup()
    if (openclash.configured) openclash.refresh()
  } else {
    setupSecret = ""
    editingSetup = false
  }

  Service { id: openclash; settings: root.settings }
  ClipboardReader { id: clipboardReader }

  Connections {
    target: openclash
    function onSetupRevisionChanged() {
      root.editingSetup = false
      root.setupSecret = ""
      root.showGroups()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { openclash.refresh(); return "ok" }
    function dashboard(): string { openclash.openDashboard(); return "ok" }
    function status(): string { return openclash.online ? "Connected" : openclash.lastError }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Text {
        text: "󰒍"
        textFormat: Text.PlainText
        color: root.barIconColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) openclash.openDashboard()
      else if (buttonCode === Qt.MiddleButton) openclash.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: !openclash.configured || root.editingSetup ? controllerField : (root.selectedGroup !== null ? searchField : null)
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(610))

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: contentColumn
        width: panelFlick.width
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          // PanelHero uses Text.AutoText internally, so keep controller-derived
          // strings out of it and render them in the explicit plain-text label below.
          title: "OpenClash"
          meta: !openclash.configured ? "Setup required"
                : (editingSetup ? "Connection setup"
                   : (selectedGroup ? "Proxy group"
                      : (openclash.online ? openclash.groups.length + " proxy groups" : "Offline")))
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: selectedGroup && !editingSetup ? "󰒍" : "󰇧"
              textFormat: Text.PlainText
              color: openclash.configured && openclash.online ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Text {
          visible: selectedGroup !== null && !root.editingSetup
          width: parent.width
          text: selectedGroup ? String(selectedGroup.name || "") + " · " + String(selectedGroup.now || "") : ""
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          visible: openclash.actionStatus !== "" || openclash.lastError !== ""
          width: parent.width
          text: openclash.actionStatus !== "" ? openclash.actionStatus : openclash.lastError
          textFormat: Text.PlainText
          color: openclash.lastError !== "" && openclash.actionStatus === "" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          ActionButton {
            visible: openclash.configured && !root.editingSetup && selectedGroup !== null
            label: "‹ Groups"
            onActivated: root.showGroups()
          }

          ActionButton {
            visible: root.editingSetup && openclash.configured
            label: "Cancel"
            onActivated: root.cancelSetup()
          }

          Item { Layout.fillWidth: true }

          ActionButton {
            visible: openclash.configured && !root.editingSetup
            label: openclash.refreshing ? "Refreshing…" : "Refresh"
            enabled: !openclash.refreshing
            onActivated: openclash.refresh()
          }

          ActionButton {
            visible: openclash.configured && !root.editingSetup
            label: "Setup"
            onActivated: root.showSetup()
          }

          ActionButton {
            visible: openclash.configured && !root.editingSetup
            label: root.dashboardLabel(openclash.dashboardUrl) + " ↗"
            onActivated: openclash.openDashboard()
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          visible: !openclash.configured || root.editingSetup
          width: parent.width
          spacing: Style.space(9)

          PanelSectionHeader {
            text: openclash.configured ? "EDIT CONNECTION" : "CONNECT TO OPENCLASH"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            text: "Controller URL"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          SafeTextField {
            id: controllerField
            width: parent.width
            placeholderText: "https://openclash.example.net"
            text: root.setupController
            inputActive: root.opened && (!openclash.configured || root.editingSetup)
            onEdited: function(value) { root.setupController = value }
            onPasteRequested: clipboardReader.paste(controllerField)
            onEscapeRequested: root.close()
          }

          Text {
            width: parent.width
            text: "Dashboard URL (optional)"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          SafeTextField {
            id: dashboardField
            width: parent.width
            placeholderText: "https://openclash.example.net/ui/"
            text: root.setupDashboard
            inputActive: root.opened && (!openclash.configured || root.editingSetup)
            onEdited: function(value) { root.setupDashboard = value }
            onPasteRequested: clipboardReader.paste(dashboardField)
            onEscapeRequested: root.close()
          }

          Text {
            width: parent.width
            text: "The button name is detected from known dashboard URLs; custom dashboards use the generic Dashboard label."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: openclash.configured ? "Controller secret (leave blank to keep current)" : "Controller secret"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          SafeTextField {
            id: secretField
            width: parent.width
            placeholderText: openclash.configured ? "Saved secret unchanged" : "Required"
            password: true
            maximumLength: 4096
            text: root.setupSecret
            inputActive: root.opened && (!openclash.configured || root.editingSetup)
            onEdited: function(value) { root.setupSecret = value }
            onPasteRequested: clipboardReader.paste(secretField)
            onEscapeRequested: root.close()
            onAccepted: root.submitSetup()
          }

          Text {
            width: parent.width
            text: "The controller is tested before anything is saved. The secret is sent to the helper over stdin and stored with owner-only permissions."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          ActionButton {
            width: parent.width
            label: openclash.configuring ? "Validating…" : (openclash.configured ? "Save and test" : "Connect and save")
            busy: openclash.configuring
            enabled: String(root.setupController).trim() !== ""
                     && (openclash.configured || String(root.setupSecret) !== "")
            onActivated: root.submitSetup()
          }
        }

        PanelSeparator {
          visible: openclash.configured && !root.editingSetup
          foreground: root.foreground
        }

        Column {
          visible: openclash.configured && !root.editingSetup
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "TRAFFIC MODE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            ActionButton {
              Layout.fillWidth: true
              label: "Rule"
              selected: openclash.mode === "rule"
              busy: openclash.switchingMode === "rule"
              onActivated: openclash.setMode("rule")
            }

            ActionButton {
              Layout.fillWidth: true
              label: "Global"
              selected: openclash.mode === "global"
              busy: openclash.switchingMode === "global"
              onActivated: openclash.setMode("global")
            }

            ActionButton {
              Layout.fillWidth: true
              label: "Direct"
              selected: openclash.mode === "direct"
              busy: openclash.switchingMode === "direct"
              onActivated: openclash.setMode("direct")
            }
          }
        }

        PanelSeparator {
          visible: openclash.configured && !root.editingSetup
          foreground: root.foreground
        }

        Column {
          visible: openclash.configured && !root.editingSetup && selectedGroup === null
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: openclash.groups
            ProxyRow {
              required property var modelData
              width: parent.width
              title: modelData.name
              subtitle: modelData.now
              subtitlePing: Number(modelData.nowDelay || 0)
              trailing: String((modelData.all || []).length)
              active: false
              busy: false
              onActivated: root.showGroup(modelData.name)
            }
          }
        }

        Column {
          visible: openclash.configured && !root.editingSetup && selectedGroup !== null
          width: parent.width
          spacing: Style.space(8)

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 1

              Text {
                text: "Lowest ping first"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                text: root.sortByPing ? "Sorted by measured latency" : "Using normal provider order"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            ToggleSwitch {
              checked: root.sortByPing
              foreground: root.foreground
              onToggled: {
                root.sortByPing = !root.sortByPing
                panelFlick.contentY = 0
              }
            }
          }

          SafeTextField {
            id: searchField
            width: parent.width
            placeholderText: "Search " + (selectedGroup ? selectedGroup.all.length : 0) + " reachable servers…"
            text: root.searchText
            maximumLength: 256
            inputActive: root.opened && openclash.configured && !root.editingSetup && root.selectedGroup !== null
            onEdited: function(value) { root.searchText = value }
            onPasteRequested: clipboardReader.paste(searchField)
            onEscapeRequested: root.close()
          }

          Text {
            visible: selectedGroup && root.searchText === "" && selectedGroup.all.length > 120
            width: parent.width
            text: "Showing the first 120 reachable servers. Search to find any server."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.visibleCandidates
            ProxyRow {
              required property var modelData
              width: parent.width
              title: String(modelData.name || "")
              subtitle: title === (root.selectedGroup ? root.selectedGroup.now : "") ? "Active" : ""
              ping: Number(modelData.delay || 0)
              trailing: title === (root.selectedGroup ? root.selectedGroup.now : "") ? "✓" : ""
              active: title === (root.selectedGroup ? root.selectedGroup.now : "")
              busy: openclash.switchingGroup === root.selectedGroupName && openclash.switchingServer === title
              onActivated: openclash.selectProxy(root.selectedGroupName, title)
            }
          }

          Text {
            visible: root.visibleCandidates.length === 0
            width: parent.width
            text: "No matching servers"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component ActionButton: Rectangle {
    id: actionButton
    property string label: ""
    property bool selected: false
    property bool busy: false
    signal activated()
    implicitWidth: actionText.implicitWidth + Style.space(18)
    implicitHeight: Style.space(30)
    radius: Style.cornerRadius
    color: selected ? Style.selectedFillFor(root.foreground, Commons.Color.accent)
                    : (actionMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent")
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)
    opacity: enabled ? 1.0 : 0.5

    Text {
      id: actionText
      anchors.centerIn: parent
      text: actionButton.busy ? "…" : actionButton.label
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: actionButton.enabled && !actionButton.busy && !openclash.busy
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (enabled) actionButton.activated()
    }
  }

  component ProxyRow: Rectangle {
    id: proxyRow
    property string title: ""
    property string subtitle: ""
    property string trailing: ""
    property int ping: 0
    property int subtitlePing: 0
    property bool active: false
    property bool busy: false
    signal activated()

    implicitHeight: Math.max(Style.space(46), rowContent.implicitHeight + Style.space(12))
    radius: Style.cornerRadius
    color: active ? Style.selectedFillFor(root.foreground, Commons.Color.accent)
                  : (rowMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent")

    RowLayout {
      id: rowContent
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        Text {
          Layout.fillWidth: true
          text: proxyRow.title
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        RowLayout {
          visible: proxyRow.subtitle !== "" || proxyRow.subtitlePing > 0
          Layout.fillWidth: true
          spacing: Style.space(5)

          Text {
            Layout.fillWidth: true
            text: proxyRow.subtitle
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            visible: proxyRow.subtitlePing > 0
            text: String(proxyRow.subtitlePing) + " ms"
            textFormat: Text.PlainText
            color: root.pingColor(proxyRow.subtitlePing)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Text {
        text: proxyRow.busy ? "…" : (proxyRow.ping > 0 ? String(proxyRow.ping) + " ms" : proxyRow.trailing)
        textFormat: Text.PlainText
        color: proxyRow.ping > 0 ? root.pingColor(proxyRow.ping)
                                 : (proxyRow.active ? root.foreground : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: !proxyRow.busy && !openclash.busy
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: proxyRow.activated()
    }
  }
}
