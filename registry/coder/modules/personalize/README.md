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

The agent sets these variables in the environment of every process it starts, including SSH sessions and other startup scripts:

| Variable                           | Default value                             |
| ---------------------------------- | ----------------------------------------- |
| `CODER_MODULE_PERSONALIZE_PATH`    | `~/personalize`                           |
| `CODER_MODULE_PERSONALIZE_DIR`     | `~/personalize.d`                         |
| `CODER_MODULE_PERSONALIZE_LOG_DIR` | `~/.coder-modules/coder/personalize/logs` |

A leading `~/` is replaced with the home directory, so the default values are absolute paths. A dotfiles install script can use them to put its files where this template's Personalize looks for them:

```sh
if [ -n "${CODER_MODULE_PERSONALIZE_DIR:-}" ]; then
  mkdir -p "$CODER_MODULE_PERSONALIZE_DIR"
  ln -sf "$PWD/workspace-services" "$CODER_MODULE_PERSONALIZE_DIR/10-services"
fi
```

Script output goes to `start.log` and `stop.log` in the log directory, and to the Personalize tabs of the agent logs. At every start, the output begins with a short description of the two paths and a link to this page, so a developer can tell from inside the workspace that Personalize is present and how to use it.

## Use a custom path

Set `path` to use a different personalize script. The drop-in directory is always `<path>.d`. The path cannot contain `$` or a newline.

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
- A `path` that contains `$` is rejected.
- Add `phase = "start"` to an existing `coder_script_order` rule that selects `module.personalize`. Without it, template import fails.

Existing `~/personalize` scripts keep running at start with no arguments.
