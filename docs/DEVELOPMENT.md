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
states are the fixture names plus `not-set-up` and `error`. With no state it
writes `preview.png` from `mixed`; check that it shows only fictional names
before committing it.

Over IPC: `qs ipc call io.github.frestina.cronward open|close|toggle|refresh|check`.

## By hand, before a release

- Horizontal and vertical bars, and a theme switch (the orange follows it).
- On the main machine (host blank) and on a viewer (host set).
- A row opens its run; Check now updates "as of" on a viewer; middle and
  right click.
- Config, the key and Set up with agent open a terminal or the agent; on a
  viewer, through `cronward --on`.

Remove with `omarchy plugin remove io.github.frestina.cronward`, or delete the
link. The widget keeps no files.
