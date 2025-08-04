---
display_name: Development Server Auto-Start
description: Automatically detect and start development servers based on project type
icon: ../../../../.icons/terminal.svg
verified: true
tags: [development, server, automation, devcontainer]
---

# Development Server Auto-Start

Automatically detect and start development servers (npm start, rails server, etc.) in background when workspace starts. Integrates with devcontainer.json configuration for standardized setup.

```tf
module "dev-server-autostart" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dev-server-autostart/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Features

- **🔍 Automatic Project Detection**: Scans workspace for common project files (package.json, Gemfile, requirements.txt, etc.)
- **🚀 Multi-Framework Support**: Supports Node.js, Python, Ruby, Go, Java, PHP, and more
- **📋 Devcontainer Integration**: Reads and respects devcontainer.json configuration
- **🔧 Customizable Commands**: Override default commands with custom startup scripts
- **📊 Health Monitoring**: Basic health checks and restart capabilities
- **🔄 Background Execution**: Runs servers in background without blocking terminal
- **📝 Logging**: Comprehensive logging for debugging and monitoring

## Supported Project Types

| Framework/Language | Detection File(s) | Default Command |
|-------------------|-------------------|-----------------|
| Node.js/npm | `package.json` | `npm start` |
| Node.js/yarn | `package.json` + `yarn.lock` | `yarn start` |
| Node.js/pnpm | `package.json` + `pnpm-lock.yaml` | `pnpm start` |
| Python/Django | `manage.py` | `python manage.py runserver` |
| Python/Flask | `app.py`, `main.py` | `python app.py` |
| Python/FastAPI | `main.py` with FastAPI | `uvicorn main:app --reload` |
| Ruby on Rails | `Gemfile` + `config/application.rb` | `rails server` |
| Go | `go.mod` | `go run .` |
| Java/Maven | `pom.xml` | `mvn spring-boot:run` |
| Java/Gradle | `build.gradle` | `gradle bootRun` |
| PHP | `composer.json` | `php -S localhost:8000` |
| Next.js | `next.config.js` | `npm run dev` |
| Vue.js | `vue.config.js` | `npm run serve` |
| React | `package.json` with react scripts | `npm start` |
| Angular | `angular.json` | `ng serve` |

## Examples

### Basic Usage

```tf
module "dev-server-autostart" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dev-server-autostart/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

### Custom Working Directory

```tf
module "dev-server-autostart" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dev-server-autostart/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  work_dir = "/workspace/my-project"
}
```

### Override Commands

```tf
module "dev-server-autostart" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dev-server-autostart/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  custom_commands = {
    "node" = "npm run dev"
    "python" = "python -m uvicorn app.main:app --reload --host 0.0.0.0"
  }
}
```

### Multiple Projects

```tf
module "dev-server-autostart" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dev-server-autostart/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  scan_subdirectories = true
  max_depth = 3
}
```

### Devcontainer Integration

```tf
module "dev-server-autostart" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dev-server-autostart/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  devcontainer_integration = true
  devcontainer_service = "web"  # Optional: specify which service to start
}
```

### Disable Specific Frameworks

```tf
module "dev-server-autostart" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dev-server-autostart/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  disabled_frameworks = ["php", "java"]
}
```

## Configuration

All parameters are optional:

- `work_dir` (string): Directory to scan for projects (default: `/workspaces` or agent directory)
- `scan_subdirectories` (bool): Whether to scan subdirectories for projects (default: `true`)
- `max_depth` (number): Maximum directory depth to scan (default: `2`)
- `custom_commands` (map): Override default commands for specific project types
- `devcontainer_integration` (bool): Enable devcontainer.json integration (default: `true`)
- `devcontainer_service` (string): Specific service to start from docker-compose (optional)
- `disabled_frameworks` (list): List of frameworks to ignore during detection
- `startup_delay` (number): Delay in seconds before starting servers (default: `5`)
- `health_check_enabled` (bool): Enable basic health checks (default: `true`)
- `log_level` (string): Logging level: debug, info, warn, error (default: `info`)

## Devcontainer.json Integration

When `devcontainer_integration` is enabled, the module will:

1. Look for `.devcontainer/devcontainer.json` or `.devcontainer.json`
2. Parse `postCreateCommand`, `postStartCommand`, and `postAttachCommand`
3. Execute these commands in the background
4. If using docker-compose, optionally start specific services

Example devcontainer.json:
```json
{
  "name": "My Dev Environment",
  "postCreateCommand": "npm install",
  "postStartCommand": "npm start",
  "forwardPorts": [3000, 8000],
  "portsAttributes": {
    "3000": {
      "label": "Frontend"
    },
    "8000": {
      "label": "API"
    }
  }
}
```

## Monitoring and Logs

- Server processes run in background with tmux/screen sessions
- Logs are available in `/tmp/dev-server-autostart/`
- Use `tmux list-sessions` to see running servers
- Access logs with `tail -f /tmp/dev-server-autostart/server.log`

## Port Forwarding

The module automatically detects common development ports and suggests forwarding them through Coder apps. Common ports include:
- 3000 (React, Next.js)
- 8000 (Django, simple HTTP servers)
- 4200 (Angular)
- 8080 (Spring Boot)
- 5000 (Flask)
- 3001 (development proxies)

## Troubleshooting

### Server Not Starting
1. Check logs: `cat /tmp/dev-server-autostart/server.log`
2. Verify project dependencies are installed
3. Check if ports are already in use: `netstat -tlnp`

### Multiple Projects Detected
- Use `work_dir` to specify a specific project directory
- Use `disabled_frameworks` to ignore certain project types
- Set `max_depth` to limit scanning depth

### Devcontainer Commands Failing
- Ensure devcontainer.json syntax is valid
- Check that required tools are installed in the container
- Verify working directory and paths in commands
