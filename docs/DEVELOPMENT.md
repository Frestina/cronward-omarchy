# Develop and test the plugin

Read [README.md](../README.md) and [ARCHITECTURE.md](../ARCHITECTURE.md)
before a change.

Run `./tests/run` for the portable checks: the template's structure check,
`CronwardView.js` against every fixture (in UTC), and the demo scripts with
`bash -n` and shellcheck. On an Omarchy machine also run
`omarchy plugin validate "$PWD"`.

The plain-text check from the Build Omarchy Plugins test skill
(`omarchy-plugin-test`) checks that every `Text` and tooltip in the QML
shows its text as plain text. Run it from the skill's folder:

```bash
python3 <skill-dir>/scripts/check_plain_text.py "$PWD"
```

It reads the QML by its tokens, not as QML, so a regular expression in a
QML file can trip it ("Unbalanced braces"). Keep such logic in
`CronwardView.js`, with a test, as the theme colours are
(`themeColors()`).

## Rules for changes

- The widget only displays: cronward decides what passed, failed or didn't
  run, `CronwardView.js` sorts it, and `Cronward.qml` shows it. Keep rules
  out of QML. See [ARCHITECTURE.md](../ARCHITECTURE.md) for what the widget
  may run; it never reads cronward's files or a token, and never talks to
  the network or ssh itself. A change on the main machine is
  `cronward --on HOST ...`.
- Every new state gets a fixture in `demo/fixtures` and a test, and
  `demo/run` shows it in the installed widget. Test the behaviour you
  changed; the portable checks do not stand in for trying it in the bar.
- Fixtures, docs and screenshots use fictional names (`me/widget`,
  `homeserver`), never real hostnames, usernames or home paths.
- Follow [Build Omarchy Plugins](https://github.com/tcballard/build-omarchy-plugins)
  guidance, and check the current upstream contract before relying on an
  API of one Omarchy version.
- The widget keeps its settings in its own `shell.json` entry. Removing it
  leaves user data and unrelated desktop configuration as they were.
- Keep the README's centered title, its one category badge and the credit
  to the projects it builds on. Claim a screenshot, a listing or a
  supported version only with evidence.
- Workflow actions stay pinned to a full commit SHA, with the fewest token
  permissions. Nothing for developing the widget goes in the checkout that
  Omarchy installs: no agent instruction files (see "What is installed" in
  ARCHITECTURE.md).
- `.template/blueprint` keeps the starter as it was generated; change the
  product files instead.
- Release notes say what changed for the user (Merge and Tell guidance when
  available).
- Docs: sentence case headings, straight quotes, no em dashes, no emoji.

## In the bar

Link the checkout as the plugin, then enable it:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.frestina.cronward
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.frestina.cronward
```

After a change to a QML file, run `omarchy restart shell`: a plugin reached
through a link is not loaded again by `rescanPlugins`. Its log is the
newest `/run/user/$UID/quickshell/by-id/*/log.log`.

To see the states without a real cronward, `demo/run "<x>,<y> <w>x<h>"
[STATE...]` points the widget at `demo/cronward` for a moment, captures each
state to `demo/out/`, and puts `~/.config/omarchy/shell.json` back. The
states are the fixture names plus `not-set-up` and `error`, and for the
workflow picker `workflows-NAME` for each `fixtures/workflows/NAME.json`,
plus `workflows-unreachable` and `workflows-readonly`. For the add form,
`add-form` shows it, and `add-added`, `add-refused` and `add-unreachable`
press Enter in it with `wtype` and show what came of it. For Run now and
Remove, `run-confirm` and `remove-confirm` show the question, `run-cancelled`
answers it with Esc, and `run-started`, `run-refused`, `remove-done` and
`action-unreachable` answer yes. `account-confirm` asks to remove the
account `work` on the picker, and `account-removed` and `account-old` answer
yes, from a current cronward and an older one. With no state it
writes `preview.png` from `mixed`; check that it shows only fictional names
before committing it. Capture the popup and the bar icon above it, 422
logical pixels wide from its left edge less one. `docs/workflows.png` is
`workflows-list` with the repo `widget` open: start `openRepos` as
`{"personal/me/widget": true}` for the capture, then put it back.

Over IPC: `qs ipc call io.github.frestina.cronward open|close|toggle|refresh|check|workflows`,
`add ACCOUNT OWNER/REPO FILE` for the add form, and `askRun JOB` or
`askRemove JOB` for the question on a row, and `askRemoveAccount ACCOUNT`
on the picker.

## By hand, before a release

- Horizontal and vertical bars, and a theme switch (the orange follows it).
- On the main machine (host blank) and on a viewer (host set).
- A row opens its run; Check now updates "as of" on a viewer; middle and
  right click.
- Config, the key and Set up with agent open a terminal or the agent; on a
  viewer, through `cronward --on`.
- Add job from the picker: the job shows in the bar after the add, and a
  refused add says why.
- Run now and Remove ask first; Cancel and Esc do nothing; a yes to Run now
  shows the row running, a yes to Remove takes the row away.
- Remove account: dimmed with the jobs named while a job uses the account;
  otherwise asks, and the account leaves the picker and `cronward status`.

Remove with `omarchy plugin remove io.github.frestina.cronward`, or delete the
link. The widget keeps no files.
