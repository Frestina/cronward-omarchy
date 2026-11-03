import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "CronwardView.js" as View

// Bar widget for cronward (github.com/Frestina/cronward). cronward decides
// whether each job passed, failed or didn't run; this widget only shows what
// `cronward status --json` says, or on a viewer `cronward status --host HOST
// --json`, sorted by CronwardView.js. It reads no cronward files, holds no
// token, and makes no network or ssh calls of its own: every change is a
// cronward command, run on the main machine through `cronward --on HOST`.
//
// left = popup · middle = check now · right = `cronward status` in a terminal.
// A job's row opens its run on github.com; a job that failed or didn't run can
// be handed to the agent to explain. The footer edits the config, opens the
// token page, and sets up a new job with the agent.
Panel {
  id: root
  moduleName: "io.github.frestina.cronward"
  ipcTarget: "io.github.frestina.cronward"
  // Own the target so it can carry refresh and check alongside open/close/toggle.
  manageIpc: false

  // The main machine, as typed after ssh; blank when this is the main machine.
  readonly property string host: String(setting("host", "") || "").trim()
  readonly property string cronward: String(setting("cronward", "cronward") || "").trim() || "cronward"
  readonly property int refreshSec: Math.min(3600, Math.max(30, Number(setting("refreshSec", 60)) || 60))
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")

  // What CronwardView.model() made of the last status run.
  property var view: null
  property bool loading: false
  property bool checking: false
  property var checkedAt: null
  // Per run: a command that fails to start only flips running, with no exited
  // or stream signals, so the finish handlers key off running and these.
  property bool procStarted: false
  property int procExitCode: 0
  property bool checkStarted: false
  property bool refreshAgain: false

  readonly property string level: view ? view.level : "quiet"
  readonly property int count: view ? view.count : 0
  readonly property var hostProblems: view ? view.problems.filter(function(p) { return p.scope === "host" }) : []
  readonly property bool allPassed: !!view && view.kind === "status" && view.level === "quiet"

  // Warnings in the theme's orange (or yellow), which the shell's palette
  // lacks; its accent can be any hue, red included.
  property color warnColor: Color.accent

  readonly property string caption: {
    if (checking) return "Checking…"
    if (!view) return loading ? "Reading status…" : ""
    if (view.header) return view.header
    return view.kind === "missing" ? "cronward not found"
      : view.kind === "notsetup" ? "not set up"
      : "status failed"
  }

  function refresh() {
    if (proc.running) {
      refreshAgain = true
      return
    }
    loading = true
    procStarted = false
    procExitCode = 0
    proc.command = View.processArgv(root.cronward, View.statusArgs(root.host))
    proc.running = true
  }

  function finish() {
    loading = false
    root.view = View.model({ started: procStarted, exitCode: procExitCode,
                             stdout: out.text, stderr: errOut.text }, root.host, Date.now())
    root.checkedAt = new Date()
    if (refreshAgain) {
      refreshAgain = false
      Qt.callLater(root.refresh)
    }
  }

  // Every monitor's copy reads the status again; each run is cheap and local.
  function refreshAll() {
    var items = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : []
    if (items.indexOf(root) < 0) items = items.concat([root])
    for (var i = 0; i < items.length; i++)
      if (items[i] && typeof items[i].refresh === "function") items[i].refresh()
  }

  // On a viewer: fetch the main machine's status now (`cronward watch HOST`),
  // then read it. On the main machine a fresh status is the check.
  function checkNow() {
    var args = View.checkArgs(root.host)
    if (!args) return root.refreshAll()
    if (checkProc.running) return
    checking = true
    checkStarted = false
    checkProc.command = View.processArgv(root.cronward, args)
    checkProc.running = true
  }

  function run(line) {
    if (!root.bar || !line) return
    root.close()
    root.bar.run(line)
  }

  function inTerminal(args) {
    run(View.terminal(View.shellLine(root.cronward, args)))
  }

  function openStatus() {
    inTerminal(root.host ? ["status", "--host", root.host] : ["status"])
  }

  function openRun(url) { run(View.open(url)) }

  function setUp() { run(View.agent(View.setupPrompt(root.host, root.pluginDir))) }

  function explain(row) { run(View.agent(View.explainPrompt(row, root.host, root.pluginDir))) }

  // Muted text as see-through bar foreground, so it recedes on light and dark
  // themes alike.
  function dim(alpha) {
    return Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, alpha)
  }

  function levelColor(level) {
    if (level === "bad") return Color.urgent
    if (level === "warn") return root.warnColor
    if (level === "ok") return root.barForeground
    return root.dim(0.45)
  }

  // The first of orange, yellow and ANSI yellow that colors.toml has.
  function loadWarnColor(raw) {
    var found = {}
    String(raw || "").split("\n").forEach(function(line) {
      var match = line.match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (match) found[match[1]] = match[2]
    })
    root.warnColor = found.orange || found.yellow || found.color3 || Color.accent
  }

  onOpenedChanged: if (opened) refresh()
  onHostChanged: refresh()
  onCronwardChanged: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refreshAll() }
    function check(): void { root.checkNow() }
  }

  // Both streams finish and exited fires before running drops, so finish()
  // sees this run's complete output.
  Process {
    id: proc
    onStarted: root.procStarted = true
    onExited: function(exitCode) { root.procExitCode = exitCode }
    onRunningChanged: if (!running) root.finish()
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector { id: errOut; waitForEnd: true }
  }

  // `cronward watch HOST`: its notices are cronward's own, from the viewer's
  // record, so a check gives no notice the hourly timer would not.
  Process {
    id: checkProc
    onStarted: root.checkStarted = true
    onRunningChanged: if (!running) { root.checking = false; root.refreshAll() }
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  FileView {
    id: themeColors
    path: Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: root.loadWarnColor(text())
    onLoadFailed: root.loadWarnColor("")
  }

  // A theme switch reaches the shell's palette over IPC, without a file
  // change to watch; read the new theme when the palette changes.
  Connections {
    target: Color
    function onAccentChanged() { themeColors.reload() }
    function onUrgentChanged() { themeColors.reload() }
    function onBackgroundChanged() { themeColors.reload() }
  }

  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // A count of what needs attention; a small mark while a run is going.
    text: vertical ? "󰃰"
      : "󰃰" + (root.count > 0 ? " " + root.count : root.view && root.view.running ? " •" : "")
    slotSize: Style.bar.iconSlot * (!vertical && (root.count > 0 || (root.view && root.view.running)) ? 1.6 : 1)
    active: root.level !== "quiet"
    activeColor: root.level === "bad" ? Color.urgent : root.warnColor
    // Quiet only when cronward said every job passed and the main machine ticks.
    dimmed: root.allPassed && !(root.view && root.view.running)
    tooltipText: root.opened ? "" : (root.view ? root.view.tooltip : "cronward")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openStatus()
      else if (b === Qt.MiddleButton) root.checkNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r") root.checkNow() }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // ---------- Hero: icon · title and the main machine · actions ----------
        RowLayout {
          width: parent.width
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            text: "󰃰"
            color: root.level === "quiet" ? root.barForeground : root.levelColor(root.level)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }

          Column {
            Layout.fillWidth: true
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "cronward"
              color: root.barForeground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.caption.toUpperCase()
              color: root.dim(0.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          PanelActionButton {
            iconText: "󰑐"
            tooltipText: root.host ? "Check now: fetch the status from " + root.host + " (r)" : "Check now (r)"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            enabled: !root.checking
            onClicked: root.checkNow()
          }

          PanelActionButton {
            iconText: "󰆍"
            tooltipText: "cronward status in a terminal"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            onClicked: root.openStatus()
          }
        }

        // ---------- Not found, not set up, no jobs, or an error ----------
        Text {
          visible: !!root.view && root.view.message !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.view ? root.view.message : ""
          wrapMode: Text.Wrap
          color: root.view && root.view.kind === "error" ? Color.urgent
            : root.view && root.view.kind === "nojobs" ? root.dim(0.7) : root.warnColor
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // ---------- The main machine: out of reach, stopped, a failed tick ----------
        Repeater {
          model: root.hostProblems.concat(root.view ? root.view.notes : [])

          delegate: Text {
            required property var modelData
            width: content.width
            textFormat: Text.PlainText
            text: "• " + modelData.text
            wrapMode: Text.Wrap
            color: root.levelColor(modelData.level)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---------- Tokens: none stored, or expiring ----------
        Repeater {
          model: root.view ? root.view.accounts : []

          delegate: RowLayout {
            id: accountRow
            required property var modelData
            width: content.width
            spacing: Style.space(4)

            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: "• " + accountRow.modelData.text
              wrapMode: Text.Wrap
              color: root.warnColor
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            // Typed in the terminal, on the main machine; the widget never sees it.
            PanelActionButton {
              iconText: "󰌆"
              tooltipText: "Store a new token for " + accountRow.modelData.name
                + (root.host ? " on " + root.host : "") + ", in a terminal"
              foreground: root.barForeground
              fontFamily: root.bar.fontFamily
              onClicked: root.inTerminal(View.onMain(root.host, ["token", "set", accountRow.modelData.name]))
            }
          }
        }

        PanelSeparator {
          visible: !!root.view && root.view.rows.length > 0
          foreground: root.barForeground
        }

        // ---------- One block per job ----------
        Repeater {
          model: root.view ? root.view.rows : []

          delegate: Rectangle {
            id: jobRow
            required property var modelData
            readonly property bool linked: modelData.open !== ""

            width: content.width
            implicitHeight: jobColumn.implicitHeight + Style.space(10)
            radius: Style.cornerRadius
            color: rowMouse.containsMouse && linked ? root.dim(0.06) : "transparent"

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: jobRow.linked ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: if (jobRow.linked) root.openRun(jobRow.modelData.open)
            }

            Column {
              id: jobColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              spacing: Style.space(2)

              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: jobRow.modelData.word
                  color: root.levelColor(jobRow.modelData.level)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: jobRow.modelData.level === "bad" || jobRow.modelData.level === "warn"
                }

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: jobRow.modelData.name
                  color: root.barForeground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  text: jobRow.modelData.next
                  color: root.dim(0.6)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }

                PanelActionButton {
                  visible: jobRow.modelData.ask
                  iconText: "󰚩"
                  tooltipText: "Ask your agent why " + jobRow.modelData.name + " "
                    + (jobRow.modelData.kind === "failed" ? "failed" : "didn't run")
                  size: Style.space(18)
                  fontSize: Style.font.caption
                  foreground: root.barForeground
                  fontFamily: root.bar.fontFamily
                  onClicked: root.explain(jobRow.modelData)
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: jobRow.modelData.where + (jobRow.modelData.ran ? " · " + jobRow.modelData.ran : "")
                color: root.dim(0.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Text {
                visible: jobRow.modelData.reason !== ""
                width: parent.width
                textFormat: Text.PlainText
                text: jobRow.modelData.reason
                wrapMode: Text.Wrap
                color: root.levelColor(jobRow.modelData.level)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                visible: jobRow.modelData.running !== ""
                width: parent.width
                textFormat: Text.PlainText
                text: "󰐊 " + jobRow.modelData.running
                color: root.barForeground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Text {
          visible: !!root.view && root.view.rows.some(function(r) { return r.open !== "" })
          width: parent.width
          textFormat: Text.PlainText
          text: "Click a job to open its run on GitHub"
          horizontalAlignment: Text.AlignHCenter
          color: root.dim(0.45)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { foreground: root.barForeground }

        // ---------- Footer: the config and the token · a new job with the agent ----------
        RowLayout {
          width: parent.width
          spacing: Style.space(4)

          Button {
            iconText: "󰏫"
            text: "Config"
            tooltipText: root.host ? "Edit the config on " + root.host + ", in a terminal" : "Edit the config, in a terminal"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.inTerminal(View.onMain(root.host, ["edit"]))
          }

          Button {
            iconText: "󰖟"
            text: "Token"
            tooltipText: "Give a token access to a repo, on GitHub's token page"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.run("xdg-open " + View.quote(View.TOKEN_PAGE))
          }

          Item { Layout.fillWidth: true }

          Button {
            iconText: "󰚩"
            text: "Set up with agent"
            tooltipText: "Your default coding agent puts a workflow on cronward with you"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            bordered: !!root.view && root.view.kind === "nojobs"
            onClicked: root.setUp()
          }
        }
      }
    }
  }
}
