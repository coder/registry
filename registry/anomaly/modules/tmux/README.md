---
display_name: "Tmux"
description: "Tmux for coder agent :)"
icon: "../../../../.icons/tmux.svg"
verified: false
tags: ["tmux", "terminal", "persistent"]
---

# tmux

This module provisions and configures [tmux](https://github.com/tmux/tmux) with session persistence and plugin support
for a Coder agent. It automatically installs tmux, the Tmux Plugin Manager (TPM), and a set of useful plugins, and sets
up a default or custom tmux configuration with session save/restore capabilities.

```tf
module "tmux" {
  source   = "registry.coder.com/anomaly/tmux/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Features

- Installs tmux if not already present
- Installs TPM (Tmux Plugin Manager)
- Configures tmux with plugins for sensible defaults, session persistence, and automation:
  - `tmux-plugins/tpm`
  - `tmux-plugins/tmux-sensible`
  - `tmux-plugins/tmux-resurrect`
  - `tmux-plugins/tmux-continuum`
- Supports custom tmux configuration
- Enables automatic session save
- Configurable save interval
- **Supports multiple named tmux sessions, each as a separate app in the Coder UI**

## Usage

```tf
module "tmux" {
  source        = "registry.coder.com/anomaly/tmux/coder"
  version       = "1.0.0"
  agent_id      = coder_agent.example.id
  tmux_config   = ""                        # Optional: custom tmux.conf content
  save_interval = 1                         # Optional: save interval in minutes
  sessions      = ["default", "dev", "ops"] # Optional: list of tmux sessions
  order         = 1                         # Optional: UI order
  group         = "Terminal"                # Optional: UI group
  icon          = "/icon/tmux.svg"          # Optional: app icon
}
```

## Multi-Session Support

This module can provision multiple tmux sessions, each as a separate app in the Coder UI. Use the `sessions` variable to specify a list of session names. For each session, a `coder_app` is created, allowing you to launch or attach to that session directly from the UI.

- **sessions**: List of tmux session names (default: `["default"]`).

## How It Works

- **tmux Installation:**
  - Checks if tmux is installed; if not, installs it using the system's package manager (supports apt, yum, dnf,
    zypper, apk, brew).
- **TPM Installation:**
  - Installs the Tmux Plugin Manager (TPM) to `~/.tmux/plugins/tpm` if not already present.
- **tmux Configuration:**
  - If `tmux_config` is provided, writes it to `~/.tmux.conf`.
  - Otherwise, generates a default configuration with plugin support and session persistence (using tmux-resurrect and
    tmux-continuum).
  - Sets up key bindings for quick session save (`Ctrl+s`) and restore (`Ctrl+r`).
- **Plugin Installation:**
  - Installs plugins via TPM.
- **Session Persistence:**
  - Enables automatic session save/restore at the configured interval.

## Example

```tf
module "tmux" {
  source      = "registry.coder.com/anomaly/tmux/coder"
  version     = "1.0.0"
  agent_id    = var.agent_id
  sessions    = ["default", "dev", "anomaly"]
  tmux_config = <<-EOT
    set -g mouse on
    set -g history-limit 10000
  EOT
  group       = "Terminal"
  order       = 2
}
```

> [!IMPORTANT]
>
> - If you provide a custom `tmux_config`, it will completely replace the default configuration. Ensure you include plugin
>   and TPM initialization lines if you want plugin support and session persistence.
> - The script will attempt to install dependencies using `sudo` where required.
> - If `git` is not installed, TPM installation will fail.
> - If you are using custom config, you'll be responsible for setting up persistence and plugins.
> - The `order`, `group`, and `icon` variables allow you to customize how tmux apps appear in the Coder UI.
> - In case of session restart or shh reconnection, the tmux session will be automatically restored :)
