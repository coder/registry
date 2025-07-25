---
display_name: Development Tools Installer
description: Automatically install essential development tools like Git, Docker, Node.js, Python, and Go in your workspace
icon: ../../../../.icons/code.svg
maintainer_github: sahelisaha04
verified: false
tags: [tools, development, installer, productivity]
---

# Development Tools Installer

Automatically install and configure essential development tools in your Coder workspace. This module supports Git, Docker, Node.js, Python, and Go with intelligent detection of already installed tools.

```tf
module "dev-tools" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/saheli/dev-tools/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  
  # Install Git and Node.js by default
  tools = ["git", "nodejs"]
}
```

## Features

✅ **Smart Detection** - Checks for existing installations before installing  
✅ **Multiple Tools** - Supports Git, Docker, Node.js, Python, and Go  
✅ **Detailed Logging** - Full installation logs with timestamps  
✅ **User-friendly Output** - Colorized progress indicators  
✅ **Zero Configuration** - Works out of the box with sensible defaults  
✅ **Fast Installation** - Efficient package management and caching

## Supported Tools

- **`git`** - Version control system with bash completion
- **`docker`** - Container runtime with user group setup
- **`nodejs`** - JavaScript runtime with npm package manager
- **`python`** - Python 3 with pip, venv, and dev tools
- **`golang`** - Go programming language with PATH configuration

## Examples

### Basic Usage

Install Git and Node.js (default configuration):

```tf
module "dev-tools" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/saheli/dev-tools/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

### Full Stack Development

Install all supported development tools:

```tf
module "dev-tools" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/saheli/dev-tools/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  
  tools = ["git", "docker", "nodejs", "python", "golang"]
}
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `agent_id` | string | *required* | The ID of a Coder agent |
| `tools` | list(string) | `["git", "nodejs"]` | List of tools to install |
| `log_path` | string | `/tmp/dev-tools-install.log` | Path for installation logs |
| `install_on_start` | bool | `true` | Whether to install tools on workspace start |
| `user` | string | `coder` | User to install tools for |

## Requirements

- Ubuntu/Debian-based workspace (uses apt package manager)
- Sudo access for package installation
- Internet connectivity for downloading packages
- Sufficient disk space for selected tools