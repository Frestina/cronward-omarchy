# Putting a workflow on cronward: a guide for coding agents

The user clicked "Set up with agent" in the cronward bar widget. Help them
put a GitHub Actions workflow on cronward, which starts it on a schedule
from their own machine through `workflow_dispatch` and says whether each
run passed. Work with them step by step: they decide what goes in, you do
the looking up and the typing.

The prompt says where cronward runs: on this machine, or on a main machine
reached with `cronward --on <host> <command>`. In the second case, put
`--on <host>` first in every cronward command below. Never ssh there
yourself: `--on` runs only cronward, with the user's own ssh.

## Limits

You may have been started with approvals switched off. Hold yourself to these
regardless:

- **Never handle a token.** Don't ask for one, read one, print one or store
  one. When a token is missing or lacks access, say what the user should do
  (the widget's footer has Token, which opens GitHub's token page, and its
  key button stores one in a terminal) and wait.
- **Change cronward only with its commands**: `cronward add`, `remove`,
  `run`. Don't edit its config by hand; the user can, with Config in the
  widget's footer.
- **A test run is a real run** on GitHub, with whatever the workflow does:
  deploys, releases, messages. Ask before starting one that has effects.
- **The repo is the user's.** Commit and push the workflow change the way
  the repo does it, and ask before pushing when unsure.

## Steps

1. **Check cronward.** Run `cronward status` (with `--on <host>`). If it
   fails, explain the message and stop: cronward needs to be installed and
   set up first (its README, Install).
2. **Pick the workflow.** Ask which repo and workflow, and when it should
   run. `cronward workflows --json` lists the repos and workflows the
   stored tokens reach, and `jobs` names the ones already on cronward. A repo
   that isn't there needs the token's access first: say so (see Limits). If
   the main machine refuses `--json`, its cronward is older:
   `cronward workflows <account>` prints the same as text.
3. **Find the repo's local clone.** Ask the user where it is, or look in
   their usual project folders (`~/Projects`, `~/Work`, `~/src`, `~/code`)
   for a clone whose `git remote get-url origin` is that repo. Don't scan the
   whole disk. With no clone, offer to clone it into a folder the user picks,
   and do so only if they say yes. Work in that clone from here on.
4. **Follow cronward's skill.** If you have the `cronward` skill, use it. If
   not, read it: `skills/cronward/SKILL.md` in cronward's install, found with
   `readlink -f "$(command -v cronward || echo ~/.local/bin/cronward)"`,
   two folders up from `bin/cronward`; or
   <https://github.com/Frestina/cronward/blob/main/skills/cronward/SKILL.md>.
   It covers the rest: adding `workflow_dispatch:`, `cronward add`, a test
   with `cronward run <job> --wait`, and taking out `schedule:` once a run has
   passed. Skip its "Find the machine" section: the prompt already says where
   cronward runs.
5. **Finish with a summary**: the job's name, its schedule and time zone, the
   next slot, the test run's URL, and what you changed in the repo. The
   widget shows the job within a minute; on a laptop, its result arrives with
   the next hourly fetch, or at once with Check now.
