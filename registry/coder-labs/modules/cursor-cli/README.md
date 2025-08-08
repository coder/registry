---
display_name: Cursor CLI
icon: ../../../../.icons/cursor.svg
description: Run Cursor CLI agent in your workspace (no AgentAPI)
verified: true
tags: [agent, cursor, ai, cli]
---

# Cursor CLI

Run the Cursor Coding Agent in your workspace using the Cursor CLI directly. This module does not use AgentAPI and executes the Cursor agent process itself.

- Runs non-interactive (autonomous) by default, using `-p` (print)
- Supports `--force` runs
- Allows configuring MCP servers and project MCP (`~/.cursor/settings.json` and `<folder>/.cursor/mcp.json`)
- Lets you choose a model and pass extra CLI arguments

```tf
module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id

  # Optional
  folder              = "/home/coder/project"
  install_cursor_cli  = true
  cursor_cli_version  = "latest"
  base_command        = "status"          # optional subcommand (default is chat mode)
  output_format       = "json"            # text | json | stream-json
  force               = false
  model               = "gpt-5"
  mcp_json            = jsonencode({
    mcpServers = {
      # example project-specific servers (see docs)
    }
  })
  additional_settings = jsonencode({
    mcpServers = {
      coder = {
        command = "coder"
        args    = ["exp", "mcp", "server"]
        type    = "stdio"
        name    = "Coder"
        env     = {}
        enabled = true
      }
    }
  })
  extra_args = ["--verbose"]
}
```

## Notes

- See Cursor CLI docs: `https://docs.cursor.com/en/cli/overview`
- For MCP project config, see `https://docs.cursor.com/en/context/mcp#using-mcp-json`. This module writes your `mcp_json` into `<folder>/.cursor/mcp.json` and merges `additional_settings` into `~/.cursor/settings.json`.
- For Rules, see `https://docs.cursor.com/en/context/rules#project-rules`. Provide `rules_files` (map of file name to content) to populate `<folder>/.cursor/rules/`.
- The agent runs non-interactively with `-p` by default. Use `output_format` to choose `text | json | stream-json` (default `json`).

## Troubleshooting

- Ensure the CLI is installed (enable `install_cursor_cli = true` or preinstall it in your image)
- Logs are written to `~/.cursor-cli-module/`
