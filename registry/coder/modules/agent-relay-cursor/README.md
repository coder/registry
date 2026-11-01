---
display_name: Agent Relay Cursor
description: Serves Cursor cloud agent requests in Coder workspaces that Agent Relay dispatches.
icon: ../../../../.icons/cursor.svg
verified: true
tags: [agent, cursor, agent-relay]
---

# Agent Relay Cursor

Makes a Coder template a target for [Agent Relay](https://coder.com/docs/ai-coder/agent-relay)
Cursor pools. Agent Relay dispatches [Cursor cloud agent](https://coder.com/docs/ai-coder/agent-relay/cursor)
requests to workspaces built from the template; the module declares the
parameters the relay stamps on each build and runs the Cursor CLI worker.

```tf
module "cursor_worker" {
  source   = "registry.coder.com/coder/agent-relay-cursor/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  # Downloads the Cursor CLI at start when it is not in the image. Bake
  # the CLI into the image and set this to false for faster workspaces.
  install_cli = true
}

resource "coder_agent" "main" {
  # ...
  metadata {
    key          = "agent_relay_status"
    display_name = "Worker"
    script       = module.cursor_worker.status_metadata_script
    interval     = 10
    timeout      = 5
  }

  metadata {
    key          = "agent_relay_session_attached"
    display_name = "Session attached"
    script       = module.cursor_worker.session_attached_metadata_script
    interval     = 30
    timeout      = 5
  }
}
```

The `agent_relay_status` metadata block is required. It has to live on the
`coder_agent`, which the module cannot declare; the relay reads it to decide
when to reap the workspace. The `agent_relay_session_attached` block is
optional; see [Session attachment](#session-attachment).

When Agent Relay stamps `agent_relay_session_id`, the module adds two external
apps. Cursor's docs call the clients Cursor Web and Cursor Desktop:

- **Open in Cursor Web** opens the cloud agent at `https://cursor.com/agents/<id>`.
- **Open in Cursor Desktop** opens it with
  `cursor://anysphere.cursor-deeplink/background-agent?bcId=<id>`.

A workspace a person creates by hand has no session id, so neither button is
created.

## Requirements

- Coder 2.39.0 or newer and Agent Relay v0.14.0 or newer. On those versions
  the relay delivers the worker token as an ephemeral workspace secret, which
  the agent injects as `AGENT_RELAY_CURSOR_TOKEN`; it is never a build
  parameter. A relay that still sends it as the `agent_relay_credential`
  parameter refuses to serve a template on this version with
  `missing parameter "agent_relay_credential"`, so on older versions pin
  `0.8.0`, the last release that declares the parameter. Upgrade Coder, then
  Agent Relay, then move templates to `1.0.0` one at a time; a `0.8.0`
  template keeps working on the new versions, except that its `dispatched`
  output reads `false` on relay builds. To roll a relay or Coder back, pin
  templates back to `0.8.0` first.
- The Cursor CLI (`agent`) must be in the workspace. `install_cli` (default
  `true`) downloads it at start only when it is not already on PATH; bake it
  into the image for the fastest start. `cli_binary` overrides the path.
- Repo-scoped pools: the template must clone `agent_relay_cursor_repo_url` and
  provide SCM credentials before this module's script runs.
- `computer_use = true` needs the computer-use packages in the image.
  `share_desktop = true` (requires `computer_use`) lets people watch or take
  control of the agent's desktop from the Desktop tab in Cursor. It needs
  TigerVNC and Xfce in the image, as in
  `ghcr.io/coder/agent-relay-workspace:desktop`, and `DISPLAY` must be unset
  so the worker starts its own managed desktop. Run `agent worker debug` in
  the image to check.
- Builds must finish inside the pool's `dispatch_deadline` (default 10m, max
  15m): pre-pulled images, no persistent volumes.

## Worker credential

The pool's service-account API key never leaves Agent Relay. When the relay
claims a request, Cursor mints a
[session token](https://cursor.com/docs/cloud-agent/self-hosted/pool#session-tokens)
for that claim, and the relay sends it as an ephemeral workspace secret,
which the agent injects as `AGENT_RELAY_CURSOR_TOKEN`. It never appears in
the build's parameters or Terraform state. The module writes it to
`worker-token` (mode `0600`) and starts the worker with `--auth-token-file`.
The token stays off the worker's command line, and the supervisor unsets the
variable so the worker and the agent's commands do not inherit it. The
supervisor deletes the file when the worker exits.

A session token connects only the claimed worker id, and Cursor refuses it on
every endpoint a worker does not call. It stops working when the claim ends,
for example after the idle-release timeout, or when the service account key
that minted it is deleted or expires. Its 7-day expiry is a backstop, not a
session limit.

## Additional worker arguments

Use `additional_args` to pass extra arguments to `agent worker`, as a
list with one element per argument. They are appended after the flags the module sets and before the `start` subcommand, in the order written.
Each element is passed exactly as written, so a flag can repeat and a value
can contain spaces or quotes without escaping. Flags the module already sets
(`--pool`, `--idle-release-timeout`, `--auth-token-file`, `--auth-token`, `--management-addr`, `--computer-use`, `--share-desktop`) are rejected, with or without `=value`. Give a flag that takes an
optional value an explicit one (`--flag=value`), or it consumes `start`.

```tf
module "cursor_worker" {
  source          = "registry.coder.com/coder/agent-relay-cursor/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.main.id
  additional_args = ["--some-flag", "value", "--some-flag", "another value", "--another-flag"]
}
```

## Parameters

Agent Relay verifies this contract against the template's active version at
startup and refuses to serve a pool that does not satisfy it. Every parameter
renders disabled with a "Set by Agent Relay on dispatch" placeholder. The
worker token is not among them: it is a workspace secret, so it never appears
in the build's parameters or Terraform state, and the template should not
set `AGENT_RELAY_CURSOR_TOKEN` itself.

## Scripts and logs

The module runs three steps through [coder-utils](https://registry.coder.com/modules/coder/coder-utils):
a pre-install cleanup that stops any worker a previous agent start left
running, an install step that downloads the CLI when `install_cli` is set and
the binary is missing (a no-op otherwise), then a start step that launches the
worker. Everything lands under `$HOME/.coder-modules/coder/agent-relay-cursor`;
the separate stop script uses the same cleanup source and reports failures in
its Coder script output:

| path                                     | contents                                              |
| ---------------------------------------- | ----------------------------------------------------- |
| `scripts/pre_install.sh`                 | the cleanup as it ran on start                        |
| `scripts/install.sh`, `scripts/start.sh` | the install and start steps as they ran               |
| `scripts/supervise.sh`                   | the detached supervisor that owns the worker          |
| `supervisors/`, `workers/`               | one identity record per running supervisor and worker |
| `started/`                               | one start claim per cleanup generation                |
| `cleanup-complete`                       | fresh startup generation; removed on workspace stop   |
| `logs/*.log`                             | output of each step, plus the worker's own log        |
| `worker-state`                           | the supervisor's lifecycle line (`state_file`)        |
| `worker-token`                           | the session token, removed when the worker exits      |

## Worker lifecycle

The start step launches `agent worker --pool ... --idle-release-timeout ... --auth-token-file ... start`
detached and exits, so the agent reaches `ready` immediately. The worker exits
`0` when its idle-release timer fires after a session; that clean exit is what
tells Agent Relay to delete the workspace. The timer starts when the agent
finishes a turn, not when the chat closes, so keep the timeout at or above
300 seconds.

`agent_relay_status` reports one of:

| value             | meaning                                                                    |
| ----------------- | -------------------------------------------------------------------------- |
| `pending`         | start step running, supervisor has not written yet                         |
| `idle`            | no worker token in this build: created by a person, or restarted by one    |
| `working`         | worker alive, no session attached                                          |
| `serving`         | worker alive, session attached (best effort, see `serving_log_pattern`)    |
| `orphaned`        | worker process gone without recording an exit                              |
| `done <code>`     | worker exited with that status; `0` is the normal idle release             |
| `failed <reason>` | worker could not start, e.g. `runner-agent-missing` when the CLI is absent |

Renaming the `agent_relay_status` key breaks reaping.

The start step is safe to re-run after the pre-install cleanup. The supervisor
and worker outlive the agent, so a normal agent start attempts to stop the
previous supervisor and worker, then clears the previous run's state and
token. A worker stopped this way records no terminal state. An agent start
with a credential therefore starts a fresh worker, even after a terminal state;
one without a credential reports `idle`.
The supervisor and the worker each record their pid, boot id, and process
start time before the CLI runs, and are only signalled while all three still
match, which protects against a reused pid. The worker records itself, so it is
stopped even when its supervisor was killed. Processes that ignore `SIGTERM`
for 10 seconds get `SIGKILL`, with at most another 5 seconds to confirm exit.
The separate stop script has a 20-second timeout; allow at least 30 seconds
for cleanup in the workspace shutdown budget. Stop removes the launch marker
and never recreates it. A surviving old supervisor that already checked the
marker can still race with a new start to write stale status or remove its
shared token. Both cleanup modes remove the old state and token before and
after signalling.

Startup publishes a fresh `cleanup-complete` marker even when a verified old
process survives or an identity cannot be verified. If pre-install cleanup did
not publish a marker at all, the start step creates a fresh generation and
continues. If an old valid marker and its start claim remain, it rotates the
generation and starts anyway. Without a credential, start removes any old token
before reporting `idle`, even if cleanup never ran. An unverifiable pid is never
signalled; its record remains for a later cleanup attempt, and the error is
logged. This availability-first policy can leave two workers running if cleanup
was skipped or could not stop the old one. Liveness in `agent_relay_status` is
judged by pid and cmdline, so a reused pid reads as `orphaned` rather than
`working`. The reaper also needs a short grace after a new build so it does not
act on old metadata before startup cleanup and a fresh status report.

## Session attachment

The worker serves `GET /healthz`, `GET /readyz`, and `GET /metrics` on
`management_addr` (default `127.0.0.1:3287`; Cursor's docs use `8080`, which templates often take). The
`cursor_self_hosted_worker_session_active` gauge is `1` while a cloud agent
session runs on the worker. `session_attached_metadata_script` reads it and
prints one of:

| value        | worker running | session held | meaning                                                              |
| ------------ | -------------- | ------------ | -------------------------------------------------------------------- |
| `attached`   | yes            | yes          | a cloud agent session is active on the worker                        |
| `unattached` | yes            | no           | waiting for its claimed session, or released one and is still alive  |
| `stopped`    | no             | no           | exited, died, never started, or the workspace was created manually   |
| `disabled`   | not checked    | not checked  | `management_addr` is empty, so the server is off and nothing is read |
| error        | yes            | unknown      | `/metrics` cannot be read or has no session gauge                    |

Running means the pid the supervisor recorded in `worker-state` is alive
(`kill -0`) and its command line is still the CLI. The supervisor writes
`working <pid>` when it starts the worker and `done <code>` when it exits,
so a clean idle release, a crash, and a reused pid all read as `stopped`.

An error is a non-zero exit, so the metadata sample carries an error
rather than a value and a consumer can tell unknown from any state above. The server
starts only after the worker connects to Cursor, so a fresh worker reports
an error briefly. The image needs `curl` and `awk`.

`management_addr` is `host:port`. An empty host (`:3287`), `0.0.0.0`, or
`[::]` binds every interface; the script still reads it over loopback. Keep
the default loopback bind unless something outside the workspace must
scrape the worker, and never publish it through a `coder_app`.

```tf
module "cursor_worker" {
  source          = "registry.coder.com/coder/agent-relay-cursor/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.main.id
  management_addr = "127.0.0.1:3290"
}
```
