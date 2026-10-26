import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Claude API spend this credit cycle, from scripts/claude-cost (Anthropic Admin API).
// The bar shows a pace gauge: the fill is credit used, the tick is how far through the cycle we are.
BarWidget {
  id: root
  moduleName: "gig3m.claude-api-usage"

  property var report: ({})
  property string error: ""
  property bool pending: false
  property bool pendingForce: false

  readonly property real credit: Math.max(0, Number(setting("credit", 200)) || 0)
  readonly property int cycleStartDay: Math.max(1, Math.min(31, Number(setting("cycleStartDay", 1)) || 1))
  readonly property int refreshMinutes: Math.max(1, Number(setting("refreshMinutes", 5)) || 5)
  readonly property string barLabel: String(setting("barLabel", "none"))
  readonly property string keyEnv: String(setting("keyEnv", "ANTHROPIC_ADMIN_KEY"))
  readonly property string keyExec: String(setting("keyExec", ""))
  readonly property string script: localPath(Qt.resolvedUrl("scripts/claude-cost"))
  readonly property bool loaded: report.total !== undefined
  readonly property bool fetching: costProcess.running

  // Pace counts only complete UTC days, the same days the total covers.
  readonly property real total: Number(report.total || 0)
  readonly property int daysElapsed: Number(report.daysElapsed || 0)
  readonly property int cycleDays: Number(report.cycleDays || 0)
  readonly property real usedFraction: credit > 0 ? total / credit : 0
  readonly property real elapsedFraction: cycleDays > 0 ? daysElapsed / cycleDays : 0
  readonly property real projected: daysElapsed > 0 ? total / daysElapsed * cycleDays : 0
  readonly property bool overCredit: credit > 0 && total > credit
  readonly property bool burningHot: credit > 0 && projected > credit
  readonly property color paceColor: burningHot || overCredit ? Color.urgent : Color.accent

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (e) { return value }
  }

  function money(value) {
    return "$" + Number(value || 0).toFixed(2)
  }

  function percent(part, whole) {
    return whole > 0 ? Math.round(part * 100 / whole) + "%" : "–"
  }

  function labelText() {
    if (!loaded) return "…"
    if (barLabel === "percent") return percent(total, credit)
    if (barLabel === "projected") return "→" + money(projected)
    if (barLabel === "none") return ""
    return money(total)
  }

  function openConsole() {
    if (root.bar) root.bar.run("xdg-open https://platform.claude.com/cost")
  }

  // A refresh asked for mid-fetch (settings arriving after creation, a click)
  // runs once the current fetch exits, so it isn't lost.
  function refresh(force) {
    if (costProcess.running) {
      pending = true
      pendingForce = pendingForce || force === true
      return
    }
    if (error === "claude-cost timed out") error = ""
    costProcess.command = ["timeout", "90", script, "--cycle-day", String(cycleStartDay), "--key-env", keyEnv]
      .concat(keyExec !== "" ? ["--key-exec", keyExec] : [])
      .concat(force === true ? ["--force"] : [])
    costProcess.running = true
  }

  function applyReport(raw) {
    var text = String(raw || "").trim()
    if (text === "") {
      if (error !== "claude-cost timed out") error = "No output from claude-cost"
      return
    }
    try {
      var next = JSON.parse(text)
      if (next.error) {
        error = next.error
        return
      }
      if (typeof next.total !== "number" || !isFinite(next.total)) throw new Error("bad total")
      report = next
      error = ""
    } catch (e) {
      error = "Could not read Claude API cost"
    }
  }

  function tooltip() {
    if (!loaded) return error !== "" ? "Claude API: " + error : "Claude API: loading…"
    return "Claude API: " + money(total) + " of " + money(credit) + " (" + percent(total, credit) + ")"
      + " · day " + Math.min(cycleDays, daysElapsed + 1) + " of " + cycleDays
      + "\nProjected " + money(projected) + " by " + report.cycleEnd + (burningHot ? " — over credit" : "")
      + (error !== "" ? "\nLast refresh failed: " + error : "")
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onCompleted: Qt.callLater(refresh)
  onCycleStartDayChanged: refresh()
  onKeyEnvChanged: refresh()
  onKeyExecChanged: refresh()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fixedWidth: root.vertical ? -1 : content.implicitWidth + Style.spaceReal(14)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    horizontalMargin: 0
    verticalPadding: 0
    labelVisible: false
    hasVisualContent: true
    active: root.opened
    dimmed: !root.loaded || root.error !== ""
    tooltipText: root.opened ? "" : root.tooltip()
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
      else if (mouseButton === Qt.RightButton) root.refresh(true)
      else if (mouseButton === Qt.MiddleButton) root.openConsole()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.spaceReal(5)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰚩"
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }

      // Pace gauge: fill = credit used, ghost fill = projection, tick = cycle elapsed.
      Item {
        id: gauge
        visible: !root.vertical
        anchors.verticalCenter: parent.verticalCenter
        width: Style.spaceReal(34)
        height: Style.spaceReal(8)

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.14)
        }

        Rectangle {
          height: parent.height
          radius: height / 2
          width: Math.min(1, root.credit > 0 ? root.projected / root.credit : 0) * parent.width
          color: root.paceColor
          opacity: 0.28
          Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }

        Rectangle {
          height: parent.height
          radius: height / 2
          width: Math.max(root.usedFraction > 0 ? height : 0, Math.min(1, root.usedFraction) * parent.width)
          color: root.paceColor
          Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 160 } }
        }

        Rectangle {
          visible: root.loaded
          x: Math.min(1, root.elapsedFraction) * parent.width - width / 2
          y: -Style.spaceReal(2)
          width: Math.max(1, Style.spaceReal(1.5))
          height: parent.height + Style.spaceReal(4)
          color: button.foreground
        }
      }

      Text {
        visible: text !== "" && !root.vertical
        anchors.verticalCenter: parent.verticalCenter
        text: root.labelText()
        color: root.burningHot || root.overCredit ? Color.urgent : button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }
    }
  }

  Process {
    id: costProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyReport(text)
    }
    onExited: function(exitCode) {
      if (exitCode === 124) root.error = "claude-cost timed out"
      if (root.pending) {
        var force = root.pendingForce
        root.pending = false
        root.pendingForce = false
        Qt.callLater(function() { root.refresh(force) })
      }
    }
  }

  Timer {
    interval: root.refreshMinutes * 60000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }
}
