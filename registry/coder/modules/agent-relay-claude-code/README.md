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
  version  = "0.1.0"
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

The `agent_relay_status` metadata block is required. It has to live on the
`coder_agent`, which the module cannot declare; the relay reads it to decide
when to reap the workspace.

## Requirements

- The `claude` CLI must be in the workspace. `install_cli` (default `true`)
  downloads it at start only when it is not already on PATH; bake it into the
  image for the fastest start. `cli_binary` overrides the path.
- Builds must finish inside Agent Relay's 300s spawn budget: pre-pulled
  images, no persistent volumes.

## Parameters

Agent Relay verifies this contract against the template's active version at
startup and refuses to serve a pool that does not satisfy it. Every parameter
renders disabled with a "Set by Agent Relay on dispatch" placeholder; the
credential is masked.

| parameter                                 | kind       | value                                                                        |
| ----------------------------------------- | ---------- | ---------------------------------------------------------------------------- |
| `agent_relay_session_id`                  | persistent | Anthropic session this workspace serves                                      |
| `agent_relay_delivery_id`                 | persistent | work order that dispatched the build; rotates per attempt                    |
| `agent_relay_pool`                        | persistent | Agent Relay pool that dispatched the build                                   |
| `agent_relay_credential`                  | ephemeral  | single-use work order JWT (`SELF_HOSTED_RUNNER_POOL_SECRET`)                 |
| `agent_relay_claude_code_lock_to_account` | ephemeral  | Anthropic account the runner locks to (`SELF_HOSTED_RUNNER_LOCK_TO_ACCOUNT`) |
| `agent_relay_attempt`                     | ephemeral  | delivery attempt, echoed back when the relay nacks the session               |

## Runner lifecycle

The script starts `claude self-hosted-runner --capacity 1` detached and exits,
so the agent reaches `ready` immediately. The runner is wrapped so every
session runs with `--permission-mode bypassPermissions`; there is no terminal
attached, so an approval prompt would hang it. When the runner exits, Agent
Relay deletes the workspace; when it fails, the relay nacks the work order.

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
