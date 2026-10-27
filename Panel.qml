import QtQuick
import qs.Commons
import qs.Ui

// Flyout for gig3m.claude-api-usage: pace, daily trend, today by hour, and breakdowns.
// All data comes from the host BarWidget's report (scripts/report.jq).
Panel {
  id: root
  moduleName: "gig3m.claude-api-usage"
  ipcTarget: "gig3m.claude-api-usage"
  manageIpc: true

  property var anchorItem: null
  property var hostWidget: null

  readonly property var barIdentity: hostWidget || root
  readonly property var report: hostWidget ? hostWidget.report : ({})
  readonly property bool loaded: hostWidget ? hostWidget.loaded : false
  readonly property real credit: hostWidget ? hostWidget.credit : 0
  readonly property real total: hostWidget ? hostWidget.total : 0
  readonly property int daysElapsed: hostWidget ? hostWidget.daysElapsed : 0
  readonly property int cycleDays: hostWidget ? hostWidget.cycleDays : 0
  readonly property real projected: hostWidget ? hostWidget.projected : 0
  readonly property bool burningHot: hostWidget ? (hostWidget.burningHot || hostWidget.overCredit) : false
  readonly property int daysLeft: Math.max(0, cycleDays - daysElapsed)
  // Today is day daysElapsed + 1; pace maths uses only the complete days.
  readonly property int dayNumber: Math.min(cycleDays, daysElapsed + 1)
  readonly property real burnPerDay: daysElapsed > 0 ? total / daysElapsed : 0
  readonly property real budgetPerDay: cycleDays > 0 ? credit / cycleDays : 0
  readonly property real today: report.today ? Number(report.today.cost || 0) : 0
  readonly property var previous: report.previous || ({})

  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property color dim: Qt.rgba(barForeground.r, barForeground.g, barForeground.b, 0.55)
  readonly property color faint: Qt.rgba(barForeground.r, barForeground.g, barForeground.b, 0.14)
  readonly property color paceColor: burningHot ? Color.urgent : Color.accent
  // The first model takes the theme accent; the rest are picked to stay apart from common accents.
  readonly property var modelColors: [Color.accent, "#e0a030", "#f05a9d", "#9b7cf2"]

  function money(value) { return hostWidget ? hostWidget.money(value) : "$0.00" }
  function percent(part, whole) { return hostWidget ? hostWidget.percent(part, whole) : "–" }

  function shortMoney(value) {
    var v = Number(value || 0)
    return v >= 100 ? "$" + Math.round(v) : "$" + v.toFixed(2)
  }

  function compact(n) {
    n = Number(n || 0)
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
    return String(Math.round(n))
  }

  // claude-sonnet-5-5 → Sonnet 5.5, claude-haiku-4-5-20251001 → Haiku 4.5
  function modelName(id) {
    var m = String(id || "").match(/^claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?$/)
    if (!m) return String(id || "Other")
    return m[1].charAt(0).toUpperCase() + m[1].slice(1) + " " + m[2] + (m[3] !== undefined ? "." + m[3] : "")
  }

  function modelColor(id) {
    var top = report.topModels || []
    var i = top.indexOf(id)
    return i >= 0 ? modelColors[i] : dim
  }

  function shortDate(iso) {
    var d = new Date(String(iso) + "T00:00:00Z")
    if (isNaN(d.getTime())) return "—"
    return ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getUTCMonth()]
      + " " + d.getUTCDate()
  }

  function vsPrevious() {
    var before = Number(previous.toDate || 0)
    if (before <= 0) return "—"
    var change = Math.round((total - before) * 100 / before)
    return (change > 0 ? "+" : "") + change + "%"
  }

  function updatedText() {
    if (!report.updated) return ""
    var d = new Date(report.updated * 1000)
    return "Updated " + String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // A label · value row with a proportional bar underneath.
  component BreakdownRow: Item {
    id: row
    property string label: ""
    property string value: ""
    property string note: ""
    property real fraction: 0
    property color barColor: Color.accent
    width: parent ? parent.width : 0
    height: Style.space(30)

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: valueText.left
      anchors.rightMargin: Style.space(8)
      anchors.top: parent.top
      text: row.label + (row.note !== "" ? "  " + row.note : "")
      color: root.barForeground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
    Text {
      id: valueText
      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.top: parent.top
      text: row.value
      color: root.barForeground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(4)
      height: Style.space(4)
      radius: height / 2
      color: root.faint
      Rectangle {
        height: parent.height
        radius: height / 2
        width: Math.max(row.fraction > 0 ? height : 0, Math.min(1, row.fraction) * parent.width)
        color: row.barColor
      }
    }
  }

  component SectionTitle: Text {
    textFormat: Text.PlainText
    color: Color.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0.6
  }

  component Stat: Column {
    property string label: ""
    property string value: ""
    property color valueColor: root.barForeground
    width: (parent.width - parent.spacing * 2) / 3
    spacing: Style.space(2)
    Text {
      textFormat: Text.PlainText
      text: parent.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      textFormat: Text.PlainText
      text: parent.value
      color: parent.valueColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }
  }

  component Divider: Rectangle {
    width: parent ? parent.width : 0
    height: Math.max(1, Style.space(1))
    color: root.barForeground
    opacity: 0.12
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (!root.hostWidget) return
        if (text === "r" || text === "R") root.hostWidget.refresh(true)
        else if (text === "o" || text === "O") root.hostWidget.openConsole()
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(10)

        // Header
        Item {
          width: parent.width
          height: Style.space(26)
          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "CLAUDE API"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.loaded ? root.money(root.total) + " / " + root.shortMoney(root.credit) : "…"
            color: root.burningHot ? Color.urgent : root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.loaded
          text: root.shortDate(root.report.cycleStart) + " → " + root.shortDate(root.report.cycleEnd)
            + "  ·  day " + root.dayNumber + " of " + root.cycleDays
            + "  ·  " + root.daysLeft + " days left"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Pace: credit used (solid), projection (ghost), cycle elapsed (tick)
        Item {
          width: parent.width
          height: Style.space(16)
          visible: root.loaded

          Rectangle {
            anchors.fill: parent
            radius: Style.space(4)
            color: root.faint
          }
          Rectangle {
            height: parent.height
            radius: Style.space(4)
            width: Math.min(1, root.credit > 0 ? root.projected / root.credit : 0) * parent.width
            color: root.paceColor
            opacity: 0.25
          }
          Rectangle {
            height: parent.height
            radius: Style.space(4)
            width: Math.min(1, root.credit > 0 ? root.total / root.credit : 0) * parent.width
            color: root.paceColor
          }
          Rectangle {
            x: Math.min(1, root.cycleDays > 0 ? root.daysElapsed / root.cycleDays : 0) * parent.width - width / 2
            y: -Style.space(3)
            width: Math.max(2, Style.space(2))
            height: parent.height + Style.space(6)
            color: root.barForeground
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: root.loaded
          wrapMode: Text.WordWrap
          text: root.percent(root.total, root.credit) + " of credit used, "
            + root.percent(root.daysElapsed, root.cycleDays) + " of the cycle gone.  On pace for "
            + root.money(root.projected) + " (" + root.percent(root.projected, root.credit) + ")"
            + (root.burningHot ? " — over the credit." : ".")
          color: root.burningHot ? Color.urgent : root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: root.loaded
          Stat { label: "Burn / day"; value: root.money(root.burnPerDay); valueColor: root.burnPerDay > root.budgetPerDay ? Color.urgent : root.barForeground }
          Stat { label: "Budget / day"; value: root.money(root.budgetPerDay) }
          Stat { label: "Left / day"; value: root.daysLeft > 0 ? root.money(Math.max(0, root.credit - root.total) / root.daysLeft) : "—" }
        }
        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: root.loaded
          Stat {
            label: "Today (est.)"
            value: root.report.today && root.report.today.unpriced
              ? (root.today > 0 ? "≥" + root.money(root.today) : "n/a")
              : "≈" + root.money(root.today)
            valueColor: root.today > root.budgetPerDay ? Color.urgent : root.barForeground
          }
          Stat { label: "Last cycle, same day"; value: root.money(root.previous.toDate); }
          Stat { label: "Change"; value: root.vsPrevious() }
        }

        Divider {}

        // Daily spend for the whole cycle, stacked by top model, with the budget line.
        Item {
          width: parent.width
          height: Style.space(18)
          SectionTitle { anchors.left: parent.left; text: "DAILY SPEND" }
          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            text: "- - budget " + root.money(root.budgetPerDay) + "/day"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Canvas {
          id: dailyChart
          width: parent.width
          height: Style.space(110)
          property var days: root.report.daily || []
          property real todayCost: root.today
          property real budget: root.budgetPerDay
          property int slots: Math.max(1, root.cycleDays)
          property var colors: root.modelColors
          property color other: root.dim
          property color grid: root.faint
          property color line: root.barForeground
          property color accent: Color.accent
          onDaysChanged: requestPaint()
          onTodayCostChanged: requestPaint()
          onBudgetChanged: requestPaint()
          onSlotsChanged: requestPaint()
          onWidthChanged: requestPaint()
          onGridChanged: requestPaint()
          onColorsChanged: requestPaint()
          onOtherChanged: requestPaint()
          onLineChanged: requestPaint()
          onAccentChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var maxValue = Math.max(budget, todayCost)
            for (var i = 0; i < days.length; i++) maxValue = Math.max(maxValue, days[i].cost)
            maxValue = maxValue * 1.12 || 1
            var step = width / slots
            var gap = Math.max(1, step * 0.18)

            for (var s = 0; s < slots; s++) {
              ctx.fillStyle = grid
              ctx.fillRect(s * step + gap / 2, height - 1, step - gap, 1)
            }

            for (var d = 0; d < days.length; d++) {
              var x = d * step + gap / 2
              var y = height
              var parts = days[d].byModel || []
              var rest = days[d].cost
              for (var p = 0; p < parts.length; p++) {
                var h = parts[p] / maxValue * height
                ctx.fillStyle = colors[p % colors.length]
                ctx.fillRect(x, y - h, step - gap, h)
                y -= h
                rest -= parts[p]
              }
              if (rest > 0.0001) {
                var hr = rest / maxValue * height
                ctx.fillStyle = other
                ctx.fillRect(x, y - hr, step - gap, hr)
              }
            }

            // Today's estimate, outlined: it isn't billed yet.
            if (days.length < slots && todayCost > 0) {
              var tx = days.length * step + gap / 2
              var th = todayCost / maxValue * height
              ctx.strokeStyle = accent
              ctx.lineWidth = 1
              ctx.setLineDash([2, 2])
              ctx.strokeRect(tx + 0.5, height - th + 0.5, step - gap - 1, th - 1)
              ctx.setLineDash([])
            }

            if (budget > 0) {
              var by = height - budget / maxValue * height
              ctx.strokeStyle = line
              ctx.globalAlpha = 0.6
              ctx.lineWidth = 1
              ctx.setLineDash([4, 3])
              ctx.beginPath()
              ctx.moveTo(0, by)
              ctx.lineTo(width, by)
              ctx.stroke()
              ctx.setLineDash([])
              ctx.globalAlpha = 1
            }
          }
        }

        Item {
          width: parent.width
          height: Style.space(14)
          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            text: root.shortDate(root.report.cycleStart)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: "dashed bar = today, estimated"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            text: root.shortDate(root.report.cycleEnd)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(12)
          Repeater {
            model: root.report.topModels || []
            delegate: Row {
              required property var modelData
              required property int index
              spacing: Style.space(5)
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(8)
                height: width
                radius: width / 2
                color: root.modelColors[index % root.modelColors.length]
              }
              Text {
                textFormat: Text.PlainText
                text: root.modelName(modelData)
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Divider {}

        // Today by hour (UTC), estimated from usage at this cycle's rates.
        Item {
          width: parent.width
          height: Style.space(18)
          SectionTitle {
            anchors.left: parent.left
            text: "TODAY BY HOUR (UTC, EST.)"
              + (root.report.today && root.report.today.unpriced ? " · SOME MODELS UNPRICED" : "")
          }
          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            text: root.report.today ? root.compact(root.report.today.tokens) + " tokens" : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Canvas {
          width: parent.width
          height: Style.space(48)
          property var hours: root.report.today ? root.report.today.hours || [] : []
          property color fill: Color.accent
          property color grid: root.faint
          onHoursChanged: requestPaint()
          onWidthChanged: requestPaint()
          onFillChanged: requestPaint()
          onGridChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var maxValue = 0
            for (var i = 0; i < hours.length; i++) maxValue = Math.max(maxValue, hours[i].cost)
            var step = width / 24
            var gap = Math.max(1, step * 0.2)
            for (var h = 0; h < 24; h++) {
              ctx.fillStyle = grid
              ctx.fillRect(h * step + gap / 2, height - 1, step - gap, 1)
            }
            if (maxValue <= 0) return
            ctx.fillStyle = fill
            for (var j = 0; j < hours.length; j++) {
              var bh = hours[j].cost / maxValue * (height - 2)
              ctx.fillRect(hours[j].h * step + gap / 2, height - bh, step - gap, bh)
            }
          }
        }

        Item {
          width: parent.width
          height: Style.space(14)
          Repeater {
            model: [0, 6, 12, 18]
            delegate: Text {
              textFormat: Text.PlainText
              required property int modelData
              x: modelData / 24 * parent.width
              text: String(modelData).padStart(2, "0")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Divider {}

        SectionTitle { text: "BY MODEL" }
        Column {
          width: parent.width
          Repeater {
            model: root.report.models || []
            delegate: BreakdownRow {
              required property var modelData
              label: root.modelName(modelData.model)
              value: root.money(modelData.cost)
              note: root.percent(modelData.cost, root.total)
              fraction: root.total > 0 ? modelData.cost / root.total : 0
              barColor: root.modelColor(modelData.model)
            }
          }
        }

        SectionTitle { text: "BY API KEY (EST.)" }
        Column {
          width: parent.width
          Repeater {
            model: root.report.keys || []
            delegate: BreakdownRow {
              required property var modelData
              label: modelData.name
              value: root.money(modelData.cost)
              note: root.compact(modelData.tokens) + " tok" + (modelData.unpriced ? " · partial" : "")
              fraction: root.total > 0 ? modelData.cost / root.total : 0
            }
          }
        }

        SectionTitle { text: "BY TOKEN TYPE" }
        Column {
          width: parent.width
          Repeater {
            model: root.report.types || []
            delegate: BreakdownRow {
              required property var modelData
              label: modelData.type
              value: root.money(modelData.cost)
              note: root.percent(modelData.cost, root.total)
              fraction: root.total > 0 ? modelData.cost / root.total : 0
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: root.report.tokens !== undefined
          Stat {
            label: "Cache hit rate"
            value: root.report.tokens && root.report.tokens.cacheHitRate !== null
              ? Math.round(root.report.tokens.cacheHitRate * 100) + "%" : "—"
          }
          Stat { label: "Output tokens"; value: root.report.tokens ? root.compact(root.report.tokens.output) : "—" }
          Stat { label: "Last cycle total"; value: root.money(root.previous.total) }
        }

        Divider {}

        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.WordWrap
          text: (root.hostWidget && root.hostWidget.error !== "" ? root.hostWidget.error + "  ·  " : "")
            + (root.hostWidget && root.hostWidget.fetching ? "Refreshing…" : root.updatedText())
            + "  ·  billed through " + root.shortDate(root.report.through)
            + "  ·  R refresh · O Console"
          color: root.hostWidget && root.hostWidget.error !== "" ? Color.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
