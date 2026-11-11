---
display_name: Personalize
description: Allow developers to customize their workspace at start and stop
icon: ../../../../.icons/personalize.svg
verified: true
tags: [helper, personalize]
---

# Personalize

Personalize runs scripts that each developer keeps in their own home directory when a Coder workspace starts and when it stops. Developers can install personal tools, or start and stop their own services, without changing the shared template.

```tf
module "personalize" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/personalize/coder"
  version  = "2.0.0"
  agent_id = coder_agent.main.id
}
```

The workspace image must have bash.

## The personalize script

`~/personalize` runs at every workspace start, with no arguments. Keep its commands idempotent.

```sh
cat > ~/personalize << 'EOF'
#!/usr/bin/env bash

command -v jq >/dev/null 2>&1 || echo "Install jq for this workspace"
EOF
chmod +x ~/personalize
```

## Drop-in scripts

Executable files in `~/personalize.d` run at start and at stop. Each one receives a single argument, `start` or `stop`.

```sh
mkdir -p ~/personalize.d
cat > ~/personalize.d/10-cache << 'EOF'
#!/usr/bin/env bash

case "$1" in
  start) mkdir -p "$HOME/.cache/my-tool" ;;
  stop) rm -f "$HOME/.cache/my-tool/session.lock" ;;
esac
EOF
chmod +x ~/personalize.d/10-cache
```

- At start, drop-in scripts run after the personalize script, in byte order of their names: `10-cache` runs before `20-server`.
- At stop, drop-in scripts run in reverse order. The personalize script does not run at stop.
- A file runs when it is a regular file and executable. Hidden files and names that end in `~` are skipped.
- A script that fails does not stop the others. Personalize exits with the exit code of the first script that failed. At start, that puts the agent in `start_error`.

The start script blocks login until every script has finished.

A script that launches a background process at start must detach it and redirect its output:

```sh
nohup my-tool < /dev/null > "$HOME/.cache/my-tool/output.log" 2>&1 &
```

The agent waits for the script's output to close and reports a failure if a background process keeps it open.

### Stop is best effort

Stop scripts run when the agent receives a termination signal. The agent waits for them, but the infrastructure can end the agent first, so do not rely on them to save essential data.

With the Docker example template, short stop scripts ran to completion in testing without `destroy_grace_seconds`. Give longer scripts a grace period on the workspace resource.

## Find the paths and logs

At every start, Personalize writes the paths it uses to `~/.coder-modules/coder/personalize/config`:

```sh
PERSONALIZE_PATH=/home/coder/personalize
PERSONALIZE_DIR=/home/coder/personalize.d
PERSONALIZE_LOG_DIR=/home/coder/.coder-modules/coder/personalize/logs
```

The file is shell syntax, written with bash `printf %q`, so a script can source it. `sh` and bash both read it; a path with non-ASCII characters can require bash.

The agent also sets `PERSONALIZE_PATH` in the environment of every process it starts. Use the variable in a script that runs during workspace start, such as a dotfiles install script, because the config file is written when Personalize runs, which can be after that script:

```sh
if [ -n "${PERSONALIZE_PATH:-}" ]; then
  mkdir -p "$PERSONALIZE_PATH.d"
  ln -sf "$PWD/workspace-services" "$PERSONALIZE_PATH.d/10-services"
fi
```

`PERSONALIZE_PATH` is not set when `path` contains `$`, because the agent expands `$` in environment values.

Script output goes to `logs/start.log` and `logs/stop.log` in `~/.coder-modules/coder/personalize/`.

## Use a custom path

Set `path` to use a different personalize script. The drop-in directory is always `<path>.d`.

```tf
module "personalize" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/personalize/coder"
  version  = "2.0.0"
  agent_id = coder_agent.main.id

  path = "~/.init" # The drop-in directory is ~/.init.d.
}
```

## Run after dotfiles

Scripts from different modules start concurrently. To run Personalize after the dotfiles module has finished, add a rule to the template:

```tf
data "coder_script_order" "personalize_after_dotfiles" {
  rule {
    phase = "start"
    run   = ["module.personalize"]
    after = ["module.dotfiles"]
  }
}
```

This needs Coder 2.39.0 or later on the server, provisioners and agents, and Coder Terraform provider 2.20.0 or later. Older versions ignore the rule without an error. The rule needs `phase` because Personalize has a start script and a stop script.

## Upgrade from v1

- Remove the `log_path` argument. Logs are now in `~/.coder-modules/coder/personalize/logs/`.
- Use Coder Terraform provider 0.13.0 or later.
- Add `phase = "start"` to an existing `coder_script_order` rule that selects `module.personalize`. Without it, template import fails.

Existing `~/personalize` scripts keep running at start with no arguments.
