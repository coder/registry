---
display_name: Personalize
description: Allow developers to customize their workspace at start and stop
icon: ../../../../.icons/personalize.svg
verified: true
tags: [helper, personalize]
---

# Personalize

Personalize runs developer-managed scripts when a Coder workspace starts or stops. It lets each developer install personal tools or configure their environment without changing the shared Coder template.

The personalize script at `~/personalize` runs at workspace start with no arguments. Executable drop-in scripts in `~/personalize.d` receive `start` at workspace start and `stop` at workspace stop.

```tf
module "personalize" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/personalize/coder"
  version  = "2.0.0"
  agent_id = coder_agent.main.id
}
```

## Create the personalize script

Create the personalize script inside the workspace and make it executable. Keep startup commands idempotent because Coder runs the script on every workspace start.

```sh
cat > ~/personalize << 'EOF'
#!/usr/bin/env sh

command -v jq >/dev/null 2>&1 || echo "Install jq for this workspace"
EOF
chmod +x ~/personalize
```

If the personalize script is missing or is not executable, Personalize prints instructions and continues to the drop-in scripts. The personalize script never runs at stop, so existing personalize scripts keep working unchanged.

## Add drop-in scripts

Create executable drop-in scripts in `~/personalize.d`. Their contract is exactly one argument, either `start` or `stop`:

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

At start, Personalize runs the personalize script first, then the drop-in scripts in bytewise lexical order (`LC_ALL=C`). The C locale applies only to filename ordering; user scripts retain the caller's locale. At stop, it runs only the drop-in scripts, in reverse order. For example, `10-cache` runs before `20-setup` at start and after it at stop.

If a drop-in script launches a background process for `start`, detach the process and redirect its output, for example `nohup my-tool </dev/null >"$HOME/.cache/my-tool/start.log" 2>&1 &`. The agent waits for the script's output pipes to close and reports failure if a background process keeps them open beyond its wait limit.

Only executable regular files run as drop-in scripts. Hidden files, directories, and filenames ending in `~` are skipped. Non-executable files and broken symlinks are skipped with a notice. An existing drop-in directory that cannot be read or searched produces one notice. Names such as `10-cache.sh` are allowed. A missing drop-in directory is not an error.

A failure of the personalize script or a drop-in script does not prevent remaining drop-in scripts from running. Personalize prints the failed script's path and exit code and returns the first non-zero exit code after running the remaining drop-in scripts. A start failure puts the agent in `start_error`. The module's start script blocks login until it finishes.

### Stop is best effort

Drop-in scripts receive `stop` when the agent receives a termination signal. The agent waits for the module's stop script during shutdown, but the infrastructure can terminate it before the drop-in scripts finish. Do not rely on drop-in scripts for essential data persistence or for supervising services. The module sets no stop timeout.

In local testing with the stock Docker example template and Docker provider 4.7.0, two short drop-in scripts received `stop`, completed in reverse order, and wrote their output to `logs/stop.log` without an explicit `destroy_grace_seconds`. They also completed with `destroy_grace_seconds = 30` on the template's `docker_container`. Set a suitable infrastructure grace period for your drop-in scripts; these results do not guarantee that longer drop-in scripts will finish.

## Find configuration and logs

At every start, Personalize attempts to replace `~/.coder-modules/coder/personalize/config` atomically. If writing the config file fails, Personalize warns and still runs user scripts. The config file contains absolute paths as shell-quoted `KEY=value` assignments:

```sh
PERSONALIZE_PATH='/home/coder/personalize'
PERSONALIZE_DIR='/home/coder/personalize.d'
PERSONALIZE_LOG_DIR='/home/coder/.coder-modules/coder/personalize/logs'
```

Read it in a shell script with:

```sh
. "$HOME/.coder-modules/coder/personalize/config"
```

The agent also exports `PERSONALIZE_PATH` through `coder_env` when `path` is absolute or starts with `~/` and contains no `$`. For `~/`, the value uses the workspace user's home directory. This lets dotfiles and other agent-started processes discover the module before its start script runs. Other paths use the config file only: relative paths need runtime resolution, and the agent would expand `$` in an environment value. The config file is available only after Personalize starts and writes it successfully; order dotfiles and Personalize explicitly if one needs files created by the other.

Script output goes to `~/.coder-modules/coder/personalize/logs/start.log` and `~/.coder-modules/coder/personalize/logs/stop.log`.

## Use custom paths

Set `path` when the personalize script is stored elsewhere. The drop-in directory is always `<path>.d`: for example, `path = "~/.init"` uses `~/.init.d`. Paths cannot be empty, be only `~`, end with `/`, or contain newlines or carriage returns.

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

Remove `log_path` from module calls before upgrading to v2. The variable is no longer supported, and logs now use the module directory's `logs/start.log` and `logs/stop.log` instead of `~/personalize.log` or a custom location. Existing personalize scripts still run at start with no arguments; no script changes are required.

Use Coder Terraform provider 0.13.0 or later; v2 needs its `coder_env` resource.

If an existing `coder_script_order` rule selects `module.personalize` without `phase`, add `phase = "start"`. The module now contains both a start script and a stop script, so a rule without an explicit phase fails template import.
