---
display_name: Claude Code self-hosted runner
description: Run Anthropic's Claude Code self-hosted runner as a long-lived process inside a Coder workspace, with per-workspace scoped self-eviction so the prebuild reconciler keeps the pool warm.
icon: ../../../../.icons/claude.svg
verified: false
tags: [ai, claude, claude-code, anthropic, runner]
---

# Claude Code self-hosted runner

Drops Anthropic's [Claude Code self-hosted runner](https://docs.anthropic.com/en/docs/claude-code/self-hosted-runners) into any Coder template that has a `coder_agent` and a workspace image with the runner binary installed (`/usr/local/bin/claude self-hosted-runner` by default).

The module owns the runner script (writes a per-session wrapper that forces `--permission-mode bypassPermissions`, then spawns a detached supervisor that runs the runner in the foreground and POSTs a delete build to self-evict on drain), the agent environment variables it needs, an optional bot-git askpass setup, and a host Docker socket gid fixup. Agent metadata items (lock status, active sessions, runner ID, last poll) are emitted via the `agent_metadata` output for the parent to splat into a `dynamic "metadata"` block.

The parent template still owns the `coder_agent` itself, the per-workspace scope-restricted self-evict token (minted via the `Mastercard/restapi` provider against an admin bootstrap token), the prebuild preset, and the infra block (`docker_container`, `kubernetes_pod`, etc.).

> [!IMPORTANT]
> This module is part of the [Claude Code self-hosted runners on Coder](https://coder.com/docs/ai-coder/claude-code-self-hosted-runners) recipe, which currently targets Anthropic's EAP build of the runner. Both the runner binary and the wire contract are still evolving; expect API drift until Anthropic ships GA.

## Usage

```tf
module "claude_self_hosted_runner" {
  source  = "registry.coder.com/coder-labs/claude-self-hosted-runner/coder"
  version = "1.0.0"

  agent_id         = coder_agent.main.id
  workspace_id     = data.coder_workspace.me.id
  pool_secret      = var.pool_secret
  self_evict_token = jsondecode(restapi_object.self_evict_token.api_response).key
  git_bot_token    = var.git_bot_token
  capacity         = tonumber(data.coder_parameter.capacity.value)
}

resource "coder_agent" "main" {
  # ... arch, os, dir, startup_script_behavior, etc.

  # Static metadata blocks coexist with the dynamic block below;
  # Terraform concatenates them on the same coder_agent.
  metadata {
    display_name = "CPU"
    key          = "cpu"
    script       = "top -bn1 | awk '/Cpu/ {print $2 \"%\"}'"
    interval     = 10
    timeout      = 5
  }

  dynamic "metadata" {
    for_each = module.claude_self_hosted_runner.agent_metadata
    content {
      display_name = metadata.value.display_name
      key          = metadata.value.key
      interval     = metadata.value.interval
      timeout      = metadata.value.timeout
      script       = metadata.value.script
    }
  }
}
```

## What the module does

- Writes `$HOME/.claude/wrapper.sh` at agent start. The wrapper appends `--permission-mode bypassPermissions` after `"$@"` so unattended sessions never stall on a tool-approval prompt; Claude Code's flag parser is last-occurrence-wins, so this overrides the server-supplied permission mode.
- Sets up the runner's required environment (`CLAUDE_POOL_SECRET`, `CLAUDE_CAPACITY`, `GIT_BOT_TOKEN`, `CODER_SELF_TOKEN`, `CODER_WORKSPACE_ID`) via `coder_env` resources on the agent.
- Spawns a `setsid nohup` supervisor that runs the runner in the foreground. When the runner exits on drain, the supervisor POSTs `/api/v2/workspaces/{id}/builds` with `{"transition":"delete"}` to self-evict, so Coder's prebuild reconciler can queue a replacement.
- Wires up `GIT_ASKPASS` if `git_bot_token` is supplied so the runner's child claude can `git push` without baking credentials into the image.
- If the parent template mounts the host Docker socket at `/var/run/docker.sock` and the gid does not match the in-container `docker` group, chgrps the socket so the workspace user can use it without sudo.

## Self-eviction security model

The `self_evict_token` input is minted by the parent template via the `Mastercard/restapi` provider at template build time, against an admin bootstrap token that lives in Terraform state and is never injected into the workspace. The minted token is scoped to `workspace:delete + workspace:read + template:read + user:read` and allow-listed to this single workspace's UUID. A leaked copy can do exactly one thing: delete this one workspace. No read of peer prebuilds, no SSH, no external auth, no git creds.

The supervisor uses raw `curl` against `/api/v2/workspaces/{id}/builds`, not the `coder delete` CLI. The CLI fetches workspace resources first, which fails against the scoped token whose allow-list intersection excludes peer workspaces.
