---
display_name: Auto-Start Dev Servers
description: Automatically detect and start development servers for various project types
icon: ../../../../.icons/auto-dev-server.svg
verified: false
tags: [development, automation, servers]
---

# Auto-Start Development Servers

Automatically detect and start development servers for various project types when a workspace starts. This module scans your workspace for common project structures and starts the appropriate development servers in the background without manual intervention.

```tf
module "auto_start_dev_servers" {
  source   = "registry.coder.com/mavrickrishi/auto-start-dev-server/coder"
  version  = "1.0.2"
  agent_id = coder_agent.main.id
}
```

## Features

- **Multi-language support**: Detects and starts servers for Node.js, Python (Django/Flask), Ruby (Rails), Java (Spring Boot), Go, PHP, Rust, and .NET projects
- **Smart script prioritization**: Prioritizes `dev` scripts over `start` scripts for better development experience
- **Intelligent frontend detection**: Automatically identifies frontend projects (React, Vue, Angular, Next.js, Nuxt, Svelte, Vite) and prioritizes them for preview apps
- **Devcontainer integration**: Respects custom start commands defined in `.devcontainer/devcontainer.json`
- **Configurable scanning**: Adjustable directory scan depth and project type toggles
- **Non-blocking startup**: Servers start in the background with configurable startup delay
- **Comprehensive logging**: All server output and detection results logged to a central file
- **Smart detection**: Uses project-specific files and configurations to identify project types
- **Integrated live preview**: Automatically creates a preview app for the primary frontend project

## Supported Project Types

| Framework/Language | Detection Files                              | Start Commands (in priority order)                    |
| ------------------ | -------------------------------------------- | ----------------------------------------------------- |
| **Node.js/npm**    | `package.json`                               | `npm run dev`, `npm run serve`, `npm start` (or yarn) |
| **Ruby on Rails**  | `Gemfile` with rails gem                     | `bundle exec rails server`                            |
| **Django**         | `manage.py`                                  | `python manage.py runserver`                          |
| **Flask**          | `requirements.txt` with Flask                | `python app.py/main.py/run.py`                        |
| **Spring Boot**    | `pom.xml` or `build.gradle` with spring-boot | `mvn spring-boot:run`, `gradle bootRun`               |
| **Go**             | `go.mod`                                     | `go run main.go`                                      |
| **PHP**            | `composer.json`                              | `php -S 0.0.0.0:8080`                                 |
| **Rust**           | `Cargo.toml`                                 | `cargo run`                                           |
| **.NET**           | `*.csproj`                                   | `dotnet run`                                          |

## Examples

### Basic Usage

```tf
module "auto_start" {
  source   = "./modules/auto-start-dev-server"
  version  = "1.0.1"
  agent_id = coder_agent.main.id
}
```

### Advanced Usage

```tf
module "auto_start_dev_servers" {
  source   = "./modules/auto-start-dev-server"
  version  = "1.0.1"
  agent_id = coder_agent.main.id

  # Optional: Configure which project types to detect
  enable_npm         = true
  enable_rails       = true
  enable_django      = true
  enable_flask       = true
  enable_spring_boot = true
  enable_go          = true
  enable_php         = true
  enable_rust        = true
  enable_dotnet      = true

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

### Disable Preview App

```tf
module "auto_start" {
  source   = "./modules/auto-start-dev-server"
  version  = "1.0.1"
  agent_id = coder_agent.main.id

  # Disable automatic preview app creation
  enable_preview_app = false
}
```

### Selective Project Types

```tf
module "auto_start" {
  source   = "./modules/auto-start-dev-server"
  version  = "1.0.1"
  agent_id = coder_agent.main.id

  # Only enable web development projects
  enable_npm    = true
  enable_rails  = true
  enable_django = true
  enable_flask  = true

  # Disable other project types
  enable_spring_boot = false
  enable_go          = false
  enable_php         = false
  enable_rust        = false
  enable_dotnet      = false
}
```

### Deep Workspace Scanning

```tf
module "auto_start" {
  source   = "./modules/auto-start-dev-server"
  version  = "1.0.1"
  agent_id = coder_agent.main.id

  workspace_directory = "/workspaces"
  scan_depth          = 3
  startup_delay       = 5
  log_path            = "/var/log/dev-servers.log"
}
```

## License

This module is provided under the same license as the Coder Registry.
