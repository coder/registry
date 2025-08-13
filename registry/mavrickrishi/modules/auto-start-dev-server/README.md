---
display_name: Auto-Start Development Servers
description: Automatically detect and start development servers for various project types
icon: ../../../../.icons/server.svg
verified: false
tags:
  [
    development,
    automation,
    servers,
    nodejs,
    python,
    java,
    go,
    rust,
    php,
    rails,
    django,
    flask,
    spring-boot,
    dotnet,
  ]
---

# Auto-Start Development Servers

Automatically detect and start development servers for various project types when a workspace starts. This module scans your workspace for common project structures and starts the appropriate development servers in the background without manual intervention.

```tf
module "auto_start_dev_servers" {
  source   = "registry.coder.com/mavrickrishi/auto-start-dev-server/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

## Features

- **Multi-language support**: Detects and starts servers for Node.js, Python (Django/Flask), Ruby (Rails), Java (Spring Boot), Go, PHP, Rust, and .NET projects
- **Devcontainer integration**: Respects custom start commands defined in `.devcontainer/devcontainer.json`
- **Configurable scanning**: Adjustable directory scan depth and project type toggles
- **Non-blocking startup**: Servers start in the background with configurable startup delay
- **Comprehensive logging**: All server output and detection results logged to a central file
- **Smart detection**: Uses project-specific files and configurations to identify project types
- **Integrated live preview**: Automatically creates a preview app for the first detected project

## Supported Project Types

| Framework/Language | Detection Files                              | Start Commands                           |
| ------------------ | -------------------------------------------- | ---------------------------------------- |
| **Node.js/npm**    | `package.json`                               | `npm start`, `npm run dev`, `yarn start` |
| **Ruby on Rails**  | `Gemfile` with rails gem                     | `bundle exec rails server`               |
| **Django**         | `manage.py`                                  | `python manage.py runserver`             |
| **Flask**          | `requirements.txt` with Flask                | `python app.py/main.py/run.py`           |
| **Spring Boot**    | `pom.xml` or `build.gradle` with spring-boot | `mvn spring-boot:run`, `gradle bootRun`  |
| **Go**             | `go.mod`                                     | `go run main.go`                         |
| **PHP**            | `composer.json`                              | `php -S 0.0.0.0:8080`                    |
| **Rust**           | `Cargo.toml`                                 | `cargo run`                              |
| **.NET**           | `*.csproj`                                   | `dotnet run`                             |

## Usage

```hcl
module "auto_start_dev_servers" {
  source   = "./modules/auto-start-dev-server"
  agent_id = coder_agent.main.id

  # Optional: Configure which project types to detect
  enable_npm         = true
  enable_rails       = true
  enable_django      = true
  enable_flask       = true
  enable_spring_boot = true
  enable_go         = true
  enable_php        = true
  enable_rust       = true
  enable_dotnet     = true

  # Optional: Enable devcontainer.json integration
  enable_devcontainer = true

  # Optional: Workspace directory to scan (supports environment variables)
  workspace_directory = "$HOME"

  # Optional: Directory scan depth (1-5)
  scan_depth = 2

  # Optional: Startup delay in seconds
  startup_delay = 10

  # Optional: Log file path
  log_path = "/tmp/dev-servers.log"

  # Optional: Enable automatic preview app (default: true)
  enable_preview_app = true
}
```

## Configuration Options

### Required Variables

- `agent_id` (string): The ID of a Coder agent

## Devcontainer Integration

When `enable_devcontainer` is true, the module will check for `.devcontainer/devcontainer.json` files and look for custom start commands in the VS Code settings:

```json
{
  "customizations": {
    "vscode": {
      "settings": {
        "npm.script.start": "npm run custom-dev-command"
      }
    }
  }
}
```

If found, the custom command will be used instead of the default project detection logic.

## Monitoring and Debugging

### View Logs

```bash
# Real-time log viewing
tail -f /tmp/dev-servers.log

# View full log
cat /tmp/dev-servers.log
```

## Security Considerations

- Servers are started with the same user permissions as the Coder agent
- All project detection is read-only (only checks for existence of files)
- Server processes run in the background and inherit workspace environment
- Log files contain server output which may include sensitive information

## Troubleshooting

### Common Issues

1. **No servers starting**: Check that project files exist and scan depth covers your project directories
2. **Permission denied**: Ensure the script has execute permissions and dependencies are installed
3. **Wrong directory**: Verify `workspace_directory` path is correct and accessible
4. **Missing dependencies**: Install required runtimes (node, python, java, etc.) in your base image

## Live Preview App

The module automatically creates a "Live Preview" app in your Coder workspace that points to the first detected development server. This gives you instant access to your running application through the Coder dashboard.

- **Automatic detection**: Uses the port from the first project detected
- **Dynamic URL**: Points to `http://localhost:{detected_port}`
- **Configurable**: Can be disabled by setting `enable_preview_app = false`
- **Fallback**: Defaults to port 3000 if no projects are detected

## Module Outputs

| Output                   | Description                              | Example Value                     |
| ------------------------ | ---------------------------------------- | --------------------------------- |
| `detected_projects_file` | Path to JSON file with detected projects | `/tmp/detected-projects.json`     |
| `log_path`               | Path to dev server log file              | `/tmp/dev-servers.log`            |
| `common_ports`           | Map of default ports by project type     | `{nodejs=3000, django=8000, ...}` |
| `preview_url`            | URL of the live preview app              | `http://localhost:3000`           |
| `detected_port`          | Port of the first detected project       | `3000`                            |

## Examples

### Basic Usage

```hcl
module "auto_start" {
  source   = "./modules/auto-start-dev-server"
  agent_id = coder_agent.main.id
}
```

### Disable Preview App

```hcl
module "auto_start" {
  source   = "./modules/auto-start-dev-server"
  agent_id = coder_agent.main.id

  # Disable automatic preview app creation
  enable_preview_app = false
}
```

### Selective Project Types

```hcl
module "auto_start" {
  source   = "./modules/auto-start-dev-server"
  agent_id = coder_agent.main.id

  # Only enable web development projects
  enable_npm    = true
  enable_rails  = true
  enable_django = true
  enable_flask  = true

  # Disable other project types
  enable_spring_boot = false
  enable_go         = false
  enable_php        = false
  enable_rust       = false
  enable_dotnet     = false
}
```

### Deep Workspace Scanning

```hcl
module "auto_start" {
  source   = "./modules/auto-start-dev-server"
  agent_id = coder_agent.main.id

  workspace_directory = "/workspaces"
  scan_depth         = 3
  startup_delay      = 5
  log_path          = "/var/log/dev-servers.log"
}
```

## License

This module is provided under the same license as the Coder Registry.
