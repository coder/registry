---
display_name: Cursor CLI
icon: ../../../../.icons/cursor.svg
description: Run Cursor Agent CLI in your workspace for AI pair programming
verified: true
tags: [agent, cursor, ai, tasks]
---

# Cursor CLI

Run the Cursor Agent CLI in your workspace for interactive coding assistance and automated task execution.

```tf
module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "0.1.1"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

## Basic setup

A full example with MCP, rules, and pre/post install scripts:

```tf

data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Build a Minesweeper in Python."
  mutable     = true
}

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.31"
  agent_id = coder_agent.main.id
}

module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "0.1.1"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"

  # Optional
  install_cursor_cli = true
  force              = true
  model              = "gpt-5"
  ai_prompt          = data.coder_parameter.ai_prompt.value
  api_key            = "xxxx-xxxx-xxxx" # Required while using tasks, see note below

  # Minimal MCP server (writes `folder/.cursor/mcp.json`):
  mcp = jsonencode({
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

  # Provide a map of file name to content; files are written to `folder/.cursor/rules/<name>`.
  rules_files = {
    "python.mdc" = <<-EOT
        ---
        description: RPC Service boilerplate
        globs:
        alwaysApply: false
        ---

        - Use our internal RPC pattern when defining services
        - Always use snake_case for service names.
        
        @service-template.ts
      EOT

    "frontend.mdc" = <<-EOT
        ---
        description: RPC Service boilerplate
        globs:
        alwaysApply: false
        ---

        - Use our internal RPC pattern when defining services
        - Always use snake_case for service names.

        @service-template.ts
      EOT
  }
}
```

> [!NOTE]
> A `.cursor` directory will be created in the specified `folder`, containing the MCP configuration, rules.
> To use this module with tasks, please pass the API Key obtained from Cursor to the `api_key` variable. To obtain the api key follow the instructions [here](https://docs.cursor.com/en/cli/reference/authentication#step-1%3A-generate-an-api-key)

## References

- See Cursor CLI docs: `https://docs.cursor.com/en/cli/overview`
- For MCP project config, see `https://docs.cursor.com/en/context/mcp#using-mcp-json`. This module writes your `mcp_json` into `folder/.cursor/mcp.json`.
- For Rules, see `https://docs.cursor.com/en/context/rules#project-rules`. Provide `rules_files` (map of file name to content) to populate `folder/.cursor/rules/`.

## Troubleshooting

- Ensure the CLI is installed (enable `install_cursor_cli = true` or preinstall it in your image)
- Logs are written to `~/.cursor-cli-module/`
