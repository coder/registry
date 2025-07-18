---
display_name: Auto Development Server
description: Automatically detect and start development servers based on project detection
icon: ../../../../.icons/play.svg
verified: false
maintainer_github: kunstewi
tags: [development, automation, devcontainer]
---

# Auto Development Server

Automatically detects and starts development servers for various project types when the workspace starts. Supports Node.js, Python, Ruby, Go, Rust, PHP projects, and integrates with devcontainer.json configuration.

```tf
module "auto_dev_server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/kunstewi/auto-dev-server/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Supported Project Types

- **Node.js**: Detects `package.json` and runs `npm start`, `npm run dev`, or `yarn start`
- **Python**: Detects Django (`manage.py`), Flask, or FastAPI projects
- **Ruby**: Detects Rails applications and Rack applications
- **Go**: Detects `go.mod` or `main.go` files
- **Rust**: Detects `Cargo.toml` files
- **PHP**: Detects `composer.json` or `index.php` files
- **Devcontainer**: Uses `postStartCommand` from `.devcontainer/devcontainer.json`

## Examples

### Basic Usage

```tf
module "auto_dev_server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/kunstewi/auto-dev-server/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

### Custom Configuration

```tf
module "auto_dev_server" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/kunstewi/auto-dev-server/coder"
  version          = "1.0.0"
  agent_id         = coder_agent.example.id
  project_dir      = "/workspace/projects"
  port_range_start = 4000
  port_range_end   = 8000
  log_level        = "DEBUG"
}
```