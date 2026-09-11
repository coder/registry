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

## Requirements

- The Cursor CLI (`agent`) must be in the workspace. `install_cli` (default
  `true`) downloads it at start only when it is not already on PATH; bake it
  into the image for the fastest start. `cli_binary` overrides the path.
- Repo-scoped pools: the template must clone `agent_relay_cursor_repo_url` and
  provide SCM credentials before this module's script runs.
- `computer_use = true` needs the computer-use packages in the image.
- Builds must finish inside the pool's `dispatch_deadline` (default 10m, max
  15m): pre-pulled images, no persistent volumes.

## Credential exposure

The pool's service-account API key is stamped on every dispatched workspace as
the ephemeral `agent_relay_credential` parameter and exported as
`CURSOR_API_KEY`, readable by the workspace owner. Use a dedicated key per
pool, scoped to the repository it serves. Rotating it affects new builds only.

## Parameters

Agent Relay verifies this contract against the template's active version at
startup and refuses to serve a pool that does not satisfy it. Every parameter
renders disabled with a "Set by Agent Relay on dispatch" placeholder; the
credential is masked.

| parameter                                 | kind       | value                                                             |
| ----------------------------------------- | ---------- | ----------------------------------------------------------------- |
| `agent_relay_session_id`                  | persistent | Cursor request this workspace serves                              |
| `agent_relay_delivery_id`                 | persistent | worker id the request was claimed with (`CURSOR_AGENT_WORKER_ID`) |
| `agent_relay_pool`                        | persistent | Agent Relay pool that dispatched the build                        |
| `agent_relay_cursor_pool_name`            | persistent | Cursor-side pool the worker registers under                       |
| `agent_relay_cursor_idle_release_timeout` | persistent | seconds the worker idles after a turn before exiting (min 300)    |
| `agent_relay_cursor_repo_url`             | persistent | repository the request targets; empty for repo-less pools         |
| `agent_relay_credential`                  | ephemeral  | service-account API key (`CURSOR_API_KEY`)                        |

## Worker lifecycle

The script starts `agent worker --pool ... --idle-release-timeout ... start`
detached and exits, so the agent reaches `ready` immediately. The worker exits
`0` when its idle-release timer fires after a session; that clean exit is what
tells Agent Relay to delete the workspace. The timer starts when the agent
finishes a turn, not when the chat closes, so keep the timeout at or above
300 seconds.

`agent_relay_status` reports one of:

| value             | meaning                                                                    |
| ----------------- | -------------------------------------------------------------------------- |
| `pending`         | no state recorded yet                                                      |
| `idle`            | no credential: workspace was created manually                              |
| `working`         | worker alive, no session attached                                          |
| `serving`         | worker alive, session attached (best effort, see `serving_log_pattern`)    |
| `orphaned`        | worker process gone without recording an exit                              |
| `done <code>`     | worker exited with that status; `0` is the normal idle release             |
| `failed <reason>` | worker could not start, e.g. `runner-agent-missing` when the CLI is absent |

Renaming the `agent_relay_status` key breaks reaping.
