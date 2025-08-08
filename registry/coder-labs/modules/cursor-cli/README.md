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
- Configures Coder MCP task reporting (sets `CODER_MCP_APP_STATUS_SLUG`), and supports project MCP via `<folder>/.cursor/mcp.json`
- Lets you choose a model

```tf
module "cursor_cli" {
  source   = "registry.coder.com/coder-labs/cursor-cli/coder"
  version  = "0.1.0"
  agent_id = coder_agent.example.id

  # Optional
  folder             = "/home/coder/project"
  install_cursor_cli = true
  cursor_cli_version = "latest"
  output_format      = "json"   # text | json | stream-json
  force              = false
  model              = "gpt-5"
  mcp_json = jsonencode({
    mcpServers = {
      # example project-specific servers (see docs)
    }
  })
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
