---
display_name: Personalize
description: Allow developers to customize their workspace at start and stop
icon: ../../../../.icons/personalize.svg
verified: true
tags: [helper, personalize]
---

# Personalize

Personalize runs developer-managed scripts when a Coder workspace starts or stops. It lets each developer install personal tools or configure their environment without changing the shared Coder template.

The default configuration runs `~/personalize` at workspace start with no arguments. Executable files in `~/personalize.d` receive `start` at workspace start and `stop` at workspace stop.

```tf
module "personalize" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/personalize/coder"
  version  = "2.0.0"
  agent_id = coder_agent.main.id
}
```

## Create the personalize script

Create the script inside the workspace and make it executable. Keep startup commands idempotent because Coder runs the script on every workspace start.

```sh
cat > ~/personalize << 'EOF'
#!/usr/bin/env sh

command -v jq >/dev/null 2>&1 || echo "Install jq for this workspace"
EOF
chmod +x ~/personalize
```

If the script is missing or is not executable, Personalize prints instructions and continues to the drop-in scripts. The `~/personalize` script itself never runs at stop, so existing scripts keep working unchanged.

## Add start and stop scripts

Create executable init scripts in `~/personalize.d`. Each script receives exactly one argument, either `start` or `stop`:

```sh
mkdir -p ~/personalize.d
cat > ~/personalize.d/10-cache << 'EOF'
#!/usr/bin/env sh

case "$1" in
  start) mkdir -p "$HOME/.cache/my-tool" ;;
  stop) rm -f "$HOME/.cache/my-tool/session.lock" ;;
esac
EOF
chmod +x ~/personalize.d/10-cache
```

At start, Personalize runs `~/personalize` first, then the drop-in scripts in bytewise lexical order (`LC_ALL=C`). At stop, it runs only the drop-ins, in reverse order. For example, `10-cache` runs before `20-setup` at start and after it at stop.

Only executable regular files run. Hidden files, directories, and filenames ending in `~` are skipped. Non-executable files are skipped with a notice. Names such as `10-cache.sh` are allowed. A missing drop-in directory is not an error.

A script failure does not prevent later scripts from running. Personalize prints the failed script's path and exit code and returns the first non-zero exit code after running the remaining scripts. A start failure puts the agent in `start_error`. The start script blocks login until it finishes.

### Stop is best effort

Stop scripts run when the agent receives a termination signal. The agent waits for its stop scripts during shutdown, but the infrastructure can terminate it before they finish. Do not rely on stop scripts for essential data persistence, and do not use them to supervise services. The module sets no stop timeout.

In local testing with the stock Docker example template and Docker provider 4.7.0, two short stop scripts completed in reverse order and wrote their output to `logs/stop.log` without an explicit `destroy_grace_seconds`. They also completed with `destroy_grace_seconds = 30` on the template's `docker_container`. Set a suitable infrastructure grace period for your scripts; these results do not guarantee that longer scripts will finish.

## Find configuration and logs

At every start, Personalize writes `~/.coder-modules/coder/personalize/config` atomically. It contains absolute paths as shell-quoted `KEY=value` assignments:

```sh
PERSONALIZE_PATH='/home/coder/personalize'
PERSONALIZE_DIR='/home/coder/personalize.d'
PERSONALIZE_LOG_DIR='/home/coder/.coder-modules/coder/personalize/logs'
```

Read it in a shell script with:

```sh
. "$HOME/.coder-modules/coder/personalize/config"
```

The agent also exports `PERSONALIZE_PATH` through `coder_env`, so dotfiles and other agent-started processes can discover the module before its start script runs. A leading `~` becomes the workspace user's home directory. If the configured `path` contains `$`, the module omits this environment variable because the agent would expand it. Use the config file for these paths. The file is available only after Personalize starts; order dotfiles and Personalize explicitly if one needs files created by the other.

Script output goes to `~/.coder-modules/coder/personalize/logs/start.log` and `~/.coder-modules/coder/personalize/logs/stop.log`.

## Use custom paths

Set `path` when the script is stored elsewhere. The drop-in directory is always `<path>.d`: for example, `path = "~/.init"` uses `~/.init.d`. Paths cannot contain newlines or carriage returns.

```tf
module "personalize" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/personalize/coder"
  version  = "2.0.0"
  agent_id = coder_agent.main.id

  path = "/home/coder/scripts/personalize workspace.sh"
}
```

The module runs scripts as the workspace user. It does not download software or require `sudo`; any network access or elevated privileges come from commands the developer places in their own scripts.

## Run after dotfiles

If your template already uses `module "dotfiles"`, add this rule beside the module calls to run Personalize after dotfiles finishes successfully:

```tf
data "coder_script_order" "personalize_after_dotfiles" {
  rule {
    run   = ["module.personalize"]
    after = ["module.dotfiles"]
    phase = "start"
  }
}
```

This requires Coder 2.39.0 or later on the control plane, provisioners, and workspace agents, and the Coder Terraform provider 2.20.0 or later. Older Coder components can ignore ordering declarations. Module-only rules need an explicit `phase` because Personalize now contains both a start script and a stop script. Terraform `depends_on` does not order script execution inside the agent.

## Upgrade from v1

Remove `log_path` from module calls before upgrading to v2. The variable is no longer supported, and logs now use the module directory's `logs/start.log` and `logs/stop.log` instead of `~/personalize.log` or a custom location. Existing `~/personalize` scripts still run at start with no arguments; no script changes are required.
