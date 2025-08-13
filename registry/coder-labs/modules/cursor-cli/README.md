---
display_name: Cursor CLI
icon: ../../../../.icons/cursor.svg
description: Run Cursor CLI agent in your workspace (no AgentAPI)
verified: true
tags: [agent, cursor, ai, cli]
---

# Cursor CLI

Run the Cursor Coding Agent in your workspace using the Cursor CLI directly.

A full example with MCP, rules, and pre/post install scripts:

```tf

data "coder_parameter" "ai_prompt" {
  name    = "ai_prompt"
  type    = "string"
  default = "Write a simple hello world program in Python"
}

module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"

  # Optional
  install_cursor_cli = true
  cursor_cli_version = "latest"
  force              = true
  model              = "gpt-5"
  ai_prompt          = data.coder_parameter.ai_prompt.value

  # Minimal MCP server (writes `~/.cursor/mcp.json`):
  mcp_json = jsonencode({
    mcpServers = {
      playwright = {
        command = "npx"
        args    = ["-y", "@playwright/mcp@latest", "--headless", "--isolated", "--no-sandbox"]
      }
      desktop-commander = {
        command = "npx"
        args    = ["-y", "@wonderwhy-er/desktop-commander"]
      }
    }
  })

  # Use a pre_install_script to install the CLI
  pre_install_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
  EOT

  # Use post_install_script to wait for the repo to be ready
  post_install_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="$${FOLDER}/.git/config"
    echo "[cursor-cli] waiting for $${TARGET}..."
    for i in $(seq 1 600); do
      [ -f "$TARGET" ] && { echo "ready"; exit 0; }
      sleep 1
    done
    echo "timeout waiting for $${TARGET}" >&2
  EOT

  # Provide a map of file name to content; files are written to `~/.cursor/rules/<name>`.
  rules_files = {
    "python.yml" = <<-EOT
      version: 1
      rules:
        - name: python
          include: ['**/*.py']
          description: Python-focused guidance
      EOT

    "frontend.yml" = <<-EOT
      version: 1
      rules:
        - name: web
          include: ['**/*.{ts,tsx,js,jsx,css}']
          exclude: ['**/dist/**']
          description: Frontend rules
      EOT
  }
}
```

To run this module with AgentAPI, pass `enable_agentapi=true`

```tf
data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Initial prompt for the Codex CLI"
  mutable     = true
}

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.31"
  agent_id = coder_agent.main.id
}

module "cursor-cli" {
  source          = "registry.coder.com/coder-labs/cursor-cli/coder"
  agent_id        = coder_agent.main.id
  api_key         = "key_xxx"
  ai_prompt       = data.coder_parameter.ai_prompt.value
  folder          = "/home/coder/project"
  enable_agentapi = true
  force           = true # recommended while running tasks
}
```

## References

- See Cursor CLI docs: `https://docs.cursor.com/en/cli/overview`
- For MCP project config, see `https://docs.cursor.com/en/context/mcp#using-mcp-json`. This module writes your `mcp_json` into `~/.cursor/mcp.json`.
- For Rules, see `https://docs.cursor.com/en/context/rules#project-rules`. Provide `rules_files` (map of file name to content) to populate `~/.cursor/rules/`.

## Troubleshooting

- Ensure the CLI is installed (enable `install_cursor_cli = true` or preinstall it in your image)
- Logs are written to `~/.cursor-cli-module/`
