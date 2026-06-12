---
display_name: Zellij
description: Modern terminal workspace with session management
icon: ../../../../.icons/zellij.svg
verified: false
tags: [zellij, terminal, multiplexer]
---

# Zellij

Automatically install and configure [zellij](https://github.com/zellij-org/zellij), a modern terminal workspace with session management. Supports terminal and web modes, custom configuration, and session persistence.

```tf
module "zellij" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/jang2162/zellij/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Features

- Installs zellij if not already present (version configurable, default `0.43.1`)
- Configures zellij with sensible defaults
- Supports custom configuration (KDL format)
- Session serialization enabled by default
- **Two modes**: `terminal` (Coder built-in terminal) and `web` (browser-based via subdomain proxy)
- Cross-platform architecture support (x86_64, aarch64)

## Examples

### Basic Usage (Terminal Mode)

```tf
module "zellij" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/jang2162/zellij/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

### Web Mode

```tf
module "zellij" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/jang2162/zellij/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  mode     = "web"
  web_port = 8082
  group    = "Terminal"
  order    = 1
}
```

### Custom Configuration

```tf
module "zellij" {
  count         = data.coder_workspace.me.start_count
  source        = "registry.coder.com/jang2162/zellij/coder"
  version       = "1.0.0"
  agent_id      = coder_agent.example.id
  zellij_config = <<-EOT
    keybinds {
        normal {
            bind "Ctrl t" { NewTab; }
        }
    }
    theme "dracula"
  EOT
}
```

## How It Works

### Installation & Setup (scripts/run.sh)

1. **Version Check**: Checks if zellij is already installed with the correct version
2. **Architecture Detection**: Detects system architecture (x86_64 or aarch64)
3. **Download**: Downloads the appropriate zellij binary from GitHub releases
4. **Installation**: Installs zellij to `/usr/local/bin/zellij`
5. **Configuration**: Creates default or custom configuration at `~/.config/zellij/config.kdl`
6. **Web Mode Only**:
   - Prepends a `TERM` fix to `~/.bashrc` (sets `TERM=xterm-256color` inside zellij when `TERM=dumb`)
   - Starts the zellij web server as a daemon and creates an authentication token

### Session Access

- **Terminal mode**: Opens zellij in the Coder built-in terminal via `zellij attach --create default`
- **Web mode**: Accesses zellij through a subdomain proxy in the browser (authentication token required on first visit)

## Default Configuration

The default configuration includes:

- Session serialization enabled for persistence
- 10,000 line scroll buffer
- Copy on select enabled (system clipboard)
- Rounded pane frames
- Key bindings: `Ctrl+s` (new pane), `Ctrl+q` (quit)
- Default theme
- Web mode: web server IP/port automatically appended

> [!IMPORTANT]
>
> - Custom `zellij_config` replaces the default configuration entirely
> - Requires `curl` and `tar` for installation
> - Uses `sudo` to install to `/usr/local/bin/`
> - Supported architectures: x86_64, aarch64
