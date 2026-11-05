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

  // The popup's page: "status", or "workflows" for the picker, which lists
  // what `cronward workflows --json` gives, as CronwardView.picker() sorts it.
  property string page: "status"
  property var pickerView: null
  property bool picking: false
  property bool wfStarted: false
  property int wfExitCode: 0
  // Asked to list again while a list was running: that one may predate a
  // change (a removed account), so list once more when it ends.
  property bool wfAgain: false
  // Which picker sections are toggled: repos start collapsed, accounts open.
  // Kept by name, so listing again keeps them as they were.
  property var openRepos: ({})
  property var closedAccounts: ({})

  // The add page: a form that puts one picked workflow on cronward with
  // `cronward [--on HOST] add`. addTarget is the workflow and its account.
  property var addTarget: null
  property string addName: ""
  property string addSchedule: View.DEFAULT_SCHEDULE
  property string addZone: ""
  property bool adding: false
  property bool addStarted: false
  property int addExitCode: 0
  // What View.addResult() made of cronward's answer, when it was not "added".
  property var addOutcome: null
  // cronward's lines after an add, a run or a removal, shown over the jobs
  // until the popup closes; statusNoteLevel is "ok", "warn" or "bad".
  property string statusNote: ""
  property string statusNoteLevel: "ok"
  // The page the note belongs to: "status", or "workflows" after Remove account.
  property string notePage: "status"

  // Run now and Remove job: View.action() while the question is open, null
  // otherwise. Nothing runs but on its yes, the dialog's onConfirmed.
  property var pendingAction: null
  property var currentAction: null
  property bool acting: false
  property bool actStarted: false
  property int actExitCode: 0
  readonly property var addForm: addTarget ? { account: addTarget.account, repo: addTarget.repo,
    file: addTarget.file, name: addName, schedule: addSchedule, timezone: addZone } : null
  readonly property string addProblem: addForm ? View.addProblem(addForm, View.jobNames(view, pickerView)) : ""

  function toggled(map, key) {
    var next = {}
    for (var k in map) next[k] = map[k]
    if (next[key]) delete next[key]
    else next[key] = true
    return next
  }

  readonly property string level: view ? view.level : "quiet"
  readonly property int count: view ? view.count : 0
  readonly property var hostProblems: view ? view.problems.filter(function(p) { return p.scope === "host" }) : []
  readonly property bool allPassed: !!view && view.kind === "status" && view.level === "quiet"

  // Warnings in the theme's orange (or yellow), which the shell's palette
  // lacks; its accent can be any hue, red included.
  property color warnColor: Color.accent
  // "On cronward" in the theme's green, else color2, else the accent.
  property color okColor: Color.accent

  readonly property string caption: {
    if (page === "workflows")
      return picking ? "Asking GitHub…" : "Workflows · " + (host || "this machine")
    if (page === "add")
      return adding ? "Adding…" : "Add a job · " + (host || "this machine")
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

  // The picker: the repos and workflows the main machine's tokens reach. It
  // asks GitHub for every repo, so it runs only when asked, never on a timer.
  function openWorkflows() {
    page = "workflows"
    if (!root.opened) root.open()
    fetchWorkflows()
  }

  function fetchWorkflows() {
    if (wfProc.running) {
      wfAgain = true
      return
    }
    picking = true
    wfStarted = false
    wfExitCode = 0
    wfProc.command = View.processArgv(root.cronward, View.workflowsArgs(root.host))
    wfProc.running = true
  }

  function finishWorkflows() {
    picking = false
    root.pickerView = View.picker({ started: wfStarted, exitCode: wfExitCode,
                                    stdout: wfOut.text, stderr: wfErr.text }, root.host)
    if (wfAgain) {
      wfAgain = false
      Qt.callLater(root.fetchWorkflows)
    }
  }

  function setUpWorkflow(w) {
    run(View.agent(View.setupWorkflowPrompt(root.host, root.pluginDir, w.repo, w.file)))
  }

  // The form for a picked workflow, with a name cronward has not got yet.
  function startAdd(w, account) {
    addTarget = { account: String(account || ""), repo: w.repo, file: w.file,
                  name: w.name || "", jobs: w.jobs || [] }
    addName = View.jobName(w.repo, w.file, View.jobNames(root.view, root.pickerView))
    addSchedule = View.DEFAULT_SCHEDULE
    addZone = ""
    addOutcome = null
    page = "add"
    if (!root.opened) root.open()
    Qt.callLater(function() { nameField.forceActiveFocus() })
  }

  function backFromAdd() {
    if (adding) return
    page = pickerView ? "workflows" : "status"
    keyCatcher.forceActiveFocus()
  }

  function submitAdd() {
    if (!addForm || adding || addProblem !== "") return
    adding = true
    addOutcome = null
    addStarted = false
    addExitCode = 0
    addProc.command = View.processArgv(root.cronward, View.addArgs(root.host, addForm))
    addProc.running = true
  }

  // Added: back to the jobs, where it shows once the status is read again; on
  // a viewer that is a check, since its copy of the status is the hourly one.
  function finishAdd() {
    adding = false
    var r = View.addResult({ started: addStarted, exitCode: addExitCode,
                             stdout: addOut.text, stderr: addErr.text }, root.host)
    if (r.kind !== "added") {
      addOutcome = r
      return
    }
    statusNote = r.message
    statusNoteLevel = "ok"
    notePage = "status"
    addTarget = null
    page = "status"
    keyCatcher.forceActiveFocus()
    root.checkNow()
  }

  // Run now or Remove job on a row: asks first, and nothing runs until the yes.
  function ask(kind, row) {
    if (acting || !row) return
    if (!root.opened) root.open()
    pendingAction = kind === "account" ? View.accountAction(row, root.host)
      : View.action(kind, row, root.host)
    confirm.selectedIndex = 0
    Qt.callLater(function() { confirm.forceActiveFocus() })
  }

  function askRemoveAccount(name) {
    var accounts = root.pickerView ? root.pickerView.accounts : []
    for (var i = 0; i < accounts.length; i++)
      if (accounts[i].name === name && View.removeAccount(root.view, name).enabled)
        return ask("account", accounts[i])
  }

  function askByName(kind, name) {
    var rows = root.view ? root.view.rows : []
    for (var i = 0; i < rows.length; i++)
      if (rows[i].name === name) return ask(kind, rows[i])
  }

  // The dialog's answer. Only a yes gives a command (View.confirmed).
  function answer(yes) {
    var act = pendingAction
    pendingAction = null
    keyCatcher.forceActiveFocus()
    var args = View.confirmed(act, yes)
    if (!args || actProc.running) return
    // The action first: bindings that read it wake on acting.
    currentAction = act
    acting = true
    actStarted = false
    actExitCode = 0
    statusNote = ""
    actProc.command = View.processArgv(root.cronward, args)
    actProc.running = true
  }

  // Either way the status is read again: a started run shows as running, a
  // start that did not go through as didn't run, a removed job is gone. A
  // removed account: the workflows are listed again too.
  function finishAction() {
    acting = false
    var r = View.actionResult(currentAction, { started: actStarted, exitCode: actExitCode,
                                               stdout: actOut.text, stderr: actErr.text }, root.host)
    statusNote = r.message
    statusNoteLevel = r.level
    notePage = currentAction.kind === "account" ? "workflows" : "status"
    root.checkNow()
    if (currentAction.kind === "account") root.fetchWorkflows()
  }

  function addAccount() { run(View.terminal(View.addAccountLine(root.cronward, root.host))) }

  function openTokenPage() { run("xdg-open " + View.quote(View.TOKEN_PAGE)) }

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
    root.okColor = found.green || found.color2 || Color.accent
  }

  onOpenedChanged: {
    if (opened) return refresh()
    page = "status"
    pendingAction = null
    if (!adding && !acting) statusNote = ""
  }
  onHostChanged: { pickerView = null; refresh() }
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
    function workflows(): void { root.openWorkflows() }
    // The add form for one workflow, as the picker's add button opens it.
    function add(account: string, repo: string, file: string): void {
      root.startAdd({ repo: repo, file: file, name: "", jobs: [] }, account)
    }
    // Ask to run or remove a job, as its row's buttons do; nothing runs without the yes.
    function askRun(job: string): void { root.askByName("run", job) }
    function askRemove(job: string): void { root.askByName("remove", job) }
    // On the picker, an account no job uses; nothing runs without the yes.
    function askRemoveAccount(account: string): void { root.askRemoveAccount(account) }
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

  // `cronward [--on HOST] workflows --json`, run as refresh's proc is.
  Process {
    id: wfProc
    onStarted: root.wfStarted = true
    onExited: function(exitCode) { root.wfExitCode = exitCode }
    onRunningChanged: if (!running) root.finishWorkflows()
    stdout: StdioCollector { id: wfOut; waitForEnd: true }
    stderr: StdioCollector { id: wfErr; waitForEnd: true }
  }

  // `cronward [--on HOST] add JOB ...`, argv as a list, never a shell line.
  Process {
    id: addProc
    onStarted: root.addStarted = true
    onExited: function(exitCode) { root.addExitCode = exitCode }
    onRunningChanged: if (!running) root.finishAdd()
    stdout: StdioCollector { id: addOut; waitForEnd: true }
    stderr: StdioCollector { id: addErr; waitForEnd: true }
  }

  // `cronward [--on HOST] run JOB` or `remove JOB`, after a yes.
  Process {
    id: actProc
    onStarted: root.actStarted = true
    onExited: function(exitCode) { root.actExitCode = exitCode }
    onRunningChanged: if (!running) root.finishAction()
    stdout: StdioCollector { id: actOut; waitForEnd: true }
    stderr: StdioCollector { id: actErr; waitForEnd: true }
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
    // Neither on a vertical bar: no room, and the tooltip says it. From
    // Omarchy 4.5.0 the mark goes in labelText, as the battery's percentage
    // does: the shell fits all of text into one icon's box, so a count there
    // would shrink the glyph with it. An older shell has no labelText and
    // draws text at its own size, so there the mark stays in text. Assigning
    // labelText where it does not exist would fail the whole icon, hence the
    // check.
    readonly property string mark: vertical ? ""
      : root.count > 0 ? String(root.count) : root.view && root.view.running ? "•" : ""
    readonly property bool hasLabel: "labelText" in button
    text: mark !== "" && !hasLabel ? "󰃰 " + mark : "󰃰"
    Component.onCompleted: {
      if (hasLabel) button.labelText = Qt.binding(function() { return button.mark })
    }
    slotSize: Style.bar.iconSlot * (mark !== "" ? 1.1 + 0.5 * mark.length : 1)
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
    // Room for the question when the jobs are few.
    contentHeight: panel.fittedContentHeight(Math.max(content.implicitHeight,
      root.pendingAction ? Style.space(240) : 0))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // A form field owns its keys (j, k, x, space…); Esc and Enter there are its own.
      // So does the question to run or remove a job.
      blocked: nameField.activeFocus || cronField.activeFocus || zoneField.activeFocus
        || root.pendingAction !== null
      // Esc on the form goes back to the picker, on the picker to the status;
      // on the status it closes.
      onCloseRequested: {
        if (root.page === "add") root.backFromAdd()
        else if (root.page === "workflows") root.page = "status"
        else root.close()
      }
      onTabRequested: function(direction) {
        if (root.page === "add") nameField.forceActiveFocus()
        else root.switchPanel(direction)
      }
      onTextKey: function(t) {
        if (t !== "r" || root.page === "add") return
        if (root.page === "workflows") root.fetchWorkflows()
        else root.checkNow()
      }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)
        // Everything on the picker's page but its list, which scrolls in what is left.
        readonly property real chromeHeight: hero.implicitHeight + pickerRule.height
          + footerRule.height + footer.implicitHeight + 4 * spacing

        // ---------- Hero: icon · title and the main machine · actions ----------
        RowLayout {
          id: hero
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
            visible: root.page === "workflows" || root.page === "add"
            iconText: "󰁍"
            tooltipText: root.page === "add" ? "Back to the workflows (Esc)" : "Back to the jobs (Esc)"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            enabled: !root.adding
            onClicked: if (root.page === "add") root.backFromAdd(); else root.page = "status"
          }

          PanelActionButton {
            visible: root.page === "status"
            iconText: "󰑐"
            tooltipText: root.host ? "Check now: fetch the status from " + root.host + " (r)" : "Check now (r)"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            enabled: !root.checking
            onClicked: root.checkNow()
          }

          PanelActionButton {
            visible: root.page === "workflows"
            iconText: "󰑐"
            tooltipText: "List the workflows again (r)"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            enabled: !root.picking
            onClicked: root.fetchWorkflows()
          }

          PanelActionButton {
            iconText: "󰆍"
            tooltipText: "cronward status in a terminal"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            onClicked: root.openStatus()
          }
        }

        // ---------- The status page: the jobs and what needs a look ----------
        Column {
          id: statusPage
          visible: root.page === "status"
          width: parent.width
          spacing: content.spacing

          // ---------- Just added, started or removed: cronward's own lines ----------
          Text {
            visible: root.acting ? root.currentAction.kind !== "account"
              : root.statusNote !== "" && root.notePage === "status"
            width: parent.width
            textFormat: Text.PlainText
            text: root.acting ? (root.currentAction.kind === "run" ? "Starting " : "Removing ")
              + root.currentAction.job + "…" : root.statusNote
            wrapMode: Text.Wrap
            color: root.acting ? root.dim(0.7) : root.statusNoteLevel === "ok" ? root.okColor
              : root.statusNoteLevel === "bad" ? Color.urgent : root.warnColor
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
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

                  // A real run of the workflow: asks first.
                  PanelActionButton {
                    iconText: "󰐊"
                    tooltipText: "Run " + jobRow.modelData.name + " now (asks first)"
                    size: Style.space(18)
                    fontSize: Style.font.caption
                    foreground: root.dim(0.75)
                    fontFamily: root.bar.fontFamily
                    enabled: !root.acting
                    onClicked: root.ask("run", jobRow.modelData)
                  }

                  // Out of cronward's config; the workflow stays. Asks first.
                  PanelActionButton {
                    iconText: "󰆴"
                    tooltipText: "Remove " + jobRow.modelData.name + " from cronward (asks first)"
                    size: Style.space(18)
                    fontSize: Style.font.caption
                    foreground: root.dim(0.75)
                    fontFamily: root.bar.fontFamily
                    enabled: !root.acting
                    onClicked: root.ask("remove", jobRow.modelData)
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
        }

        // ---------- The picker: each account's repos and workflows ----------
        PanelSeparator {
          id: pickerRule
          visible: root.page === "workflows" || root.page === "add"
          foreground: root.barForeground
          strength: root.picking && root.page === "workflows" ? 0.2 : 0.12

          // While the list is asked for: a bar sweeping along the rule.
          Rectangle {
            id: busyBar
            visible: root.picking && root.page === "workflows"
            y: -1
            width: parent.width * 0.3
            height: 3
            radius: 1.5
            color: Color.accent

            SequentialAnimation on x {
              running: busyBar.visible && !Style.reduceMotion
              loops: Animation.Infinite
              NumberAnimation { from: -busyBar.width; to: pickerRule.width; duration: 1100; easing.type: Easing.InOutQuad }
            }
          }
        }

        Flickable {
          id: flick
          visible: root.page === "workflows"
          width: parent.width
          height: Math.min(pickerList.implicitHeight, Math.max(Style.space(120),
            panel.availableCardHeight - panel.verticalContentInset - content.chromeHeight))
          contentHeight: pickerList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: pickerList
            width: flick.width
            spacing: Style.space(10)
            // The old list, while a new one is asked for: faded, and not to be
            // acted on, as it may be out of date.
            readonly property bool stale: root.picking && !!root.pickerView
            opacity: stale ? 0.4 : 1
            enabled: !stale
            Behavior on opacity { NumberAnimation { duration: typeof Style.duration === "function" ? Style.duration(150) : 150 } }

            // After Remove account: cronward's lines, and the token page, where
            // the token itself is deleted.
            RowLayout {
              visible: root.acting ? root.currentAction.kind === "account"
                : root.statusNote !== "" && root.notePage === "workflows"
              width: parent.width
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: root.acting ? "Removing " + root.currentAction.job + "…" : root.statusNote
                wrapMode: Text.Wrap
                color: root.acting ? root.dim(0.7) : root.statusNoteLevel === "ok" ? root.okColor
                  : root.statusNoteLevel === "bad" ? Color.urgent : root.warnColor
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              PanelActionButton {
                visible: !root.acting
                Layout.alignment: Qt.AlignTop
                iconText: "󰖟"
                tooltipText: "Delete the token on GitHub's token page"
                size: Style.space(18)
                fontSize: Style.font.caption
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
                onClicked: root.openTokenPage()
              }
            }

            // Before the first answer, while asking, or what went wrong.
            Text {
              readonly property string said: !root.pickerView
                ? (root.picking ? "Asking GitHub, through " + (root.host || "cronward") + ", for the repos the tokens reach…" : "")
                : root.pickerView.message
              visible: said !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: said
              wrapMode: Text.Wrap
              color: !root.pickerView || root.pickerView.kind === "list" ? root.dim(0.7)
                : root.pickerView.kind === "error" || root.pickerView.kind === "missing" ? Color.urgent
                : root.warnColor
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.pickerView ? root.pickerView.accounts : []

              delegate: Column {
                id: account
                required property var modelData
                readonly property bool open: !root.closedAccounts[modelData.name]
                readonly property var removal: View.removeAccount(root.view, modelData.name)
                width: pickerList.width
                spacing: Style.space(8)

                // The account's header: click to fold its repos away.
                Item {
                  width: parent.width
                  implicitHeight: accountHead.implicitHeight

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closedAccounts = root.toggled(root.closedAccounts, account.modelData.name)
                  }

                  RowLayout {
                    id: accountHead
                    width: parent.width
                    spacing: Style.space(4)

                    PanelSectionHeader {
                      Layout.maximumWidth: accountHead.width * 0.6
                      text: (account.modelData.name + (account.modelData.owner
                        && account.modelData.owner.toLowerCase() !== account.modelData.name.toLowerCase()
                        ? " · " + account.modelData.owner + " on GitHub" : "")).toUpperCase()
                      foreground: root.barForeground
                      fontFamily: root.bar.fontFamily
                      elide: Text.ElideRight
                    }

                    // Typed in the terminal, on the main machine; the widget never sees it.
                    PanelActionButton {
                      visible: account.modelData.error !== ""
                      iconText: "󰌆"
                      tooltipText: "Store a new token for " + account.modelData.name
                        + (root.host ? " on " + root.host : "") + ", in a terminal"
                      size: Style.space(18)
                      fontSize: Style.font.caption
                      foreground: root.barForeground
                      fontFamily: root.bar.fontFamily
                      onClicked: root.inTerminal(View.onMain(root.host, ["token", "set", account.modelData.name]))
                    }

                    PanelActionButton {
                      iconText: "󰖟"
                      tooltipText: account.modelData.tokenTip
                      size: Style.space(18)
                      fontSize: Style.font.caption
                      foreground: root.barForeground
                      fontFamily: root.bar.fontFamily
                      onClicked: root.openTokenPage()
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                      visible: !account.open && account.modelData.summary !== ""
                      textFormat: Text.PlainText
                      text: account.modelData.summary
                      color: root.dim(0.55)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: account.open ? "󰅀" : "󰅂"
                      color: root.dim(0.7)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }
                }

                Text {
                  visible: account.modelData.error !== "" || account.modelData.empty
                  width: parent.width
                  textFormat: Text.PlainText
                  text: account.modelData.error !== "" ? account.modelData.error
                    : "The token for " + account.modelData.name + " reaches no repos yet: give it access on GitHub's token page."
                  wrapMode: Text.Wrap
                  color: root.warnColor
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }

                // ---------- One card per repo: its header folds its workflows ----------
                Repeater {
                  model: account.open ? account.modelData.repos : []

                  delegate: Rectangle {
                    id: repoBlock
                    required property var modelData
                    readonly property bool open: !!root.openRepos[account.modelData.name + "/" + modelData.repo]

                    width: account.width
                    implicitHeight: repoColumn.implicitHeight + Style.space(16)
                    radius: Style.cornerRadius
                    color: repoMouse.containsMouse && !open ? root.dim(0.08) : root.dim(0.04)
                    border.width: 1
                    border.color: root.dim(0.12)

                    Column {
                      id: repoColumn
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.space(8)
                      spacing: Style.space(8)

                      Item {
                        width: parent.width
                        implicitHeight: repoHead.implicitHeight

                        MouseArea {
                          id: repoMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.openRepos = root.toggled(root.openRepos,
                            account.modelData.name + "/" + repoBlock.modelData.repo)
                        }

                        RowLayout {
                          id: repoHead
                          width: parent.width
                          spacing: Style.space(8)

                          Text {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: repoBlock.modelData.label
                            color: root.barForeground
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: true
                            elide: Text.ElideRight
                          }

                          // Seen without opening the repo: some of it is on cronward.
                          Rectangle {
                            visible: repoBlock.modelData.onCronward > 0
                            implicitWidth: repoBadge.implicitWidth + Style.space(12)
                            implicitHeight: repoBadge.implicitHeight + Style.space(4)
                            radius: height / 2
                            color: Qt.rgba(root.okColor.r, root.okColor.g, root.okColor.b, 0.18)

                            Text {
                              id: repoBadge
                              anchors.centerIn: parent
                              textFormat: Text.PlainText
                              text: "󰄬 " + repoBlock.modelData.onCronward + " on cronward"
                              color: root.okColor
                              font.family: root.bar.fontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                          }

                          Text {
                            textFormat: Text.PlainText
                            text: repoBlock.modelData.summary
                            color: repoBlock.modelData.error !== "" ? root.warnColor : root.dim(0.55)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.caption
                          }

                          Text {
                            textFormat: Text.PlainText
                            text: repoBlock.open ? "󰅀" : "󰅂"
                            color: root.dim(0.7)
                            font.family: root.bar.fontFamily
                            font.pixelSize: Style.font.body
                          }
                        }
                      }

                      Text {
                        visible: repoBlock.open && repoBlock.modelData.error !== ""
                        width: parent.width
                        textFormat: Text.PlainText
                        text: repoBlock.modelData.error
                        wrapMode: Text.Wrap
                        color: root.warnColor
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Repeater {
                        model: repoBlock.open ? repoBlock.modelData.workflows : []

                        delegate: RowLayout {
                          id: flow
                          required property var modelData
                          width: repoColumn.width
                          spacing: Style.space(8)

                          Column {
                            Layout.fillWidth: true
                            Layout.leftMargin: Style.space(8)
                            spacing: Style.space(3)

                            RowLayout {
                              width: parent.width
                              spacing: Style.space(8)

                              Text {
                                textFormat: Text.PlainText
                                text: flow.modelData.file
                                color: root.barForeground
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.bodySmall
                              }

                              Text {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: [flow.modelData.name, flow.modelData.state]
                                  .filter(function(t) { return t !== "" }).join(" · ")
                                color: flow.modelData.state !== "" ? root.warnColor : root.dim(0.55)
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.caption
                                elide: Text.ElideRight
                              }
                            }

                            // Already a job: a green pill naming it.
                            Rectangle {
                              visible: flow.modelData.job !== ""
                              implicitWidth: Math.min(parent.width, jobBadge.implicitWidth + Style.space(12))
                              implicitHeight: jobBadge.implicitHeight + Style.space(4)
                              radius: height / 2
                              color: Qt.rgba(root.okColor.r, root.okColor.g, root.okColor.b, 0.18)

                              Text {
                                id: jobBadge
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, parent.width - Style.space(12))
                                textFormat: Text.PlainText
                                text: "󰄬 " + flow.modelData.job
                                color: root.okColor
                                font.family: root.bar.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                elide: Text.ElideRight
                              }
                            }
                          }

                          // Add it as a job from a form: for a workflow that already has
                          // workflow_dispatch:, which cronward cannot see, so the form says so.
                          PanelActionButton {
                            iconText: "󰐕"
                            tooltipText: (flow.modelData.jobs.length ? "Add another job for " : "Add a job for ")
                              + flow.modelData.file + ", from a form"
                            size: Style.space(18)
                            fontSize: Style.font.caption
                            foreground: root.barForeground
                            fontFamily: root.bar.fontFamily
                            onClicked: root.startAdd(flow.modelData, account.modelData.name)
                          }

                          PanelActionButton {
                            iconText: "󰚩"
                            tooltipText: View.setupTip(flow.modelData)
                            size: Style.space(18)
                            fontSize: Style.font.caption
                            foreground: root.barForeground
                            fontFamily: root.bar.fontFamily
                            onClicked: root.setUpWorkflow(flow.modelData)
                          }
                        }
                      }
                    }
                  }
                }

                // ---------- The repos with no workflows: one folded card, one per line ----------
                Rectangle {
                  id: bareBlock
                  readonly property bool open: !!root.openRepos[account.modelData.name + "/:bare"]

                  visible: account.open && account.modelData.bare.length > 0
                  width: account.width
                  implicitHeight: bareColumn.implicitHeight + Style.space(16)
                  radius: Style.cornerRadius
                  color: bareMouse.containsMouse && !open ? root.dim(0.06) : "transparent"
                  border.width: 1
                  border.color: root.dim(0.08)

                  Column {
                    id: bareColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Style.space(8)
                    spacing: Style.space(6)

                    Item {
                      width: parent.width
                      implicitHeight: bareHead.implicitHeight

                      MouseArea {
                        id: bareMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openRepos = root.toggled(root.openRepos, account.modelData.name + "/:bare")
                      }

                      RowLayout {
                        id: bareHead
                        width: parent.width
                        spacing: Style.space(8)

                        Text {
                          Layout.fillWidth: true
                          textFormat: Text.PlainText
                          text: "No workflows"
                          color: root.dim(0.7)
                          font.family: root.bar.fontFamily
                          font.pixelSize: Style.font.bodySmall
                        }

                        Text {
                          textFormat: Text.PlainText
                          text: account.modelData.bareSummary
                          color: root.dim(0.55)
                          font.family: root.bar.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          textFormat: Text.PlainText
                          text: bareBlock.open ? "󰅀" : "󰅂"
                          color: root.dim(0.7)
                          font.family: root.bar.fontFamily
                          font.pixelSize: Style.font.body
                        }
                      }
                    }

                    Repeater {
                      model: bareBlock.open ? account.modelData.bare : []

                      delegate: Text {
                        required property var modelData
                        width: bareColumn.width
                        leftPadding: Style.space(8)
                        textFormat: Text.PlainText
                        text: modelData
                        color: root.dim(0.6)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }
                  }
                }

                // Out of the way below the repos, and asks first. Not while a job uses it.
                RowLayout {
                  visible: account.open
                  width: account.width

                  Button {
                    iconText: "󰆴"
                    text: "Remove account"
                    tooltipText: account.removal.tip
                    foreground: root.dim(0.7)
                    fontFamily: root.bar.fontFamily
                    fontSize: Style.font.caption
                    // Hoverable even when it cannot remove, so its tooltip says why.
                    enabled: !root.acting
                    opacity: account.removal.enabled && enabled ? 1 : 0.45
                    onClicked: if (account.removal.enabled) root.ask("account", account.modelData)
                  }

                  Item { Layout.fillWidth: true }
                }
              }
            }

            Text {
              visible: !!root.pickerView && root.pickerView.kind === "list"
              width: parent.width
              textFormat: Text.PlainText
              text: ((root.pickerView && (root.pickerView.github || []).length > 0
                ? "Not listed: " + root.pickerView.github.join(", ") + ", which GitHub runs itself. " : "")
                + "Repos from another GitHub account need a token of their own: Add account.")
              wrapMode: Text.Wrap
              color: root.dim(0.45)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---------- The add form: one picked workflow, as a job ----------
        Column {
          id: addPage
          visible: root.page === "add"
          width: parent.width
          spacing: Style.space(6)

          // The workflow and account, as the picker listed them.
          Rectangle {
            width: parent.width
            implicitHeight: addCard.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: root.dim(0.04)
            border.width: 1
            border.color: root.dim(0.12)

            Column {
              id: addCard
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(8)
              spacing: Style.space(3)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.addTarget ? root.addTarget.repo : ""
                color: root.barForeground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.addTarget ? [root.addTarget.file, root.addTarget.name]
                  .filter(function(t) { return t !== "" }).join(" · ")
                  + " · token of " + root.addTarget.account : ""
                color: root.dim(0.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Text {
                visible: !!root.addTarget && root.addTarget.jobs.length > 0
                width: parent.width
                textFormat: Text.PlainText
                text: root.addTarget ? "󰄬 on cronward already: " + root.addTarget.jobs.join(", ") : ""
                color: root.okColor
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }

          Item { width: 1; height: Style.space(2) }

          Text {
            textFormat: Text.PlainText
            text: "Job name"
            color: root.dim(0.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          TextField {
            id: nameField
            width: parent.width
            text: root.addName
            onTextChanged: if (text !== root.addName) root.addName = text
            enabled: !root.adding
            foreground: root.barForeground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            onAccepted: root.submitAdd()
            Keys.onEscapePressed: root.backFromAdd()
          }

          Text {
            textFormat: Text.PlainText
            text: "Schedule"
            color: root.dim(0.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          TextField {
            id: cronField
            width: parent.width
            text: root.addSchedule
            onTextChanged: if (text !== root.addSchedule) root.addSchedule = text
            enabled: !root.adding
            placeholderText: View.DEFAULT_SCHEDULE
            foreground: root.barForeground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            onAccepted: root.submitAdd()
            Keys.onEscapePressed: root.backFromAdd()
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: View.scheduleHint(root.addSchedule, root.addZone)
            wrapMode: Text.Wrap
            color: root.dim(0.55)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            textFormat: Text.PlainText
            text: "Time zone, if not the config's"
            color: root.dim(0.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          TextField {
            id: zoneField
            width: parent.width
            text: root.addZone
            onTextChanged: if (text !== root.addZone) root.addZone = text
            enabled: !root.adding
            placeholderText: "Europe/Oslo, UTC, or local for the main machine's"
            foreground: root.barForeground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            onAccepted: root.submitAdd()
            Keys.onEscapePressed: root.backFromAdd()
          }

          Item { width: 1; height: Style.space(2) }

          // cronward cannot see the trigger, so the form says what it needs.
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "The workflow needs workflow_dispatch: under on: on its default branch. cronward "
              + "cannot see that before the first slot; without it, the job didn't run and says why. "
              + "Not sure? Set up with agent adds it."
            wrapMode: Text.Wrap
            color: root.dim(0.45)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          // What is wrong with the form, else why cronward did not add it.
          Text {
            readonly property string said: root.addProblem !== "" ? root.addProblem
              : root.addOutcome ? root.addOutcome.message : ""
            visible: said !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: said
            wrapMode: Text.Wrap
            color: root.addProblem === "" && root.addOutcome
              && (root.addOutcome.kind === "missing" || root.addOutcome.kind === "unreachable")
              ? Color.urgent : root.warnColor
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { id: footerRule; foreground: root.barForeground }

        // ---------- Footer ----------
        // Jobs: the config and the token · the picker and a new job with the agent.
        // Picker: a new account and the token · a new job with the agent.
        RowLayout {
          id: footer
          width: parent.width
          spacing: Style.space(4)

          Button {
            visible: root.page === "status"
            iconText: "󰏫"
            text: "Config"
            tooltipText: root.host ? "Edit the config on " + root.host + ", in a terminal" : "Edit the config, in a terminal"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.inTerminal(View.onMain(root.host, ["edit"]))
          }

          Button {
            visible: root.page === "workflows"
            iconText: "󰀔"
            text: "Add account"
            tooltipText: "Store a token for another GitHub account" + (root.host ? " on " + root.host : "")
              + ", in a terminal: make it on GitHub's token page first, signed in as that account"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.addAccount()
          }

          Button {
            visible: root.page !== "add"
            iconText: "󰖟"
            text: "Token"
            tooltipText: "Give a token access to a repo, on GitHub's token page"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.openTokenPage()
          }

          Item { visible: root.page !== "add"; Layout.fillWidth: true }

          Button {
            visible: root.page === "status"
            iconText: "󰉹"
            text: "Workflows"
            tooltipText: "The repos and workflows the tokens reach, to put one on cronward"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.openWorkflows()
          }

          Button {
            visible: root.page !== "add"
            iconText: "󰚩"
            text: root.page === "status" ? "Set up" : "Set up with agent"
            tooltipText: "Your default coding agent puts a workflow on cronward with you"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            bordered: !!root.view && root.view.kind === "nojobs"
            onClicked: root.setUp()
          }

          // The form: the agent for this workflow instead, back, or add.
          Button {
            visible: root.page === "add"
            iconText: "󰚩"
            text: "Set up with agent"
            tooltipText: "Your agent adds workflow_dispatch: if it is missing, and sets the schedule with you"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            enabled: !root.adding
            onClicked: root.setUpWorkflow(root.addTarget)
          }

          Item { visible: root.page === "add"; Layout.fillWidth: true }

          Button {
            visible: root.page === "add"
            text: "Cancel"
            tooltipText: "Back to the workflows (Esc)"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            enabled: !root.adding
            onClicked: root.backFromAdd()
          }

          Button {
            visible: root.page === "add"
            iconText: "󰐕"
            text: root.adding ? "Adding…" : "Add job"
            tooltipText: "cronward checks the job with GitHub, then adds it to the config"
              + (root.host ? " on " + root.host : "")
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            enabled: !root.adding && root.addProblem === ""
            opacity: enabled ? 1 : 0.45
            onClicked: root.submitAdd()
          }
        }
      }

      // ---------- Run now / Remove job: the question, over the popup ----------
      // Starts on Cancel, so Enter alone never runs or removes anything.
      ConfirmDialog {
        id: confirm
        anchors.fill: parent
        z: 10
        opened: root.pendingAction !== null
        message: root.pendingAction ? root.pendingAction.question : ""
        cancelText: "Cancel"
        confirmText: root.pendingAction ? root.pendingAction.confirmText : "Confirm"
        foreground: root.barForeground
        fontFamily: root.bar.fontFamily
        onCanceled: root.answer(false)
        onConfirmed: root.answer(true)
        Keys.onPressed: function(event) { if (confirm.handleKey(event)) event.accepted = true }
      }
    }
  }
}
