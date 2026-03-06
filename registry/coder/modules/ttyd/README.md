---
display_name: ttyd
description: Share a terminal command over the web via a Coder app
icon: ../../../../.icons/terminal.svg
verified: true
tags: [terminal, web, ttyd]
---

# ttyd

Run any command and expose it as a web-based terminal via [ttyd](https://github.com/tsl0922/ttyd). Each connection spawns a new process for the configured command. The terminal is accessible as a Coder app in the workspace UI.

```tf
module "ttyd" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/ttyd/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  command  = "bash"
}
```

## Examples

### Custom command

```tf
module "ttyd" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/ttyd/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.main.id
  display_name = "Shared Terminal"
  command      = "tmux new-session -A -s main"
  share        = "authenticated"
}
```

### Readonly with custom ttyd options

```tf
module "ttyd" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/ttyd/coder"
  version         = "1.0.0"
  agent_id        = coder_agent.main.id
  command         = "tail -f /var/log/app.log"
  writable        = false
  additional_args = "-t fontSize=18"
}
```

## Session Behavior

By default, each browser tab that opens the ttyd app spawns a **new process** for the configured command. Closing the tab kills that process.

To get a **persistent, shared session** that survives tab closes and allows multiple viewers, use tmux as the command (see example above). This requires tmux to be installed in the workspace image.
