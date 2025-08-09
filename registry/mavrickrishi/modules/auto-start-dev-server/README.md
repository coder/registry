# Auto-Start Development Servers

Automatically detect and start development servers for various project types when a workspace starts. This module scans your workspace for common project structures and starts the appropriate development servers in the background without manual intervention.

## Features

- **Multi-language support**: Detects and starts servers for Node.js, Python (Django/Flask), Ruby (Rails), Java (Spring Boot), Go, PHP, Rust, and .NET projects
- **Devcontainer integration**: Respects custom start commands defined in `.devcontainer/devcontainer.json`
- **Configurable scanning**: Adjustable directory scan depth and project type toggles
- **Non-blocking startup**: Servers start in the background with configurable startup delay
- **Comprehensive logging**: All server output and detection results logged to a central file
- **Smart detection**: Uses project-specific files and configurations to identify project types

## Supported Project Types

| Framework/Language | Detection Files | Start Commands |
|-------------------|----------------|----------------|
| **Node.js/npm** | `package.json` | `npm start`, `npm run dev`, `yarn start` |
| **Ruby on Rails** | `Gemfile` with rails gem | `bundle exec rails server` |
| **Django** | `manage.py` | `python manage.py runserver` |
| **Flask** | `requirements.txt` with Flask | `python app.py/main.py/run.py` |
| **Spring Boot** | `pom.xml` or `build.gradle` with spring-boot | `mvn spring-boot:run`, `gradle bootRun` |
| **Go** | `go.mod` | `go run main.go` |
| **PHP** | `composer.json` | `php -S 0.0.0.0:8080` |
| **Rust** | `Cargo.toml` | `cargo run` |
| **.NET** | `*.csproj` | `dotnet run` |

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
}
```

## Configuration Options

### Required Variables

- `agent_id` (string): The ID of a Coder agent

### Optional Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `workspace_directory` | string | `"$HOME"` | Directory to scan for projects |
| `enable_npm` | bool | `true` | Enable Node.js/npm project detection |
| `enable_rails` | bool | `true` | Enable Ruby on Rails project detection |
| `enable_django` | bool | `true` | Enable Django project detection |
| `enable_flask` | bool | `true` | Enable Flask project detection |
| `enable_spring_boot` | bool | `true` | Enable Spring Boot project detection |
| `enable_go` | bool | `true` | Enable Go project detection |
| `enable_php` | bool | `true` | Enable PHP project detection |
| `enable_rust` | bool | `true` | Enable Rust project detection |
| `enable_dotnet` | bool | `true` | Enable .NET project detection |
| `enable_devcontainer` | bool | `true` | Enable devcontainer.json integration |
| `log_path` | string | `"/tmp/dev-servers.log"` | Path for logging output |
| `scan_depth` | number | `2` | Maximum directory depth to scan (1-5) |
| `startup_delay` | number | `10` | Delay in seconds before starting servers |
| `display_name` | string | `"Auto-Start Dev Servers"` | Display name for the script |

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

### Check Running Servers

```bash
# View all running development servers
ps aux | grep -E "(npm|rails|python|java|go|php|cargo|dotnet)"
```

### View Logs

```bash
# Real-time log viewing
tail -f /tmp/dev-servers.log

# View full log
cat /tmp/dev-servers.log
```

### Manual Testing

```bash
# Test the detection script manually
cd /path/to/workspace
bash /path/to/run.sh
```

## Example Projects

### Node.js Project Structure
```
my-app/
├── package.json        # ← Detected
├── src/
└── node_modules/
```

### Django Project Structure
```
my-project/
├── manage.py          # ← Detected  
├── myapp/
└── requirements.txt
```

### Spring Boot Project Structure
```
my-service/
├── pom.xml            # ← Detected (Maven)
├── src/
└── target/
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

### Debug Mode

Enable verbose logging by modifying the script to include debug output:

```bash
# Add to beginning of run.sh for debugging
set -x  # Enable bash debug mode
```

## Examples

### Basic Usage
```hcl
module "auto_start" {
  source   = "./modules/auto-start-dev-server"
  agent_id = coder_agent.main.id
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

## Contributing

This module is part of the Coder Registry. To contribute improvements:

1. Test your changes thoroughly across different project types
2. Update documentation for any new features
3. Ensure backward compatibility with existing configurations
4. Add appropriate error handling and logging

## License

This module is provided under the same license as the Coder Registry.