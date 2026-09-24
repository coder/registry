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
  version  = "0.2.0"
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
}
```

The `agent_relay_status` metadata block is required. It has to live on the
`coder_agent`, which the module cannot declare; the relay reads it to decide
when to reap the workspace.

When Agent Relay stamps `agent_relay_session_id`, the module adds two external
apps. Cursor's docs call the clients Cursor Web and Cursor Desktop:

- **Open in Cursor Web** opens the cloud agent at `https://cursor.com/agents/<id>`.
- **Open in Cursor Desktop** opens it with
  `cursor://anysphere.cursor-deeplink/background-agent?bcId=<id>`.

A workspace a person creates by hand has no session id, so neither button is
created.

## Requirements

- The Cursor CLI (`agent`) must be in the workspace. `install_cli` (default
  `true`) downloads it at start only when it is not already on PATH; bake it
  into the image for the fastest start. `cli_binary` overrides the path.
- Repo-scoped pools: the template must clone `agent_relay_cursor_repo_url` and
  provide SCM credentials before this module's script runs.
- `computer_use = true` needs the computer-use packages in the image.
- Builds must finish inside the pool's `dispatch_deadline` (default 10m, max
  15m): pre-pulled images, no persistent volumes.

## Worker credential

By default the pool's service-account API key never leaves Agent Relay. At
dispatch the relay exchanges it for a Cursor sub-token scoped to the requesting
user and stamps that as the ephemeral `agent_relay_credential` parameter. It
is exported as `AGENT_RELAY_CURSOR_TOKEN` and the worker starts with
`--auth-token`. It is never written to disk, though as a command-line argument
it is visible in the worker's `/proc/<pid>/cmdline` to any process running as
the same user inside the workspace; the CLI offers no environment variable for
it. The token acts only as that user, cannot mint further tokens, and expires
after an hour. It is not refreshed: a worker that has to reconnect after expiry
fails and Cursor re-queues the request for a fresh workspace.

Some Cursor CLI releases refuse a delegated sub-token for pool workers
(`Delegated service-account tokens cannot start pool workers`). Agent Relay's
per-pool `insecure_shared_token` then stamps the service-account key itself,
together with `agent_relay_cursor_credential_kind = api_key`. The CLI accepts
that key only as an API key, never as `--auth-token`
(`Failed to validate worker account settings`), so the supervisor exports the
credential as `CURSOR_API_KEY` and drops `--auth-token` when the stamped kind
says so. Every workspace owner in such a pool can read a team-wide key from
the worker's environment. No template change is needed; the relay stamps the
kind and the module follows it.

| pool `insecure_shared_token` | stamped `agent_relay_cursor_credential_kind` | credential handed to the CLI as |
| ---------------------------- | -------------------------------------------- | ------------------------------- |
| `false` (default)            | `worker_token`                               | `--auth-token`                  |
| `true`                       | `api_key`                                    | `CURSOR_API_KEY`                |

## Parameters

Agent Relay verifies this contract against the template's active version at
startup and refuses to serve a pool that does not satisfy it. Every parameter
renders disabled with a "Set by Agent Relay on dispatch" placeholder; the
credential is masked.

## Scripts and logs

The module runs two steps through [coder-utils](https://registry.coder.com/modules/coder/coder-utils):
an install step that downloads the CLI when `install_cli` is set and the
binary is missing (a no-op otherwise), then a start step that launches the
worker. Everything lands under `$HOME/.coder-modules/coder/agent-relay-cursor`:

| path                                     | contents                                       |
| ---------------------------------------- | ---------------------------------------------- |
| `scripts/install.sh`, `scripts/start.sh` | the install and start steps as they ran        |
| `scripts/supervise.sh`                   | the detached supervisor that owns the worker   |
| `logs/*.log`                             | output of each step, plus the worker's own log |
| `worker-state`                           | the supervisor's lifecycle line (`state_file`) |

## Worker lifecycle

The start step launches `agent worker --pool ... --idle-release-timeout ... --auth-token ... start`
detached and exits, so the agent reaches `ready` immediately. The worker exits
`0` when its idle-release timer fires after a session; that clean exit is what
tells Agent Relay to delete the workspace. The timer starts when the agent
finishes a turn, not when the chat closes, so keep the timeout at or above
300 seconds.

`agent_relay_status` reports one of:

| value             | meaning                                                                    |
| ----------------- | -------------------------------------------------------------------------- |
| `pending`         | start step running, supervisor has not written yet                         |
| `idle`            | no credential: workspace was created manually                              |
| `working`         | worker alive, no session attached                                          |
| `serving`         | worker alive, session attached (best effort, see `serving_log_pattern`)    |
| `orphaned`        | worker process gone without recording an exit                              |
| `done <code>`     | worker exited with that status; `0` is the normal idle release             |
| `failed <reason>` | worker could not start, e.g. `runner-agent-missing` when the CLI is absent |

Renaming the `agent_relay_status` key breaks reaping.

The start step is safe to re-run. An agent restart inside the same build
re-runs it with the credential still set and the previous run's state on
disk: a live worker is left alone, a terminal state is left for the relay
to act on, and anything else is reset to `pending` before a new worker
starts. Liveness is judged by pid and cmdline, so a reused pid reads as
`orphaned` rather than `working`.
