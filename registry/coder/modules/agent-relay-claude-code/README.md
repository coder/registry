---
display_name: Agent Relay Claude Code
description: Serves Claude Code self-hosted runner sessions in Coder workspaces that Agent Relay dispatches.
icon: ../../../../.icons/claude.svg
verified: true
tags: [agent, claude, agent-relay]
---

# Agent Relay Claude Code

Makes a Coder template a target for [Agent Relay](https://coder.com/docs/ai-coder/agent-relay)
Claude Code pools. Agent Relay dispatches Claude Code sessions to workspaces
built from the template; the module declares the parameters the relay stamps
on each build and runs the Claude Code self-hosted runner.

```tf
module "claude_code_runner" {
  source   = "registry.coder.com/coder/agent-relay-claude-code/coder"
  version  = "1.0.1"
  agent_id = coder_agent.main.id

  # Downloads the Claude Code CLI at start when it is not in the image. Bake
  # the CLI into the image and set this to false for faster workspaces.
  install_cli = true
}

resource "coder_agent" "main" {
  # ...
  metadata {
    key          = "agent_relay_status"
    display_name = "Session"
    script       = module.claude_code_runner.status_metadata_script
    interval     = 10
    timeout      = 5
  }

  metadata {
    key          = "agent_relay_session_attached"
    display_name = "Session attached"
    script       = module.claude_code_runner.session_attached_metadata_script
    interval     = 30
    timeout      = 5
  }
}
```

The `agent_relay_status` metadata block is required. It has to live on the
`coder_agent`, which the module cannot declare; the relay reads it to decide
when to reap the workspace. The `agent_relay_session_attached` block is
optional; see [Session attachment](#session-attachment).

## Requirements

- Coder 2.39.0 or newer and Agent Relay v0.14.0 or newer. On those versions
  the relay delivers the work order as an ephemeral workspace secret, which
  the agent injects as `SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET`; it is never a
  build parameter. A relay that still sends it as the `agent_relay_credential`
  parameter refuses to serve a template on this version with
  `missing parameter "agent_relay_credential"`, so on older versions pin
  `0.5.0`, the last release that declares the parameter. Upgrade Coder, then
  Agent Relay, then move templates to `1.0.0` one at a time; a `0.5.0`
  template keeps working on the new versions, except that its `dispatched`
  output reads `false` on relay builds. To roll a relay or Coder back, pin
  templates back to `0.5.0` first.
- The `claude` CLI must be in the workspace. `install_cli` (default `true`)
  downloads it at start only when it is not already on PATH; bake it into the
  image for the fastest start. `cli_binary` overrides the path.
- Builds must finish inside the pool's `dispatch_deadline` (default 5m, max
  15m), counted from the work order's issue: pre-pulled images, no
  persistent volumes.

## Start the runner after your setup

The start step runs as one of the agent's start scripts. Without an
ordering rule, every start script runs at once, so the runner can take
a session while your template is still cloning a repository or installing
tools. The module cannot wait for the agent to be `ready`: its own start
script is one of the scripts the agent waits on.

Order the module after your setup in the template, with a
`coder_script_order` rule. The module cannot declare this rule for you,
because a rule can only select scripts in its own module, so it lives
beside the module call:

```tf
resource "coder_script" "setup" {
  agent_id     = coder_agent.main.id
  display_name = "Workspace setup"
  run_on_start = true
  timeout      = 120
  script       = file("${path.module}/setup.sh")
}

data "coder_script_order" "relay_runner" {
  rule {
    phase = "start"
    run   = ["module.claude_code_runner"]
    after = ["coder_script.setup"]
  }
}
```

- Script ordering needs Coder 2.39.0 or newer on the control plane, the
  provisioners and the workspace agents, and the Coder provider 2.20.0 or
  newer. Older Coder ignores the rule without an error and the runner
  starts right away.
- `coder_agent.startup_script` cannot be ordered. Put setup the runner
  depends on in `coder_script` resources or modules, including a step that
  installs the CLI (set `install_cli = false` and order the module after it).
- With the default `requires = "success"`, a failed setup script skips
  this module and the runner never starts. Agent Relay newer than 0.15.0
  fails the session about a minute after the agent reports the failure;
  0.15.0 and older wait out the startup grace and then report that the
  runner never started. Set `requires = "completion"` to start the runner
  anyway.
- While the rule holds the start step, `agent_relay_status` reads `pending`.
  The pool's `dispatch_deadline` from Requirements (default 5 minutes, at
  most 15) is counted from the work order's issue and covers the build,
  setup and runner start together. When the runner is not up within it,
  Anthropic redelivers the work order and Agent Relay rebuilds the
  workspace, which reruns setup, so a template that cannot fit is rebuilt
  on every delivery and never serves. Keep the setup `timeout` well under
  the deadline, or raise `dispatch_deadline` first.
- Setup runs again when a prebuilt workspace is claimed, and the rule holds
  the runner until it finishes. Write setup so it skips work already done,
  for example `test -d ~/repo/.git || git clone ...`. Until setup finishes,
  `agent_relay_status` still shows the prebuild's `idle`, not `pending`, and
  a setup that fails on a claim leaves it at `idle`, which Agent Relay
  neither reaps nor reports.
- A `cli_binary` wrapper that waits for setup is not needed; the rule does
  the waiting.

The full example is in the Agent Relay repository under
[`example/templates/claude-code`](https://github.com/coder/agent-relay/tree/main/example/templates/claude-code).

## Additional runner arguments

Use `additional_args` to pass extra arguments to `claude self-hosted-runner`, as a
list with one element per argument. They are appended after the flags the module sets and before `--exec-path`, in the order written.
Each element is passed exactly as written, so a flag can repeat and a value
can contain spaces or quotes without escaping. Flags the module already sets
(`--capacity`, `--base-dir`, `--exit-if-unused-min`, `--release-idle-session-min`, `--health-port`, `--exec-path`) are rejected, with or without `=value`.

```tf
module "claude_code_runner" {
  source          = "registry.coder.com/coder/agent-relay-claude-code/coder"
  version         = "1.0.1"
  agent_id        = coder_agent.main.id
  additional_args = ["--some-flag", "value", "--some-flag", "another value", "--another-flag"]
}
```

## Parameters

Agent Relay verifies this contract against the template's active version at
startup and refuses to serve a pool that does not satisfy it. Every parameter
renders disabled with a "Set by Agent Relay on dispatch" placeholder. The
work order is not among them: it is a workspace secret, so it never appears
in the build's parameters or Terraform state, and the template should not
set `SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET` itself.

`agent_relay_client_platform` is attribution rather than contract: the relay
stamps the surface the session was created from (`web_claude_ai`,
`claude_in_slack`, `desktop_app`, ...) and the module exposes it to the
workspace as `AGENT_RELAY_CLIENT_PLATFORM` and as the `client_platform`
output, so a template can vary its setup by origin. A relay that predates the
parameter leaves it empty.

## Scripts and logs

The module runs three ordered startup steps through [coder-utils](https://registry.coder.com/modules/coder/coder-utils):
a pre-install step that stops any previous supervisor and runner and clears status,
an install step that downloads the CLI when `install_cli` is set and the
binary is missing (a no-op otherwise), then a start step that launches the
runner. A separate `run_on_stop` script uses the same cleanup source on graceful
workspace stop. Everything lands under `$HOME/.coder-modules/coder/agent-relay-claude-code`:

| path            | contents                                               |
| --------------- | ------------------------------------------------------ |
| `scripts/*.sh`  | the pre-install, install and start scripts as they ran |
| `logs/*.log`    | output of each step, plus the runner's own log         |
| `runner-state`  | the supervisor's lifecycle line (`state_file`)         |
| `supervisors/`  | identity records for live supervisors                  |
| `workers/`      | identity records for runners, even without supervisors |
| `started/`      | one start claim per cleanup generation                 |
| `run-runner.sh` | runner identity wrapper before CLI startup             |
| `supervise.sh`  | the detached supervisor that owns the runner           |
| `wrapper.sh`    | session wrapper that forces `bypassPermissions`        |

## Runner lifecycle

The start step launches `claude self-hosted-runner --capacity 1 --exit-if-unused-min 10 --release-idle-session-min 60` detached and exits,
so the agent reaches `ready` immediately. The runner is wrapped so every
session runs with `--permission-mode bypassPermissions`; there is no terminal
attached, so an approval prompt would hang it. When the runner exits, Agent
Relay deletes the workspace; when it fails, the relay nacks the work order.
A runner that is never assigned its session exits after `exit_if_unused_min`
minutes (default 10, 0 to disable), so a dispatch that never arrives is reaped
rather than reporting `working` forever.

A graceful workspace stop uses a separate script to stop the supervisor and
runner and clear their state. It waits up to 10 seconds after `TERM`, then up
to 5 seconds after `KILL`. Allow at least 30 seconds for the container or pod
to terminate so this script and the agent can finish shutting down. A forced
stop may skip the hook; startup cleanup still runs on the next agent start.

Startup cleanup is availability-first: if it cannot verify that a previous
process stopped, it logs a warning and starts a fresh runner anyway. Two
runners may then run concurrently, and a surviving old supervisor can race
to write stale status. It never signals a process whose recorded
PID, boot ID, and process start time do not match. The start step can launch
only once per cleanup generation; without a new work order it reports `idle`
instead of the previous run's status.

The reaper still needs a short grace after a new build to avoid acting on old
metadata before cleanup runs and fresh status has been collected.

`agent_relay_status` reports one of:

| value             | meaning                                                                    |
| ----------------- | -------------------------------------------------------------------------- |
| `pending`         | no state recorded yet                                                      |
| `idle`            | no work order in this build: created by a person, or restarted by one      |
| `working`         | runner alive, no session picked up                                         |
| `serving`         | runner alive, session picked up (best effort, see `serving_log_pattern`)   |
| `orphaned`        | runner process gone without recording an exit                              |
| `done <code>`     | runner exited with that status; `137` means it was killed                  |
| `failed <reason>` | runner could not start, e.g. `runner-agent-missing` when the CLI is absent |

Renaming the `agent_relay_status` key breaks reaping.

## Idle session release

An attached session whose user sends nothing for 60 minutes is released: the
runner parks the session server-side and exits, and Agent Relay deletes the
workspace. The user's next message resumes the session on a fresh runner.
This is the CLI's `--release-idle-session-min`.

`release_idle_session_min` sets the template's default, from `0` to `10080`
minutes. Agent Relay can override it per build by stamping the
`agent_relay_claude_code_release_idle_session_min` parameter, whose default is
the variable, so a relay that does not stamp it gets the template's value. `0`
omits the flag and keeps the CLI's default of never releasing. The value
reaches the runner through the environment, and a value outside the range
fails the start step with `failed invalid-release-idle-session-min`.

```tf
module "claude_code_runner" {
  source                   = "registry.coder.com/coder/agent-relay-claude-code/coder"
  version                  = "1.0.1"
  agent_id                 = coder_agent.main.id
  release_idle_session_min = 30
}
```

## Session attachment

The runner serves `GET /healthz` and `GET /metrics` on `health_port`
(default `3286`, chosen over the CLI's `8080` to avoid common clashes). The `/healthz` body carries `active_sessions`, the number
of sessions the runner holds, including between turns.
`session_attached_metadata_script` reads it over loopback and prints one of:

| value        | runner running | session held | meaning                                                            |
| ------------ | -------------- | ------------ | ------------------------------------------------------------------ |
| `attached`   | yes            | yes          | holds a session, including between turns                           |
| `unattached` | yes            | no           | waiting for its first session, or released one and is still alive  |
| `stopped`    | no             | no           | exited, died, never started, or the workspace was created manually |
| `disabled`   | not checked    | not checked  | `health_port` is `0`, so the listener is off and nothing is read   |
| error        | yes            | unknown      | `/healthz` cannot be read or has no numeric `active_sessions`      |

Running means the pid the supervisor recorded in `runner-state` is alive
(`kill -0`) and its command line is still the CLI. The supervisor writes
`working <pid>` when it starts the runner and `done <code>` when it exits,
so a clean exit, a crash, and a reused pid all read as `stopped`.

An error is a non-zero exit, so the metadata sample carries an error
rather than a value and a consumer can tell unknown from any state above.
The listener starts only after the runner registers, so a fresh runner
reports an error briefly. The image needs `curl`.

The CLI binds the listener on every interface and has no bind-host option.
Do not publish `health_port` through a `coder_app`, a container port, or a
Kubernetes Service, and make sure the workspace network keeps other hosts
from reaching it.

```tf
module "claude_code_runner" {
  source      = "registry.coder.com/coder/agent-relay-claude-code/coder"
  version     = "1.0.1"
  agent_id    = coder_agent.main.id
  health_port = 3290
}
```
