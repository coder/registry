---
display_name: Personalize
description: Allow developers to customize their workspace at start and stop
icon: ../../../../.icons/personalize.svg
verified: true
tags: [helper, personalize]
---

# Personalize

Personalize runs developer-managed scripts when a workspace starts or stops. The workspace image needs bash, as in v1.

```tf
module "personalize" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/personalize/coder"
  version  = "2.0.0"
  agent_id = coder_agent.main.id
}
```

## Add your scripts

The personalize script at `~/personalize` runs at start with no arguments. Keep its commands idempotent because it runs on every start:

```sh
cat > ~/personalize << 'EOF'
#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || echo "Install jq for this workspace"
EOF
chmod +x ~/personalize
```

Executable drop-in scripts in `~/personalize.d` receive one argument, `start` or `stop`:

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

At start, Personalize runs the personalize script, then drop-in scripts in byte order. At stop, it runs only drop-in scripts, in reverse order. User scripts retain the caller's locale. Only executable regular files run; hidden files and names ending in `~` are skipped. A non-executable regular file produces a notice. Everything else is skipped silently, and a missing drop-in directory is not an error.

Personalize prints a creation hint only when both paths are absent, and an executable-permission notice for a non-executable personalize script. Drop-in-only users get no hint. Set `path` to use a different personalize script; the drop-in directory is always `<path>.d`, so `path = "~/.init"` uses `~/.init.d`. Paths cannot contain newlines or carriage returns.

A failed script does not prevent remaining drop-ins from running. Personalize prints its path and exit code and returns the first failing script's exit code, or 0. The start script blocks login until it finishes; a failure puts the agent in `start_error`.

If a start script launches a background process, detach it and redirect its output, for example `nohup my-tool </dev/null >"$HOME/.cache/my-tool/start.log" 2>&1 &`. The agent waits for script output pipes to close and reports failure if a background process keeps them open beyond its wait limit.

### Stop is best effort

Stop scripts run when the agent receives a termination signal. The agent waits for them, but infrastructure can end the agent first. The module sets no stop timeout; do not rely on these scripts for essential data persistence or supervising services.

In local testing with the stock Docker example template and Docker provider 4.7.0, two short drop-in scripts completed in reverse order and wrote to `logs/stop.log` without an explicit `destroy_grace_seconds`. This does not guarantee that longer scripts finish; set a suitable infrastructure grace period.

## Find configuration and logs

At each start, Personalize writes `~/.coder-modules/coder/personalize/config` through a temporary file and rename. A failed write only warns; user scripts still run. For the default path, the file contains:

```sh
PERSONALIZE_PATH=/home/coder/personalize
PERSONALIZE_DIR=/home/coder/personalize.d
PERSONALIZE_LOG_DIR=/home/coder/.coder-modules/coder/personalize/logs
```

Values use bash `printf %q`: spaces and ASCII punctuation that the shell treats specially are backslash-escaped, so `sh` and bash read them back, except that bash 3.2 does not escape `~`. Other characters can require bash to read the file, depending on the locale. Source it with `. "$HOME/.coder-modules/coder/personalize/config"` after a successful start.

The agent also exports `PERSONALIZE_PATH`, replacing a leading `~/` with the user's home directory, unless `path` contains `$`. The agent would expand dollar signs in that value, so those paths use the config file only. The environment value is available before Personalize runs, but the config file is not; explicitly order scripts that depend on files created by one another.

Output goes to `~/.coder-modules/coder/personalize/logs/start.log` and `~/.coder-modules/coder/personalize/logs/stop.log`.

## Run after dotfiles

To run Personalize after dotfiles finishes successfully:

```tf
data "coder_script_order" "personalize_after_dotfiles" {
  rule {
    run   = ["module.personalize"]
    after = ["module.dotfiles"]
    phase = "start"
  }
}
```

This requires Coder 2.39.0 or later on the control plane, provisioners, and agents, and Coder Terraform provider 2.20.0 or later. Older components can ignore ordering declarations. Module-only rules need `phase` because Personalize contains both start and stop scripts. Terraform `depends_on` does not order script execution inside the agent.

## Upgrade from v1

Remove the unsupported `log_path` argument; logs now use the module's `logs/start.log` and `logs/stop.log`. Existing personalize scripts still run at start with no arguments. Use Coder Terraform provider 0.13.0 or later for `coder_env`.

Add `phase = "start"` to existing `coder_script_order` rules that select `module.personalize` without a phase, or template import fails.
