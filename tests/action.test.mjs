// Run now and Remove job on a row: the question asked first, the command only
// on its yes, and what cronward's answer means (demo/fixtures/action), with
// `--on` failing.
import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const View = require("../CronwardView.js")
const QML = fs.readFileSync(new URL("../Cronward.qml", import.meta.url), "utf8")

function fixture(name) {
  return fs.readFileSync(new URL(`../demo/fixtures/action/${name}.txt`, import.meta.url), "utf8")
}

const row = { name: "nightly", repo: "me/widget", workflow: "check.yml" }
const run = View.action("run", row, "homeserver")
const remove = View.action("remove", row, "homeserver")

function result(act, exitCode, stdout = "", stderr = "", host = "homeserver") {
  return View.actionResult(act, { started: true, exitCode, stdout, stderr }, host)
}

const SSH = "ssh: connect to host homeserver port 22: Connection refused\n"
  + "cronward: cannot run cronward on homeserver: ssh failed (above)\n"

test("the question names the job, repo and workflow, and what each does", () => {
  assert.equal(run.question, "Start a real run of check.yml in me/widget now, as the job nightly? "
    + "GitHub runs it as it would at a slot.")
  assert.equal(run.confirmText, "Run")
  assert.match(remove.question, /^Take nightly \(me\/widget check\.yml\) off cronward\? Only cronward's config changes: the workflow and its file stay as they are/)
  assert.equal(remove.confirmText, "Remove")
  assert.equal(View.action("other", row, ""), null)
})

test("the commands run on the main machine, as a list", () => {
  assert.deepEqual(run.args, ["--on", "homeserver", "run", "nightly"])
  assert.deepEqual(remove.args, ["--on", "homeserver", "remove", "nightly"])
  assert.deepEqual(View.action("run", row, "").args, ["run", "nightly"])
  assert.deepEqual(View.action("run", { ...row, name: "x; rm -rf ~" }, "").args, ["run", "x; rm -rf ~"])
})

test("only a yes gives a command; a cancel runs nothing", () => {
  assert.deepEqual(View.confirmed(run, true), run.args)
  assert.equal(View.confirmed(run, false), null)
  assert.equal(View.confirmed(run, undefined), null)
  assert.equal(View.confirmed(run, "yes"), null)
  assert.equal(View.confirmed(null, true), null)
})

test("the QML runs a command only from the dialog's yes, which starts on Cancel", () => {
  assert.equal(QML.match(/actProc\.running = true/g).length, 1)
  const answer = QML.slice(QML.indexOf("function answer(yes)"), QML.indexOf("function finishAction()"))
  assert.match(answer, /View\.confirmed\(act, yes\)/)
  assert.match(answer, /actProc\.running = true/)
  assert.deepEqual(QML.match(/answer\(true\)/g).length, 1)
  assert.match(QML, /onConfirmed: root\.answer\(true\)/)
  assert.match(QML, /onCanceled: root\.answer\(false\)/)
  assert.match(QML, /confirm\.selectedIndex = 0/)
})

test("run started: cronward's line, and that started is not passed", () => {
  const r = result(run, 0, fixture("run-started"))
  assert.equal(r.kind, "done")
  assert.equal(r.level, "ok")
  assert.equal(r.message, "started nightly: https://github.com/me/widget/actions/runs/9100000001\n"
    + "Started, not passed yet: the row shows the result when the run ends.")
})

test("removed: cronward's lines", () => {
  const r = result(remove, 0, fixture("removed"))
  assert.equal(r.kind, "done")
  assert.equal(r.message, "removed nightly from /home/me/.config/cronward/config.toml\n"
    + "If GitHub should run the workflow on its own again, put its `schedule:` back.")
})

test("refused by cronward: its own message, from stdout or stderr", () => {
  const start = result(run, 1, fixture("run-refused"))
  assert.equal(start.kind, "refused")
  assert.equal(start.level, "warn")
  assert.match(start.message, /^nightly didn't run: Workflow does not have 'workflow_dispatch' trigger/)
  const gone = result(remove, 2, "", "cronward: no job nightly in /home/me/.config/cronward/config.toml\n")
  assert.equal(gone.kind, "refused")
  assert.equal(gone.message, "no job nightly in /home/me/.config/cronward/config.toml")
  assert.equal(result(run, 1).message, "`cronward run nightly` exited 1")
})

test("--on failing: ssh, a key that only reads the status, an old cronward, none at all", () => {
  const ssh = result(run, 2, "", SSH)
  assert.deepEqual([ssh.kind, ssh.level], ["unreachable", "bad"])
  assert.equal(ssh.message, "Cannot reach homeserver over ssh: connect to host homeserver port 22: Connection refused.")
  const key = result(remove, 1, "", "cronward: this key only reads the status\n")
  assert.deepEqual([key.kind, key.level], ["readonly", "warn"])
  assert.match(key.message, /so this machine cannot remove jobs/)
  const old = result(run, 2, "", "usage: cronward [-h] COMMAND ...\ncronward: error: unrecognized arguments: --on\n")
  assert.equal(old.message, "cronward here or on homeserver is too old to start runs through `--on`: update it.")
  const none = View.actionResult(run, { started: false, exitCode: 0, stdout: "", stderr: "" }, "")
  assert.deepEqual([none.kind, none.level], ["missing", "bad"])
})
