---
display_name: Agent Relay Cursor
description: Serves Cursor cloud agent requests in Coder workspaces that Agent Relay dispatches.
icon: ../../../../.icons/cursor.svg
verified: true
tags: [agent, cursor, agent-relay]
---

# Agent Relay Cursor

Makes a Coder template a target for [Agent Relay](https://coder.com/docs/ai-coder/agent-relay)
Cursor pools: include the module, wire it to your `coder_agent`, and Agent
Relay can dispatch [Cursor cloud agent](https://coder.com/docs/ai-coder/agent-relay/cursor)
requests to workspaces built from the template.

```tf
module "cursor_worker" {
  source   = "registry.coder.com/coder/agent-relay-cursor/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  # Default. Installs the CLI only when the image does not already
  # carry it; baking it into the image stays the fastest path.
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

The `agent_relay_status` metadata block is required and must live on the
agent: the coder provider has no standalone agent-metadata resource, so
a module cannot declare it. Referencing the module's
`status_metadata_script` output does not create a dependency cycle; the
output does not depend on `agent_id`.

Requirements for the template and image:

- The Cursor CLI (`agent`) must be available in the workspace.
  `install_cli` defaults to `true` and downloads the latest CLI at
  workspace start, but only when the binary is not already on PATH: a
  CLI in the image is used as is, never upgraded, and costs nothing.
  When the download does run it needs outbound access to cursor.com and
  spends part of the claim-to-ready window. `cli_binary` overrides the
  path. With no CLI and no successful install, the worker reports
  `failed runner-agent-missing`, which
  Agent Relay reaps and records.
- For repo-scoped pools the template must clone the repository named
  by `agent_relay_cursor_repo_url` and provide SCM credentials before the worker
  starts, e.g. via a startup script ordered before this module's
  script. Repo-less pools should provide a `.cursor/rules` file in the
  worker's working directory instead.
- With `computer_use = true` the image must also carry the
  computer-use packages the Cursor CLI expects.
- Builds should complete within the pool's `dispatch_deadline`
  (default 10m): pre-pulled images, no persistent volumes. The
  deadline cannot exceed 15m: Agent Relay's reaper deletes
  workspaces stuck pending or starting after that grace, and it does
  so even when `dispatch_deadline` is `"0"` (no dispatcher deadline).

## Credential exposure

The pool's service-account API key reaches every dispatched workspace:
it is stamped as the ephemeral `agent_relay_credential` build parameter
and exported as the `CURSOR_API_KEY` environment variable, where the
workspace owner can read it for the lifetime of the workspace. Treat
the key accordingly:

- Use a dedicated service-account key per pool, scoped to the
  repository the pool serves, distinct from any broader Cursor
  key your team uses.
- Rotating the key in Agent Relay's config only affects new builds;
  running workspaces keep the value they were built with until reaped.

Sub-token worker authentication (short-lived per-worker credentials
instead of the pool key) is the tracked hardening follow-up.

The module declares the full parameter contract Agent Relay stamps on
every build; Agent Relay verifies the contract against the template's
active version at startup (dynamic parameters evaluate endpoint) and
refuses to serve a pool whose template does not satisfy it:

| parameter                                 | kind             | value                                                                                                                      |
| ----------------------------------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `agent_relay_session_id`                  | persistent state | Cursor request served by this workspace (dedupe/reconciliation key)                                                        |
| `agent_relay_delivery_id`                 | persistent state | worker id the request was claimed with; exported as `CURSOR_AGENT_WORKER_ID`                                               |
| `agent_relay_pool`                        | persistent state | Agent Relay pool that dispatched this build                                                                                |
| `agent_relay_cursor_pool_name`            | persistent state | Cursor-side pool the worker registers under                                                                                |
| `agent_relay_cursor_idle_release_timeout` | persistent state | seconds the worker idles after the agent finishes a turn before releasing and exiting; keep it at or above 300 (see below) |
| `agent_relay_cursor_repo_url`             | persistent state | repository the request targets; empty for repo-less pools, but always declared so the contract stays static                |
| `agent_relay_credential`                  | ephemeral        | service-account API key the worker authenticates with; exported as `CURSOR_API_KEY`                                        |

The persistent parameters matter because coderd only stores values the
template declares; Agent Relay's dedupe and reconciliation depend on
querying them with `param:` search filters.

Every parameter above renders disabled, with a placeholder saying Agent Relay
sets it. That is cosmetic, not a guardrail: it keeps a person creating a
workspace by hand from filling in machine-set fields, and does not stop the
CLI or the API from sending values. The credential is masked for the same
reason.

## Worker lifecycle reporting

Agent Relay deletes a workspace once its worker exits, and records the
failure when the worker died instead; Cursor offers no nack, so
observability is the only failure signal. Neither Coder nor Agent Relay
knows what a Cursor session is, so the module publishes the worker's
lifecycle and Agent Relay reads it.

The worker script starts

```sh
CURSOR_API_KEY= < token > CURSOR_AGENT_WORKER_ID= < worker id > \
agent worker --pool < agent_relay_cursor_pool_name > \
  --idle-release-timeout < idle_release_timeout > start
```

detached and exits, so the agent reaches the `ready` lifecycle state
instead of sitting in `starting` for the life of the session. The
worker exits `0` on its own once the idle-release timer fires after a
session ends; that clean exit is what tells Agent Relay to reap. Mind the
timer semantics: it starts when the agent finishes a turn, not when
the user closes the chat, so `idle_release_timeout` must cover the
user's reading and typing time. Once released, a follow-up to that
chat errors on Cursor's side until Cursor issues a new pending request
(which Agent Relay then serves with a fresh workspace). Keep the timeout
at or above 300 seconds (Agent Relay warns below that; the default is
600). A
detached supervisor owns the worker process and writes single-line
state to `state_file` (`/tmp/agent-relay/worker-state` by default).
The `agent_relay_status` metadata item reports one of:

| value             | meaning                                                                                                 |
| ----------------- | ------------------------------------------------------------------------------------------------------- |
| `pending`         | supervisor has not recorded state yet (agent just started)                                              |
| `idle`            | no worker token: workspace was created manually                                                         |
| `working`         | worker alive, no session attached yet                                                                   |
| `serving`         | worker alive and a session has attached                                                                 |
| `orphaned`        | state says working but the process is gone, and the supervisor died too                                 |
| `done <code>`     | worker exited with that status (`0` is the normal idle release; `137` means it was killed)              |
| `failed <reason>` | the worker could not be started at all, e.g. `runner-agent-missing` when the binary is not in the image |

`working` versus `serving` comes from matching `serving_log_pattern`
against the worker log. At default verbosity the Cursor CLI log
carries no session-attach line at all, so the pattern can only match
with verbose worker logs and typically never fires. That is fine:
Agent Relay's status page overlays Cursor's authoritative in-use worker
state (from the fleet worker listing) on top of this metadata, so a
workspace whose worker is in use renders as serving either way, and
reaping decisions rest on the process lifecycle. The metadata-level
distinction is therefore best-effort and purely cosmetic; tune the
pattern only if you run verbose logs and want the distinction inside
the workspace metadata too.

The script's timings row is not the reaping signal. coderd records it
when the script ends, which is now seconds after the agent starts, long
before the session finishes.

The `agent_relay_status` key is part of the contract; renaming it breaks
reaping.
