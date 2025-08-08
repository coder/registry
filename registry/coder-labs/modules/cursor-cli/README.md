---
display_name: Cursor CLI
icon: ../../../../.icons/cursor.svg
description: Run Cursor CLI agent in your workspace (no AgentAPI)
verified: true
tags: [agent, cursor, ai, cli]
---

# Cursor CLI

Run the Cursor Coding Agent in your workspace using the Cursor CLI directly. This module does not use AgentAPI and executes the Cursor agent process itself.

- Defaults to interactive mode, with an option for non-interactive mode
- Supports `--force` runs
- Allows configuring MCP servers (settings merge)
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
  interactive         = true
  non_interactive_cmd = "run --once"
  force               = false
  model               = "gpt-4o"
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
- The module writes merged settings to `~/.cursor/settings.json`
- Interactive by default; set `interactive = false` to run non-interactively via `non_interactive_cmd`

## Troubleshooting

- Ensure the CLI is installed (enable `install_cursor_cli = true` or preinstall it in your image)
- Logs are written to `~/.cursor-cli-module/`
