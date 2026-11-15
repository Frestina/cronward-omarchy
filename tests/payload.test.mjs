// What Omarchy installs is the whole checkout, so it holds no instructions
// for the agents that develop the widget. The guides in docs/ that the
// widget hands to the user's agent are part of the product and stay.
import test from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)))
const AGENT_FILES = new Set(["AGENTS.md", "CLAUDE.md", "GEMINI.md", "HANDOFF.md",
  ".claude", ".codex", ".agents", ".cursor", ".cursorrules"])

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const rel = path.relative(ROOT, path.join(dir, entry.name))
    if (rel === ".git" || rel === path.join("demo", "out")) continue
    out.push(rel)
    if (entry.isDirectory()) walk(path.join(dir, entry.name), out)
  }
  return out
}

test("no agent instruction files in the checkout", () => {
  const found = walk(ROOT).filter((f) => AGENT_FILES.has(path.basename(f)))
  assert.deepEqual(found, [])
})

test("the guides the widget hands to the user's agent ship", () => {
  for (const f of ["docs/AGENT_SETUP.md", "docs/AGENT_EXPLAIN.md"]) {
    assert.ok(fs.statSync(path.join(ROOT, f)).isFile(), f)
  }
})
