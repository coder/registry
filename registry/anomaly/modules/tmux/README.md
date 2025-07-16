---
display_name: "Tmux"
description: "Tmux for coder agent :)"
icon: "../../../../.icons/tmux.svg"
verified: false
tags: ["tmux", "terminal", "persistent"]
---

# tmux Terraform Module

This module provisions and configures [tmux](https://github.com/tmux/tmux) with session persistence and plugin support
for a Coder agent. It automatically installs tmux, the Tmux Plugin Manager (TPM), and a set of useful plugins, and sets
up a default or custom tmux configuration with session save/restore capabilities.

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
- To restore in case of server restart `prefix + ctrl+r`
- Configurable save interval

## Usage

```hcl
module "tmux" {
  source        = "path/to/this/module"
  agent_id      = coder_agent.example.id
  tmux_config = "" # Optional: custom tmux.conf content
  save_interval = 1  # Optional: save interval in minutes
}
```

## Input Variables

| Name          | Type   | Description                         | Default |
| ------------- | ------ | ----------------------------------- | ------- |
| agent_id      | string | The ID of a Coder agent.            | n/a     |
| tmux_config   | string | Custom tmux configuration to apply. | ""      |
| save_interval | number | Save interval (in minutes).         | 1       |

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

```hcl
module "tmux" {
  source        = "./registry/anomaly/modules/tmux"
  agent_id      = var.agent_id
  tmux_config   = <<-EOT
    set -g mouse on
    set -g history-limit 10000
  EOT
}
```

## Outputs

This module does not export outputs.

## Notes

- If you provide a custom `tmux_config`, it will completely replace the default configuration. Ensure you include plugin
  and TPM initialization lines if you want plugin support.
- The script will attempt to install dependencies using `sudo` where required.
- If `git` is not installed, TPM installation will fail.
- To restore in case of server restart `prefix + ctrl+r`
- If you are using custom config, you'll be responsible for setting up persistence
