---
display_name: Auto Development Server
description: Automatically detect and start development servers based on project detection
icon: ../../../../.icons/play.svg
verified: false
tags: [development, automation, devserver, nodejs, rails, django, flask, spring]
---

# Auto Development Server

This module automatically detects development projects in your workspace and starts the appropriate development servers in the background. It supports multiple frameworks and integrates with devcontainer.json configuration.

```tf
module "auto_dev_server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/toti85/auto-dev-server/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Features

🔍 **Multi-Framework Detection**: Supports Node.js, Rails, Django, Flask, FastAPI, Spring Boot, Go, Rust, and PHP projects

⚙️ **Devcontainer Integration**: Automatically reads and executes `postStartCommand` from `.devcontainer/devcontainer.json`

🚀 **Auto-Start on Workspace Launch**: Servers start automatically when your workspace boots up

📊 **Health Monitoring**: Periodic health checks ensure servers stay running

🎛️ **Highly Configurable**: Customize detection patterns, startup commands, and behavior

📝 **Comprehensive Logging**: Debug and monitor server startup with detailed logs

## Basic Usage

Add this module to your Coder template to enable automatic development server detection:

```tf
module "auto_dev_server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/toti85/auto-dev-server/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Supported Frameworks

| Framework       | Detection Files                            | Default Start Command                         |
| --------------- | ------------------------------------------ | --------------------------------------------- |
| **Node.js**     | `package.json`                             | `npm start`                                   |
| **Rails**       | `Gemfile`, `config.ru`, `app/controllers`  | `rails server`                                |
| **Django**      | `manage.py`, `settings.py`                 | `python manage.py runserver 0.0.0.0:8000`     |
| **Flask**       | `app.py`, `application.py`, `wsgi.py`      | `flask run --host=0.0.0.0`                    |
| **FastAPI**     | `main.py`, `app.py`                        | `uvicorn main:app --host 0.0.0.0 --port 8000` |
| **Spring Boot** | `pom.xml`, `build.gradle`, `src/main/java` | `./mvnw spring-boot:run`                      |
| **Go**          | `go.mod`, `main.go`                        | `go run .`                                    |
| **Rust**        | `Cargo.toml`, `src/main.rs`                | `cargo run`                                   |
| **PHP**         | `index.php`, `composer.json`               | `php -S 0.0.0.0:8000`                         |

## Configuration Options

### Basic Configuration

```tf
module "auto_dev_server" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/toti85/auto-dev-server/coder"
  version     = "1.0.0"
  agent_id    = coder_agent.example.id
  project_dir = "/home/coder/projects"
  start_delay = 45
}
```

### Framework Selection

Enable only specific frameworks:

```tf
module "auto_dev_server" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/toti85/auto-dev-server/coder"
  version            = "1.0.0"
  agent_id           = coder_agent.example.id
  enabled_frameworks = ["nodejs", "rails", "django"]
}
```

### Custom Start Commands

Override default commands for specific frameworks:

```tf
module "auto_dev_server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/toti85/auto-dev-server/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  custom_commands = {
    nodejs = "npm run dev"
    rails  = "bundle exec rails server -b 0.0.0.0"
    django = "python manage.py runserver 0.0.0.0:3000"
  }
}
```

### Advanced Configuration

```tf
module "auto_dev_server" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/toti85/auto-dev-server/coder"
  version            = "1.0.0"
  agent_id           = coder_agent.example.id
  project_dir        = "/workspace"
  enabled_frameworks = ["nodejs", "rails", "django", "spring"]
  start_delay        = 60
  log_level          = "DEBUG"
  use_devcontainer   = true
  custom_commands = {
    nodejs = "npm run dev -- --host 0.0.0.0"
    spring = "./gradlew bootRun"
  }
}
```

## Variables

| Variable             | Type           | Default                                                                            | Description                              |
| -------------------- | -------------- | ---------------------------------------------------------------------------------- | ---------------------------------------- |
| `agent_id`           | `string`       | **Required**                                                                       | The ID of a Coder agent                  |
| `project_dir`        | `string`       | `"$HOME"`                                                                          | Directory to scan for projects           |
| `enabled_frameworks` | `list(string)` | `["nodejs", "rails", "django", "flask", "fastapi", "spring", "go", "rust", "php"]` | Frameworks to detect                     |
| `start_delay`        | `number`       | `30`                                                                               | Delay before starting servers (seconds)  |
| `log_level`          | `string`       | `"INFO"`                                                                           | Logging level (DEBUG, INFO, WARN, ERROR) |
| `use_devcontainer`   | `bool`         | `true`                                                                             | Enable devcontainer.json integration     |
| `custom_commands`    | `map(string)`  | `{}`                                                                               | Custom start commands per framework      |

## Outputs

| Output               | Description                          |
| -------------------- | ------------------------------------ |
| `log_file`           | Path to the auto-dev-server log file |
| `enabled_frameworks` | List of enabled frameworks           |
| `project_directory`  | Directory being scanned              |

## Devcontainer Integration

The module automatically detects and respects `.devcontainer/devcontainer.json` configuration:

```json
{
  "name": "My Dev Environment",
  "image": "node:18",
  "postStartCommand": "npm install && npm run dev",
  "forwardPorts": [3000, 8080]
}
```

If a `postStartCommand` or `postCreateCommand` is found, it takes precedence over framework-specific defaults.

## Monitoring & Logs

### Log Files

- **Main log**: `$PROJECT_DIR/auto-dev-server.log`
- **Framework logs**: `$PROJECT_DIR/.auto-dev-server/{framework}.log`
- **PID files**: `$PROJECT_DIR/.auto-dev-server/{framework}.pid`

### Checking Server Status

```bash
# View main log
tail -f ~/auto-dev-server.log

# Check running servers
ls ~/.auto-dev-server/*.pid

# View specific framework log
tail -f ~/.auto-dev-server/nodejs.log
```

## Troubleshooting

### Servers Not Starting

1. **Check logs**: `tail -f ~/auto-dev-server.log`
2. **Verify detection**: Ensure your project files match detection patterns
3. **Check permissions**: Ensure the agent can execute startup commands
4. **Increase delay**: Some projects need more time to initialize

### Framework Not Detected

1. **Verify files exist**: Check that detection files are present
2. **Check enabled frameworks**: Ensure the framework is in `enabled_frameworks`
3. **Custom patterns**: Use `custom_commands` for non-standard setups

### Port Conflicts

If you have port conflicts, customize commands to use different ports:

```tf
custom_commands = {
  nodejs = "npm start -- --port 3001"
  django = "python manage.py runserver 0.0.0.0:8001"
}
```

## Examples

### Full-Stack Development Setup

```tf
module "auto_dev_server" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/toti85/auto-dev-server/coder"
  version            = "1.0.0"
  agent_id           = coder_agent.example.id
  project_dir        = "/home/coder/workspace"
  enabled_frameworks = ["nodejs", "django", "spring"]
  start_delay        = 45
  custom_commands = {
    nodejs = "npm run dev:frontend"
    django = "python manage.py runserver 0.0.0.0:8000"
    spring = "./mvnw spring-boot:run -Dspring-boot.run.profiles=dev"
  }
}
```

### Microservices Setup

```tf
module "auto_dev_server" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/toti85/auto-dev-server/coder"
  version            = "1.0.0"
  agent_id           = coder_agent.example.id
  project_dir        = "/workspace/services"
  enabled_frameworks = ["nodejs", "go", "fastapi"]
  log_level          = "DEBUG"
  custom_commands = {
    nodejs  = "npm run dev:api"
    go      = "go run cmd/server/main.go"
    fastapi = "uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload"
  }
}
```

## Contributing

This module is part of the Coder registry. For issues and contributions, please visit the [GitHub repository](https://github.com/coder/registry).

## License

Licensed under the MIT License.
