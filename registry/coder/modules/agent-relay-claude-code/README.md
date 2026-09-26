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
  version  = "0.2.0"
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
}
```

Each runner registers with a label the Anthropic console shows beside it,
defaulting to `<owner>/<workspace>` so it is identifiable whether or not the
template sets a hostname. `client_label` overrides it. The label is display
only: it never affects authorization, and it cannot steer which sessions a
runner is assigned — routing is per environment, and one pool is one
environment.

The `agent_relay_status` metadata block is required. It has to live on the
`coder_agent`, which the module cannot declare; the relay reads it to decide
when to reap the workspace.

## Requirements

- The `claude` CLI must be in the workspace. `install_cli` (default `true`)
  downloads it at start only when it is not already on PATH; bake it into the
  image for the fastest start. `cli_binary` overrides the path.
- Builds must finish inside Agent Relay's 300s spawn budget: pre-pulled
  images, no persistent volumes.
- The compute resource must give the workspace time to shut down. Wire
  `shutdown_grace_seconds` into it; without that the runner is killed
  mid-session. See [Graceful shutdown](#graceful-shutdown).

## Parameters

Agent Relay verifies this contract against the template's active version at
startup and refuses to serve a pool that does not satisfy it. Every parameter
renders disabled with a "Set by Agent Relay on dispatch" placeholder; the
credential is masked.

## Scripts and logs

The module runs two steps through [coder-utils](https://registry.coder.com/modules/coder/coder-utils):
an install step that downloads the CLI when `install_cli` is set and the
binary is missing (a no-op otherwise), then a start step that launches the
runner. Everything lands under `$HOME/.coder-modules/coder/agent-relay-claude-code`:

| path           | contents                                        |
| -------------- | ----------------------------------------------- |
| `scripts/*.sh` | the install and start scripts as they ran       |
| `logs/*.log`   | output of each step, plus the runner's own log  |
| `runner-state` | the supervisor's lifecycle line (`state_file`)  |
| `supervise.sh` | the detached supervisor that owns the runner    |
| `wrapper.sh`   | session wrapper that forces `bypassPermissions` |

The stop step is a plain `coder_script` rather than a coder-utils step, so its
output goes to the agent's own script log, not to `logs/` above.

## Environment

The module always passes `--capacity`, `--base-dir`, `--exec-path` and
`--client-label`, passes `--exit-if-unused-min` and
`--push-outcome-on-release` unless you turn them off, passes
`--drain-wait-sec` when you set it, and sets
`SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET` and
`SELF_HOSTED_RUNNER_LOCK_TO_ACCOUNT` from the parameters the relay stamps.
Anything else the CLI accepts can be set by the template, because the
supervisor inherits the agent's environment:

```tf
resource "coder_env" "hooks_dir" {
  agent_id = coder_agent.main.id
  name     = "SELF_HOSTED_RUNNER_HOOKS_DIR"
  value    = "/etc/claude-hooks"
}
```

Three things to know before relying on that:

- **A flag beats its paired environment variable.** Setting
  `SELF_HOSTED_RUNNER_BASE_DIR` against the module's own `--base-dir` does
  nothing; use the `base_dir` input instead. The same applies to every flag
  the module emits, including the optional ones once you enable them — so
  `SELF_HOSTED_RUNNER_CLIENT_LABEL` has no effect and `client_label` is the
  only way to change the label.
- **Duration environment variables are milliseconds**, while the CLI flags
  they pair with are seconds or minutes, and the names do not always mirror:
  `--exit-if-unused-min` pairs with `SELF_HOSTED_RUNNER_IDLE_SHUTDOWN_MS`.
- **Not every flag has an environment variable.** `--capacity` is one, and
  it is reserved anyway: Agent Relay's one-workspace-per-session model
  depends on it being 1.

Run `claude self-hosted-runner --help` for what your CLI actually accepts;
the pairings above are the CLI's contract, not this module's, and move with
it.

## Runner lifecycle

The start step launches `claude self-hosted-runner` detached and exits,
so the agent reaches `ready` immediately. The runner is wrapped so every
session runs with `--permission-mode bypassPermissions`; there is no terminal
attached, so an approval prompt would hang it. When the runner exits, Agent
Relay deletes the workspace; when it fails, the relay nacks the work order.
A runner that is never assigned its session exits after `exit_if_unused_min`
minutes (default 10, 0 to disable), so a dispatch that never arrives is reaped
rather than reporting `working` forever.

`agent_relay_status` reports one of:

| value             | meaning                                                                    |
| ----------------- | -------------------------------------------------------------------------- |
| `pending`         | no state recorded yet                                                      |
| `idle`            | no credential: workspace was created manually                              |
| `working`         | runner alive, no session picked up                                         |
| `serving`         | runner alive, session picked up (best effort, see `serving_log_pattern`)   |
| `orphaned`        | runner process gone without recording an exit                              |
| `done <code>`     | runner exited with that status; `137` means it was killed                  |
| `failed <reason>` | runner could not start, e.g. `runner-agent-missing` when the CLI is absent |

Renaming the `agent_relay_status` key breaks reaping.

## Graceful shutdown

The start step detaches the supervisor with `setsid`, so it lives in its own
session and never receives the SIGTERM the container's init gets on shutdown.
The module therefore registers a stop script that relays the signal to the
runner and waits for the supervisor to record `done <code>`. It sends SIGTERM
only, never escalates, and never writes the state file.

That half only works if the platform gives the workspace time to use it, which
the module cannot arrange: it owns no compute resource. Wire the exported
budget into the one the template owns.

```tf
resource "docker_container" "workspace" {
  # ...
  destroy_grace_seconds = module.claude_code_runner.shutdown_grace_seconds
}
```

On Kubernetes the equivalent is the pod spec's
`termination_grace_period_seconds`.

**Skip it and the drain never happens.** The Docker provider destroys the
container with a zero stop timeout unless `destroy_grace_seconds` is set, so
the container is killed before the stop script can finish: the session is
never released server-side, the post-session hook never runs, and in-flight
commits are lost. Kubernetes defaults to 30s, which is below the runner's own
budget. The value is a ceiling rather than a fixed wait, so a workspace whose
runner has already finished still stops immediately.

The budget is the runner's advertised 80s to stop the Claude process and run
the post-session hook, plus 20s for a session release already in flight, plus
the 5s the agent spends shutting down SSH first:

It comes to 105 seconds by default. Turning on the outcome push adds its 30
seconds, and every second of `drain_wait_sec` is added on top — so both
together at `drain_wait_sec = 60` make it 195.

`push_outcome_on_release` pushes the session's outcome branch to `origin`
before the branch is deleted, so commits survive an ephemeral workspace and a
resumed session continues from them. Without it, work an incomplete session had
already committed dies with the container.

It is off by default, so upgrading changes nothing until you ask for it. Turn
it on deliberately: it fires on every runner-initiated incomplete end, not only
a drain — idle-release and failed sessions push too — so the workspace needs
git auth and those sessions leave branches behind.

`drain_wait_sec` is off by default. It buys "the current turn may finish", at
a second of grace period per second of wait, which is the most expensive part
of the budget.

The budget only counts what the module passes. If you reach for the
environment escape hatch instead -- `SELF_HOSTED_RUNNER_DRAIN_WAIT_MS`, or
`SELF_HOSTED_RUNNER_PUSH_OUTCOME_ON_RELEASE` with the input left off -- the
runner will spend time this number does not know about, and the platform can
kill it mid-drain. Use the inputs, or add the difference to the grace period
yourself.
