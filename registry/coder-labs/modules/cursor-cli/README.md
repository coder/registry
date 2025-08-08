---
display_name: Cursor CLI
icon: ../../../../.icons/cursor.svg
description: Run Cursor CLI agent in your workspace (no AgentAPI)
verified: true
tags: [agent, cursor, ai, cli]
---

# Cursor CLI

Run the Cursor Coding Agent in your workspace using the Cursor CLI directly.

```tf
module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id

  # Optional
  folder             = "/home/coder/project"
  install_cursor_cli = true
  cursor_cli_version = "latest"
  output_format      = "json" # text | json | stream-json
  force              = false
  model              = "gpt-5"
  mcp_json = jsonencode({
    mcpServers = {
      # example project-specific servers (see docs)
    }
  })
}
```

## Examples

### MCP configuration

Minimal MCP server (writes `<folder>/.cursor/mcp.json`):

```tf
module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"

  mcp_json = jsonencode({
    mcpServers = {
      tools = {
        command = "/usr/local/bin/tools-server"
        type    = "stdio"
      }
    }
  })
}
```

Multiple servers with args and env:

```tf
module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  folder   = "/workspace"

  mcp_json = jsonencode({
    mcpServers = {
      search = {
        command = "/usr/bin/rg"
        type    = "stdio"
        args    = ["--json"]
        env     = { RIPGREP_CONFIG_PATH = "/workspace/.ripgreprc" }
      }
      python = {
        command = "/usr/bin/python3"
        type    = "stdio"
        args    = ["/workspace/tools/mcp_python_server.py"]
      }
    }
  })
}
```

### Rules

Provide a map of file name to content; files are written to `<folder>/.cursor/rules/<name>`.

Single rules file:

```tf
module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"

  rules_files = {
    "global.yml" = <<-EOT
      version: 1
      rules:
        - name: project
          include: ['**/*']
          exclude: ['node_modules/**', '.git/**']
          description: Project-wide rules
      EOT
  }
}
```

Multiple rules files (language-specific):

```tf
module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id
  folder   = "/workspace"

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

## Notes

- See Cursor CLI docs: `https://docs.cursor.com/en/cli/overview`
- For MCP project config, see `https://docs.cursor.com/en/context/mcp#using-mcp-json`. This module writes your `mcp_json` into `<folder>/.cursor/mcp.json`.
- For Rules, see `https://docs.cursor.com/en/context/rules#project-rules`. Provide `rules_files` (map of file name to content) to populate `<folder>/.cursor/rules/`.
- The agent runs non-interactively with `-p` by default. Use `output_format` to choose `text | json | stream-json` (default `json`).

## Troubleshooting

- Ensure the CLI is installed (enable `install_cursor_cli = true` or preinstall it in your image)
- Logs are written to `~/.cursor-cli-module/`
