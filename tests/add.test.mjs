// Adding a job from the picker's form: the first name and schedule it offers,
// what it checks before asking cronward, the `cronward add` it runs, and
// what it makes of cronward's answer (demo/fixtures/add) and of `--on` failing.
import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const View = require("../CronwardView.js")

function fixture(name) {
  return fs.readFileSync(new URL(`../demo/fixtures/add/${name}.txt`, import.meta.url), "utf8")
}

function workflows(name) {
  const stdout = fs.readFileSync(new URL(`../demo/fixtures/workflows/${name}.json`, import.meta.url), "utf8")
  return View.picker({ started: true, exitCode: 0, stdout, stderr: "" }, "homeserver")
}

const form = { account: "personal", repo: "me/widget", file: "release.yml", name: "widget-release",
               schedule: "0 6 * * *", timezone: "" }

test("the names cronward has: the status's jobs and the picker's", () => {
  const view = { rows: [{ name: "nightly" }, { name: "backup" }] }
  assert.deepEqual(View.jobNames(view, workflows("list")), ["nightly", "backup", "drift"])
  assert.deepEqual(View.jobNames(null, null), [])
})

test("a first job name from the repo and workflow, not one cronward has", () => {
  assert.equal(View.jobName("me/widget", "release.yml", []), "widget-release")
  assert.equal(View.jobName("me/widget", "release.yml", ["widget-release"]), "widget-release-2")
  assert.equal(View.jobName("me/widget", "release.yml", ["widget-release", "widget-release-2"]), "widget-release-3")
  assert.equal(View.jobName("me/.github", "check (all).yaml", []), "github-check-all")
  assert.match(View.jobName("me/" + "x".repeat(100), "a.yml", []), /^x{60}$/)
})

test("common schedules in words, the rest left to cronward", () => {
  assert.equal(View.describeSchedule("0 6 * * *"), "every day at 06:00")
  assert.equal(View.describeSchedule("  30   7 * * 1-5 "), "Monday to Friday at 07:30")
  assert.equal(View.describeSchedule("0 6 * * 0"), "every Sunday at 06:00")
  assert.equal(View.describeSchedule("0 6 * * 7"), "every Sunday at 06:00")
  assert.equal(View.describeSchedule("15 * * * *"), "every hour at :15")
  assert.equal(View.describeSchedule("0 3 1 * *"), "on day 1 of each month at 03:00")
  for (const s of ["*/15 * * * *", "0 6 * 1 *", "0 25 * * *", "0 6 * * MON", "0 6 * *", ""])
    assert.equal(View.describeSchedule(s), "", s)
})

test("the schedule's hint says the time zone it runs in", () => {
  assert.equal(View.scheduleHint("0 6 * * *", ""), "Every day at 06:00, in the config's time zone (UTC unless set)")
  assert.equal(View.scheduleHint("0 6 * * *", "Europe/Oslo"), "Every day at 06:00 in Europe/Oslo")
  assert.equal(View.scheduleHint("0 6 * * *", "local"), "Every day at 06:00 in the time zone of the main machine")
  assert.match(View.scheduleHint("*/5 * * * *", ""), /^5 fields, as in GitHub's schedule/)
})

test("the form is checked before cronward is asked", () => {
  assert.equal(View.addProblem(form, ["nightly"]), "")
  assert.equal(View.addProblem({ ...form, name: " " }, []), "Give the job a name.")
  assert.match(View.addProblem({ ...form, name: "my job" }, []), /^A job name is letters/)
  assert.match(View.addProblem({ ...form, name: "-x" }, []), /^A job name is letters/)
  assert.equal(View.addProblem({ ...form, name: "nightly" }, ["nightly"]), "There is a job nightly already.")
  assert.match(View.addProblem({ ...form, schedule: "0 6 * *" }, []), /^A schedule is 5 fields/)
  assert.match(View.addProblem({ ...form, schedule: "0 6 * * *; rm" }, []), /^A schedule is 5 fields/)
  assert.equal(View.addProblem({ ...form, schedule: "0 6 * * MON-FRI" }, []), "")
  assert.match(View.addProblem({ ...form, timezone: "Europe Oslo" }, []), /^A time zone is a name/)
  assert.equal(View.addProblem({ ...form, timezone: "America/Argentina/Buenos_Aires" }, []), "")
})

test("cronward add runs on the main machine, with the picker's account, as a list", () => {
  assert.deepEqual(View.addArgs("homeserver", { ...form, schedule: " 0  6 * * * " }), ["--on", "homeserver",
    "add", "widget-release", "--repo", "me/widget", "--workflow", "release.yml",
    "--schedule", "0 6 * * *", "--account", "personal"])
  assert.deepEqual(View.addArgs("", { ...form, timezone: " Europe/Oslo " }).slice(-4),
    ["--account", "personal", "--timezone", "Europe/Oslo"])
  assert.deepEqual(View.addArgs("", { ...form, account: "" }).slice(-2), ["--schedule", "0 6 * * *"])
})

test("added: cronward's lines, without the command to try it", () => {
  const r = View.addResult({ started: true, exitCode: 0, stdout: fixture("added"), stderr: "" }, "homeserver")
  assert.equal(r.kind, "added")
  assert.equal(r.message, "added widget-release to /home/me/.config/cronward/config.toml: me/widget "
    + "release.yml, 0 6 * * * UTC, account personal\nnext slot: Nov 4 06:00")
})

test("refused by cronward: its own message, as it said it", () => {
  const r = View.addResult({ started: true, exitCode: 1, stdout: "", stderr: fixture("refused") }, "homeserver")
  assert.equal(r.kind, "refused")
  assert.match(r.message, /^the token for personal cannot read the workflows of me\/widget/)
  assert.match(r.message, /\nNothing was added\.$/)
  const taken = View.addResult({ started: true, exitCode: 2, stdout: "",
    stderr: "cronward: there is a job nightly already; take it out first with: cronward remove nightly\n" }, "")
  assert.equal(taken.kind, "refused")
  assert.equal(taken.message, "there is a job nightly already; take it out first with: cronward remove nightly")
  assert.equal(View.addResult({ started: true, exitCode: 2, stdout: "", stderr: "" }, "").message, "`cronward add` exited 2")
})

test("--on failing: ssh, a key that only reads the status, an old cronward, none at all", () => {
  const ssh = View.addResult({ started: true, exitCode: 2, stdout: "",
    stderr: "ssh: connect to host homeserver port 22: Connection refused\ncronward: cannot run cronward on homeserver: ssh failed (above)\n" }, "homeserver")
  assert.equal(ssh.kind, "unreachable")
  assert.equal(ssh.message, "Cannot reach homeserver over ssh: connect to host homeserver port 22: Connection refused.")
  const key = View.addResult({ started: true, exitCode: 1, stdout: "", stderr: "cronward: this key only reads the status\n" }, "homeserver")
  assert.equal(key.kind, "readonly")
  assert.match(key.message, /only reads the status, so this machine cannot add jobs/)
  const old = View.addResult({ started: true, exitCode: 2, stdout: "",
    stderr: "usage: cronward [-h] COMMAND ...\ncronward: error: unrecognized arguments: --on\n" }, "homeserver")
  assert.equal(old.kind, "old")
  assert.equal(old.message, "cronward here or on homeserver is too old to add jobs through `--on`: update it.")
  assert.equal(View.addResult({ started: false, exitCode: 0, stdout: "", stderr: "" }, "").kind, "missing")
  assert.equal(View.addResult({ started: true, exitCode: 127, stdout: "", stderr: "" }, "").kind, "missing")
})
