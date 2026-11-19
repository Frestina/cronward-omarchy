// The widget runs no cronward older than View.NEEDS: every command, the
// Process ones and the terminal ones, asks cronward its version first.
import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { execFileSync } from "node:child_process"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const View = require("../CronwardView.js")

// A fake cronward that says `version` for --version (nothing when null) and
// echoes anything else, so a test sees whether it ran.
function fakes(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cronward-gate-"))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  return (version) => {
    const bin = path.join(dir, "cronward-" + fs.readdirSync(dir).length)
    const says = version === null ? "" : `echo ${JSON.stringify(version)}`
    fs.writeFileSync(bin, `#!/bin/sh\nif [ "$1" = --version ]; then ${says}; exit 0; fi\necho "ran $*"\n`,
      { mode: 0o755 })
    return bin
  }
}

function run(bin, args) {
  const [p, ...a] = View.processArgv(bin, args)
  try {
    return { started: true, exitCode: 0, stdout: execFileSync(p, a, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }), stderr: "" }
  } catch (e) {
    return { started: true, exitCode: e.status, stdout: String(e.stdout), stderr: String(e.stderr) }
  }
}

test("the requirement is the README's", () => {
  const readme = fs.readFileSync(new URL("../README.md", import.meta.url), "utf8")
  assert.match(readme, new RegExp("\\[cronward v" + View.NEEDS.replace(/\./g, "\\.") + "\\]\\("))
})

test("a cronward of the needed version or later runs", (t) => {
  const make = fakes(t)
  for (const v of ["cronward 0.2.2", "cronward 0.2.10", "cronward 0.3.0", "cronward 1.0.0"])
    assert.equal(run(make(v), ["watch", "homeserver"]).stdout, "ran watch homeserver\n", v)
})

test("an older cronward, or one that does not say, runs nothing", (t) => {
  const make = fakes(t)
  for (const v of ["cronward 0.2.1", "cronward 0.1.0", "cronward 0.2.1; rm -rf ~", "cronward", "hello", null]) {
    const r = run(make(v), ["watch", "homeserver"])
    assert.equal(r.exitCode, View.TOO_OLD, String(v))
    assert.equal(r.stdout, "", String(v))
    const old = View.tooOld(r, "homeserver")
    assert.equal(old.kind, "outdated")
    assert.match(old.message, v === "cronward 0.2.1" ? /^cronward 0\.2\.1 is too old for this widget, which needs cronward 0\.2\.2 or later/
      : v === "cronward 0.1.0" ? /^cronward 0\.1\.0 is too old/ : /^This machine's cronward did not say its version/)
    assert.match(old.message, /\ncd ~\/\.local\/share\/cronward\ngit pull --ff-only && \.\/install\.sh\ncronward install --viewer homeserver$/)
  }
  assert.match(View.tooOld(run(make("cronward 0.2.1"), ["status", "--json"]), "").message, /\ncronward install$/)
})

test("every result reads the refusal, not as cronward's own", (t) => {
  const r = run(fakes(t)("cronward 0.2.1"), ["status", "--json"])
  const m = View.model(r, "homeserver", Date.now())
  assert.equal(m.kind, "outdated")
  assert.equal(m.level, "warn")
  assert.match(m.tooltip, /^cronward: cronward 0\.2\.1 is too old/)
  assert.equal(View.picker(r, "homeserver").kind, "outdated")
  assert.equal(View.addResult(r, "homeserver").kind, "outdated")
  assert.equal(View.actionResult({ kind: "run", job: "x", args: ["--on", "homeserver", "run", "x"] }, r, "homeserver").kind, "outdated")
  // cronward's own exit 3, if it ever has one, is not the gate's.
  assert.equal(View.tooOld({ started: true, exitCode: 3, stderr: "cronward: something\n" }, ""), null)
})

test("a missing cronward still reads as missing", (t) => {
  const r = run(path.join(os.tmpdir(), "no-such-cronward"), ["status", "--json"])
  assert.equal(r.exitCode, 127)
  assert.equal(View.model(r, "", Date.now()).kind, "missing")
})

test("the terminal's commands are refused too", (t) => {
  const make = fakes(t)
  const line = (bin) => View.shellLine(bin, ["--on", "homeserver", "edit"])
  assert.equal(execFileSync("sh", ["-c", line(make("cronward 0.2.2"))], { encoding: "utf8" }), "ran --on homeserver edit\n")
  assert.throws(() => execFileSync("sh", ["-c", line(make("cronward 0.2.1")) + "; echo after"], { stdio: "pipe" }),
    (e) => e.status === View.TOO_OLD && String(e.stdout) === ""
      && /^cronward-widget: this is cronward 0\.2\.1, and the widget needs cronward 0\.2\.2 or later \(https:\/\/github\.com\/Frestina\/cronward#updating\)\n$/.test(String(e.stderr)))
})
