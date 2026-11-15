// Every call has a deadline: coreutils timeout stops cronward and what it
// started (ssh, on a viewer) at the deadline or when the widget stops it, and
// the widget says the call gave no answer instead of staying busy.
import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { spawn } from "node:child_process"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const View = require("../CronwardView.js")
const late = (exitCode = 124) => ({ started: true, exitCode, stdout: "", stderr: "" })

test("deadlines: status 30 s, watch 60 s, workflows 180 s, the rest 90 s, through --on too", () => {
  assert.equal(View.deadline(View.statusArgs("homeserver")), 30)
  assert.equal(View.deadline(View.checkArgs("homeserver")), 60)
  assert.equal(View.deadline(View.workflowsArgs("homeserver")), 180)
  assert.equal(View.deadline(View.workflowsArgs("")), 180)
  assert.equal(View.deadline(["--on", "homeserver", "run", "nightly"]), 90)
  assert.equal(View.deadline(["token", "remove", "work"]), 90)
  assert.equal(View.processArgv("cronward", ["--on", "homeserver", "add", "x"])[5], "90")
})

test("no answer: only timeout's 124, or 137 after its KILL, and who gave none", () => {
  assert.equal(View.noAnswer(late(), ["--on", "homeserver", "add"]),
    "No answer from homeserver in 90 s, so the widget stopped it")
  assert.equal(View.noAnswer(late(137), ["watch", "homeserver"]),
    "No answer from homeserver in 60 s, so the widget stopped it")
  assert.equal(View.noAnswer(late(), ["status", "--json"]),
    "cronward gave no answer in 30 s, so the widget stopped it")
  for (const code of [0, 1, 2, 127]) assert.equal(View.noAnswer(late(code), ["status"]), "")
  assert.equal(View.noAnswer({ started: false, exitCode: 124 }, ["status"]), "")
})

test("a status that gave no answer is an error, never fine", () => {
  const v = View.model(late(), "homeserver", Date.UTC(2026, 10, 3, 13, 8))
  assert.equal(v.kind, "error")
  assert.equal(v.level, "bad")
  assert.match(v.message, /^cronward gave no answer in 30 s/)
})

test("the picker that gave no answer says so and offers r", () => {
  const p = View.picker(late(), "homeserver")
  assert.equal(p.kind, "timeout")
  assert.deepEqual(p.accounts, [])
  assert.equal(p.message, "No answer from homeserver in 180 s, so the widget stopped it. Press r to try again.")
})

test("an add that gave no answer may have added it, and reads the status again", () => {
  const r = View.addResult(late(), "homeserver")
  assert.equal(r.kind, "timeout")
  assert.equal(r.recheck, true)
  assert.match(r.message, /^No answer from homeserver in 90 s.*may have been added anyway/)
  assert.equal(View.addResult(late(), "").message.slice(0, 31), "cronward gave no answer in 90 s")
})

test("Run now, Remove and Remove account that gave no answer may have happened", () => {
  const row = { name: "nightly", repo: "me/widget", workflow: "check.yml" }
  const run = View.actionResult(View.action("run", row, "homeserver"), late(), "homeserver")
  assert.equal(run.kind, "timeout")
  assert.equal(run.level, "warn")
  assert.equal(run.message, "No answer from homeserver in 90 s, so the widget stopped it. "
    + "The run may have started anyway: the row shows it once read again.")
  assert.match(View.actionResult(View.action("remove", row, ""), late(), "").message,
    /^cronward gave no answer in 90 s.*The job may have been removed anyway/)
  assert.match(View.actionResult(View.accountAction({ name: "work", owner: "acme" }, "homeserver"),
    late(137), "homeserver").message, /The account may have been removed anyway: the list shows it/)
})

test("Check now that gave no answer says so; any other end says nothing", () => {
  assert.equal(View.checkResult(late(), "homeserver"), "Check now: no answer from homeserver in "
    + "60 s, so the widget stopped it. This is the status fetched before.")
  assert.equal(View.checkResult(late(2), "homeserver"), "")
  assert.equal(View.checkResult(late(0), "homeserver"), "")
})

// A fake cronward that starts a long child, as cronward starts ssh, and
// writes the child's pid down. Whatever is left is killed after the test,
// so a failure ends instead of hanging the run.
function fake(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cronward-deadline-"))
  const bin = path.join(dir, "cronward")
  fs.writeFileSync(bin, '#!/bin/sh\nsleep 300 &\necho $! >"$PIDFILE"\nwait\n', { mode: 0o755 })
  const f = { dir, bin, pidfile: path.join(dir, "pid"), pids: [] }
  t.after(() => {
    for (const pid of f.pids) try { process.kill(pid, "SIGKILL") } catch (e) { /* gone */ }
    fs.rmSync(dir, { recursive: true, force: true })
  })
  return f
}

function start(f, seconds) {
  const [p, ...a] = View.processArgv(f.bin, ["--on", "homeserver", "workflows", "--json"], seconds)
  const child = spawn(p, a, { env: { ...process.env, PIDFILE: f.pidfile }, stdio: "ignore" })
  f.pids.push(child.pid)
  const ended = new Promise((resolve) => child.on("exit", (code, signal) => resolve({ code, signal })))
  return { child, ended }
}

async function pidOf(f) {
  for (let i = 0; i < 100 && !fs.existsSync(f.pidfile); i++) await new Promise((r) => setTimeout(r, 20))
  await new Promise((r) => setTimeout(r, 50))
  const pid = Number(fs.readFileSync(f.pidfile, "utf8"))
  f.pids.push(pid)
  return pid
}

async function gone(pid) {
  for (let i = 0; i < 100; i++) {
    try { process.kill(pid, 0) } catch (e) { if (e.code === "ESRCH") return true }
    await new Promise((r) => setTimeout(r, 20))
  }
  return false
}

function within(promise, ms) {
  let timer
  const late = new Promise((resolve) => { timer = setTimeout(() => resolve("still running"), ms) })
  return Promise.race([promise, late]).finally(() => clearTimeout(timer))
}

test("at the deadline the call ends with 124, and cronward's child goes too", async (t) => {
  const f = fake(t)
  const { ended } = start(f, 1)
  const pid = await pidOf(f)
  assert.deepEqual(await within(ended, 8000), { code: 124, signal: null })
  assert.ok(await gone(pid), "the grandchild is still running")
})

test("stopped by the widget (SIGTERM, as a Process stops), cronward's child goes too", async (t) => {
  const f = fake(t)
  const { child, ended } = start(f, 60)
  const pid = await pidOf(f)
  child.kill("SIGTERM")
  await within(ended, 8000)
  assert.ok(await gone(pid), "the grandchild is still running")
})
