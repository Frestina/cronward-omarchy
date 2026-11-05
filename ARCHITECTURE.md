# Architecture

One rule: cronward decides, the widget displays. The widget reads no
cronward files, holds no token, and makes no network or ssh calls of its
own. Every change is a cronward command.

## `CronwardView.js` (pure, no QML)

- `model(run, host, nowMs)` takes one run of `cronward status --json` (on a
  viewer `status --host HOST --json`) as `{started, exitCode, stdout,
  stderr}` and returns the bar's level (`quiet`, `warn`, `bad`), its count,
  whether a run is going, the tooltip, the popup header, the problems (each
  with a scope: `job`, `host` or `account`), notes, job rows and accounts.
- `classify()` sorts the run: not started or exit 127 is cronward not
  found; exit 2 with `no config at` or `no status from ... yet` is not set
  up; any other exit 2, or JSON that is not schema 1, is an error (`bad`).
  Nothing unknown is ever quiet.
- Stopped ticking: on a viewer, cronward's own `viewer.stopped_ticking`;
  on the main machine, `now - last_tick` over cronward's 30 minutes, or no
  tick at all while there are jobs.
- A disabled job's old result is no problem, as in cronward's exit code.
- Commands: `processArgv()` for a `Process` and `shellLine()` for a
  terminal both run the `cronward` setting, falling back to
  `~/.local/bin/cronward` for the default. Changes go through `onMain()`,
  which puts `--on HOST` first on a viewer. `quote()` is POSIX single
  quoting. `open()` returns an `xdg-open` line only for a
  `https://github.com/` URL of plain characters (`safeUrl()`).
- Agent prompts: `setupPrompt()` and `explainPrompt()` point at the guides
  in `docs/` by the plugin's absolute path, and say where cronward runs. The
  job as cronward reported it goes in as one JSON-quoted line without
  control or direction characters, marked as data (`asData()`). `agent()`
  starts `omarchy-agent-prompt`, or Omarchy's agent picker when no default
  agent is set.
- `picker(run, host)` takes one run of `cronward workflows --json` (on a
  viewer through `--on HOST`). JSON comes first: cronward prints every
  account even when one could not be listed (exit 2), so output that parses
  is a list, with each account's and repo's error kept in its place. Only
  output that is not JSON is a failure, sorted by its stderr: cronward
  missing, an ssh login that only reads the status, a cronward too old for
  `workflows --json` or `--on`, ssh failing, no accounts yet, or anything
  else as an error. Workflows without a `.yml` or `.yaml` file are GitHub's
  own (`dependabot-updates`) and are left out; repos with none of their own
  are named apart. An account's GitHub owner, when its repos share one,
  goes in its token page tooltip.
- `setupWorkflowPrompt()` is `setupPrompt()` plus the picked repo and
  workflow file, as data. `addAccountLine()` reads the new account's name in
  the terminal and runs `token set` with it, on the main machine.
- `when()` formats times in this machine's zone; tests run in UTC.
- It loads in QML (`import "CronwardView.js" as View`) and in node
  (`module.exports` when `module` exists).

## `Cronward.qml` (bar widget)

- A `Panel` with `manageIpc: false`, one instance per bar
  (`allowMultiple: false`). Settings: `host`, `cronward`, `refreshSec`
  (30 to 3600, default 60), read with `setting()` and clamped.
- A timer runs the status every `refreshSec`, and opening the popup or
  changing a setting runs it again. A `Process` with `StdioCollector`s;
  completion is handled on `onRunningChanged`, since a command that fails to
  start only flips `running`.
- Check now: on a viewer, `cronward watch HOST` in a second `Process`, then
  every monitor's copy reads the status again (`bar.moduleWidgets`). Its
  notices are cronward's own, from the viewer's record, so a check gives no
  notice the hourly timer would not. On the main machine, a fresh status.
- The popup has two pages: the jobs (`status`) and the workflow picker
  (`workflows`). The picker runs `workflows --json` in a third `Process`
  when it opens or on <kbd>r</kbd>, never on the timer, since it asks
  GitHub for every repo. Its list scrolls in a `Flickable` capped to the
  screen's room, as the shell's own panels do. <kbd>Esc</kbd> goes back to
  the jobs; closing the popup always returns to them.
- `BarIconButton`: `active` unless quiet, `activeColor` urgent for `bad`
  and the theme's orange for `warn`, `dimmed` when every job passed and
  nothing is running. Vertical bars show only the icon.
- Buttons go through `bar.run()` with lines from `CronwardView.js`:
  terminals with `omarchy-launch-floating-terminal-with-presentation`,
  agents with `omarchy-agent-prompt`, links with `xdg-open`.
- Warnings use the theme's `orange`, else `yellow`, else `color3`, else the
  accent, read from `colors.toml` and read again when the palette changes.
- All text is rendered with `Text.PlainText`; a test checks every `Text`.
- IPC target `io.github.frestina.cronward`: `open`, `close`, `toggle`,
  `refresh`, `check`, `workflows` (opens the picker).

## `demo/`

- `fixtures/*.json`: one cronward status per state, with fictional names
  (`me/widget`, `homeserver`). The tests read them as they are.
- `fixtures/workflows/*.json`: `cronward workflows --json` for the picker:
  a list (with a job, a workflow turned off, GitHub's own workflows and
  repos with none), an account with an error, a repo with an error, and no
  repos.
- `cronward`: a fake that prints the fixture named in
  `$XDG_RUNTIME_DIR/cronward-demo` with its times moved to now, or the
  stderr of the not-set-up and error states. It takes `--on HOST` as
  cronward does, and answers `workflows --json` from
  `fixtures/workflows/`.
- `run`: points the widget at the fake in `shell.json`, captures each state
  with `grim`, and puts `shell.json` back byte for byte on exit.

Nothing runs with elevated privileges, and nothing is installed outside the
plugin folder. The widget keeps no files; removing it leaves nothing behind.
Node.js is a development dependency for the checks only.
