import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})
  property var groups: []
  property bool configured: false
  property bool configuring: false
  property bool online: false
  property bool refreshing: false
  property string apiBase: ""
  property string dashboardUrl: ""
  property string mode: "rule"
  property string lastError: ""
  property string actionStatus: ""
  property string pendingAction: ""
  property string switchingGroup: ""
  property string switchingServer: ""
  property string switchingMode: ""
  property int setupRevision: 0
  property string _setupPayload: ""

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/cbayschm.openclash"
  readonly property string helperPath: pluginDir + "/openclash_api.py"
  readonly property string configDir: Quickshell.env("HOME") + "/.config/omarchy/openclash"
  readonly property string configPath: configDir + "/config.json"
  readonly property string secretPath: configDir + "/secret"
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 10, 3600)
  readonly property bool busy: setupProcess.running || configureProcess.running || statusProcess.running || actionProcess.running

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function elide(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 180 ? value.substring(0, 177) + "…" : value
  }

  function parseResult(raw) {
    try { return JSON.parse(String(raw || "")) }
    catch (error) { return { ok: false, error: "OpenClash returned invalid data" } }
  }

  function loadSetup() {
    if (setupProcess.running || configureProcess.running) return
    setupProcess.command = ["python3", helperPath, "setup-state", configPath, secretPath]
    setupProcess.running = true
  }

  function configure(controllerUrl, dashboard, secret) {
    if (configureProcess.running) return
    lastError = ""
    configuring = true
    actionStatus = "Validating OpenClash…"
    _setupPayload = JSON.stringify({
      apiBase: String(controllerUrl || "").trim(),
      dashboardUrl: String(dashboard || "").trim(),
      secret: String(secret || "")
    })
    configureProcess.command = ["python3", helperPath, "configure", configPath, secretPath]
    configureProcess.running = true
  }

  function refresh() {
    if (!configured || statusProcess.running) return
    refreshing = true
    statusProcess.command = ["python3", helperPath, "status", configPath, secretPath]
    statusProcess.running = true
  }

  function selectProxy(group, server) {
    if (!group || !server || actionProcess.running) return
    lastError = ""
    actionStatus = "Switching to " + server + "…"
    pendingAction = "proxy"
    switchingGroup = String(group)
    switchingServer = String(server)
    actionProcess.command = ["python3", helperPath, "set", configPath, secretPath, switchingGroup, switchingServer]
    actionProcess.running = true
  }

  function setMode(nextMode) {
    var requested = String(nextMode || "").toLowerCase()
    if (["rule", "global", "direct"].indexOf(requested) < 0 || requested === mode || actionProcess.running) return
    lastError = ""
    pendingAction = "mode"
    switchingMode = requested
    actionStatus = "Changing mode to " + requested.charAt(0).toUpperCase() + requested.slice(1) + "…"
    actionProcess.command = ["python3", helperPath, "mode", configPath, secretPath, requested]
    actionProcess.running = true
  }

  function openDashboard() { if (configured && dashboardUrl !== "") Qt.openUrlExternally(dashboardUrl) }

  Component.onCompleted: loadSetup()

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: root.configured
    onTriggered: root.refresh()
  }

  Process {
    id: setupProcess
    running: false
    command: []
    stdout: StdioCollector { id: setupOut; waitForEnd: true }
    stderr: StdioCollector { id: setupErr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = root.parseResult(setupOut.text)
      if (exitCode === 0 && result.ok === true) {
        root.configured = result.configured === true
        root.apiBase = String(result.apiBase || "")
        root.dashboardUrl = String(result.dashboardUrl || "")
        if (root.configured) root.refresh()
      } else {
        root.configured = false
        root.lastError = root.elide(result.error || setupErr.text || "Could not read OpenClash setup")
      }
    }
  }

  Process {
    id: configureProcess
    running: false
    command: []
    stdinEnabled: true
    stdout: StdioCollector { id: configureOut; waitForEnd: true }
    stderr: StdioCollector { id: configureErr; waitForEnd: true }
    onStarted: {
      write(root._setupPayload + "\n")
      root._setupPayload = ""
    }
    onExited: function(exitCode) {
      root.configuring = false
      var result = root.parseResult(configureOut.text)
      if (exitCode === 0 && result.ok === true) {
        root.configured = true
        root.apiBase = String(result.apiBase || "")
        root.dashboardUrl = String(result.dashboardUrl || "")
        root.lastError = ""
        root.actionStatus = "Setup complete"
        root.setupRevision += 1
        statusClear.restart()
        root.refresh()
      } else {
        root.actionStatus = ""
        root.lastError = root.elide(result.error || configureErr.text || "Could not save OpenClash setup")
      }
    }
  }

  Timer {
    id: delayedRefresh
    interval: 500
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: statusClear
    interval: 2400
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.refreshing = false
      var result = root.parseResult(statusOut.text)
      if (exitCode === 0 && result.ok === true) {
        root.groups = result.groups || []
        root.mode = String(result.mode || "rule").toLowerCase()
        root.online = true
        root.lastError = ""
      } else {
        root.online = false
        root.lastError = root.elide(result.error || statusErr.text || "Cannot reach OpenClash")
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = root.parseResult(actionOut.text)
      if (exitCode === 0 && result.ok === true) {
        if (root.pendingAction === "mode") {
          root.mode = String(result.mode || root.switchingMode).toLowerCase()
          root.actionStatus = "Mode: " + root.mode.charAt(0).toUpperCase() + root.mode.slice(1)
        } else {
          root.actionStatus = "Now using " + root.switchingServer
        }
        root.lastError = ""
        statusClear.restart()
        delayedRefresh.restart()
      } else {
        root.actionStatus = ""
        root.lastError = root.elide(result.error || actionErr.text || "Could not switch proxy")
      }
      root.switchingGroup = ""
      root.switchingServer = ""
      root.switchingMode = ""
      root.pendingAction = ""
    }
  }
}
