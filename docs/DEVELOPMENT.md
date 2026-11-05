# Develop and test the plugin

Run `./tests/run` for the portable checks: the template's structure check,
`CronwardView.js` against every fixture (in UTC), and the demo scripts with
`bash -n` and shellcheck. On an Omarchy machine also run
`omarchy plugin validate "$PWD"`.

## In the bar

Link the checkout as the plugin, then enable it:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.frestina.cronward
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.frestina.cronward
```

The shell reloads a linked plugin when its files change. Its log is the
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
