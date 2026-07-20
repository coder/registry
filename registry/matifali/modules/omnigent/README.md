---
display_name: Omnigent
icon: ../../../../.icons/omnigent.svg
description: Run a private Omnigent multi-agent coding server in your workspace.
verified: false
tags: [agent, omnigent, ai, multi-agent]
---

# Omnigent

Run a private [Omnigent](https://github.com/omnigent-dev) multi-agent coding orchestrator server inside your Coder workspace. Each workspace gets its own isolated Omnigent instance with a stable, derived admin password, no shared credentials, no manual password management.

The module installs Omnigent via the [official install script](https://omnigent.ai/install.sh), starts the server on a configurable port, waits for the health endpoint, and registers the local workspace as a host. The admin password is derived from the workspace ID at runtime and never stored in Terraform state.

```tf
module "omnigent" {
  source   = "registry.coder.com/matifali/omnigent/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
}
```

## Use in a template

Add this module to any Coder template that has a Linux `coder_agent`. The module only needs the agent ID. It handles installing `uv`, installing Omnigent, starting the app server, and registering the workspace as an Omnigent host.

For the best multi-agent experience, install and configure any local agent CLIs before the Omnigent host starts. Omnigent snapshots the host's available tools at startup, so Claude Code, Codex, or other harnesses should finish setup first.

### Minimal existing-template integration

Use this when your template already has an agent and you only want the Omnigent app.

```tf
module "omnigent" {
  source  = "registry.coder.com/matifali/omnigent/coder"
  version = "0.0.1"

  agent_id = coder_agent.main.id
}
```

### Full AI workspace integration

Use this pattern when you want Omnigent, Claude Code, Codex, Coder AI Gateway, and a repository workdir in any existing Docker, Kubernetes, or VM template. Replace the Git URL and dependency installer for your base image as needed. The dependency script below targets Ubuntu or Debian images with `apt-get`.

```tf
locals {
  repo_ready_sync_name = "matifali-omnigent-git-clone"

  ai_tools_pre_install_commands = <<-EOT
    missing_packages=()
    command -v curl >/dev/null 2>&1 || missing_packages+=(curl)
    command -v jq >/dev/null 2>&1 || missing_packages+=(jq)
    command -v tmux >/dev/null 2>&1 || missing_packages+=(tmux)
    command -v bwrap >/dev/null 2>&1 || missing_packages+=(bubblewrap)

    need_node=false
    if ! command -v node >/dev/null 2>&1; then
      need_node=true
    elif ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)' >/dev/null 2>&1; then
      need_node=true
    fi

    if [ "$${#missing_packages[@]}" -eq 0 ] && [ "$${need_node}" = false ]; then
      exit 0
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
      echo "ERROR: missing required AI tool dependencies and apt-get is not available." >&2
      printf 'Missing packages: %s\n' "$${missing_packages[*]:-none}" >&2
      printf 'Need Node.js 22+: %s\n' "$${need_node}" >&2
      exit 1
    fi

    (
      flock 9
      sudo apt-get update

      if [ "$${need_node}" = true ]; then
        if ! command -v curl >/dev/null 2>&1; then
          sudo apt-get install -y curl ca-certificates
        fi
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt-get install -y nodejs
      fi

      if [ "$${#missing_packages[@]}" -gt 0 ]; then
        sudo apt-get install -y ca-certificates "$${missing_packages[@]}"
      fi
    ) 9>/tmp/coder-ai-tools-apt.lock
  EOT

  codex_pre_install_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    coder exp sync want matifali-codex-repo-ready ${local.repo_ready_sync_name}
    coder exp sync start matifali-codex-repo-ready
    coder exp sync complete matifali-codex-repo-ready

    ${local.ai_tools_pre_install_commands}
  EOT

  claude_code_pre_install_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    coder exp sync want matifali-claude-code-repo-ready ${local.repo_ready_sync_name}
    coder exp sync start matifali-claude-code-repo-ready
    coder exp sync complete matifali-claude-code-repo-ready

    ${local.ai_tools_pre_install_commands}
  EOT
}

module "git_clone" {
  source  = "registry.coder.com/coder/git-clone/coder"
  version = "2.0.1"

  agent_id    = coder_agent.main.id
  url         = "https://github.com/coder/coder"
  base_dir    = "/home/coder/workspace"
  folder_name = "coder"
  extra_args  = ["--depth=1"]

  post_clone_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    coder exp sync start ${local.repo_ready_sync_name}
    coder exp sync complete ${local.repo_ready_sync_name}
  EOT
}

module "codex" {
  source  = "registry.coder.com/coder-labs/codex/coder"
  version = "5.2.1"

  agent_id           = coder_agent.main.id
  workdir            = module.git_clone.repo_dir
  enable_ai_gateway  = true
  pre_install_script = local.codex_pre_install_script
}

module "claude_code" {
  source  = "registry.coder.com/coder/claude-code/coder"
  version = "5.2.0"

  agent_id           = coder_agent.main.id
  workdir            = module.git_clone.repo_dir
  enable_ai_gateway  = true
  pre_install_script = local.claude_code_pre_install_script
}

module "omnigent" {
  source  = "registry.coder.com/matifali/omnigent/coder"
  version = "0.0.1"

  agent_id = coder_agent.main.id

  # Wait for Claude Code and Codex setup before Omnigent snapshots host tools.
  pre_install_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    coder exp sync want matifali-omnigent-ai-tools ${join(" ", concat(module.claude_code.scripts, module.codex.scripts))}
    coder exp sync start matifali-omnigent-ai-tools
    coder exp sync complete matifali-omnigent-ai-tools
  EOT
}
```

## Configuration examples

### Custom port

```tf
module "omnigent" {
  source   = "registry.coder.com/matifali/omnigent/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id
  port     = 7878
}
```

### Additional trusted origins

The module automatically trusts Coder app origins derived from `CODER_AGENT_URL` and `VSCODE_PROXY_URI` when those environment variables are available. If you expose Omnigent through another reverse proxy, add that browser origin explicitly:

```tf
module "omnigent" {
  source   = "registry.coder.com/matifali/omnigent/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id

  allowed_origins = ["https://omnigent.example.com"]
}
```

### Policies, server-wide

```tf
module "omnigent" {
  source   = "registry.coder.com/matifali/omnigent/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id

  server_config = <<-YAML
    policies:
      cap_tool_calls:
        type: function
        handler: omnigent.policies.builtins.safety.max_tool_calls_per_session
        factory_params:
          limit: 50
      require_approval:
        type: function
        handler: omnigent.policies.builtins.safety.ask_on_os_tools
  YAML
}
```

### Custom agents

```tf
module "omnigent" {
  source   = "registry.coder.com/matifali/omnigent/coder"
  version  = "0.0.1"
  agent_id = coder_agent.main.id

  agents = [
    {
      name    = "reviewer"
      content = <<-YAML
        name: reviewer
        instructions: You are an expert code reviewer. Focus on correctness, security, and clarity.
        executor:
          harness: claude-sdk
          model: claude-sonnet-4-5
      YAML
    }
  ]
}
```

### Bring your own server config file

```tf
module "omnigent" {
  source             = "registry.coder.com/matifali/omnigent/coder"
  version            = "0.0.1"
  agent_id           = coder_agent.main.id
  server_config_path = "/home/coder/.omnigent/server_config.yaml"
}
```

## Troubleshooting

Script logs are written to `~/.coder-modules/matifali/omnigent/logs/`. If the Omnigent app shows as unhealthy or the server fails to start, check:

```bash
cat ~/.coder-modules/matifali/omnigent/logs/server.log
cat ~/.coder-modules/matifali/omnigent/logs/start.log
cat ~/.coder-modules/matifali/omnigent/logs/install.log
cat ~/.coder-modules/matifali/omnigent/logs/host.log
```

The health endpoint is available at `http://localhost:<port>/health`. You can check it directly:

```bash
curl -sf http://localhost:6767/health && echo "healthy" || echo "not ready"
```

### Finding the admin password

The admin password is derived from the workspace ID at runtime. To retrieve it inside the workspace:

```bash
echo -n "$CODER_WORKSPACE_ID" | tr -d '-' | cut -c1-16
```
