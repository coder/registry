# Development Server Auto-Start Example

This example demonstrates how to use the `dev-server-autostart` module to automatically detect and start development servers in a Coder workspace.

## Features Demonstrated

- **Automatic Project Detection**: Scans for common project files and starts appropriate development servers
- **Multi-Framework Support**: Supports Node.js, Python, Ruby, Go, Java, PHP and their popular frameworks
- **Devcontainer Integration**: Respects devcontainer.json configuration
- **Custom Commands**: Override default commands for specific project types
- **Background Execution**: Runs servers in tmux sessions without blocking the terminal
- **Health Monitoring**: Basic health checks for started servers
- **Multiple Development Ports**: Pre-configured Coder apps for common development ports

## Supported Project Types

| Framework | Detection | Default Command | Port |
|-----------|-----------|-----------------|------|
| Next.js | `next.config.js` | `npm run dev` | 3000 |
| React | `package.json` with react | `npm start` | 3000 |
| Vue.js | `vue.config.js` | `npm run serve` | 8080 |
| Angular | `angular.json` | `ng serve` | 4200 |
| Node.js | `package.json` | `npm start` | 3000 |
| Django | `manage.py` | `python manage.py runserver` | 8000 |
| FastAPI | `main.py` with FastAPI | `uvicorn main:app --reload` | 8000 |
| Flask | `app.py` with Flask | `python app.py` | 5000 |
| Rails | `Gemfile` + `config/application.rb` | `rails server` | 3000 |
| Go | `go.mod` | `go run .` | 8080 |
| Java/Spring | `pom.xml` | `mvn spring-boot:run` | 8080 |

## Usage

1. **Create a workspace** from this template
2. **Navigate to your project directory** or clone a repository
3. **Development servers will automatically start** based on detected project files
4. **Access your applications** through the pre-configured Coder apps in the dashboard

## Example Projects

The template includes sample projects that will be cloned if the workspace is empty:

### Next.js Example
```bash
cd nextjs-example/examples/hello-world
# Server will auto-start on port 3000
```

### FastAPI Example  
```bash
cd fastapi-example
# Server will auto-start on port 8000
```

## Monitoring and Debugging

### View Running Servers
```bash
tmux list-sessions
```

### Access Server Logs
```bash
tail -f /tmp/dev-server-autostart/server.log
```

### View Auto-Start Logs
```bash
tail -f /tmp/dev-server-autostart/autostart.log
```

### Attach to a Server Session
```bash
tmux attach-session -t dev-server-nextjs-hello-world
```

## Configuration Options

The template includes several configuration options:

- **Auto Install Dependencies**: Automatically run `npm install`, `pip install`, etc.
- **Devcontainer Integration**: Execute commands from `devcontainer.json`
- **Docker Image**: Choose from Node.js, Python, Java, Go, Ruby, or Universal base images

## Custom Commands

The template shows how to override default commands:

```hcl
custom_commands = {
  "node"    = "npm run dev || npm start"
  "nextjs"  = "npm run dev"
  "python"  = "python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000"
  "django"  = "python manage.py runserver 0.0.0.0:8000"
  "fastapi" = "uvicorn main:app --reload --host 0.0.0.0 --port 8000"
}
```

## Devcontainer.json Integration

If your project has a `devcontainer.json` file, the module will automatically execute:

- `postCreateCommand` - Run once after container creation
- `postStartCommand` - Run every time the container starts
- `postAttachCommand` - Run when attaching to the container

Example `devcontainer.json`:
```json
{
  "name": "My Dev Environment",
  "postCreateCommand": "npm install",
  "postStartCommand": "npm run dev",
  "forwardPorts": [3000, 8000]
}
```

## Troubleshooting

### Server Not Starting
1. Check if dependencies are installed: `npm list`, `pip list`, etc.
2. Verify the project structure matches expected patterns
3. Review logs: `cat /tmp/dev-server-autostart/autostart.log`

### Port Already in Use
- Check what's running: `netstat -tlnp | grep :3000`
- Kill existing processes: `pkill -f "node.*3000"`
- Restart the workspace to reset all processes

### Custom Framework Not Detected
- Add your framework to the `custom_commands` configuration
- Use the `work_dir` parameter to specify the exact project directory
- Consider creating a custom startup script for complex scenarios

## Advanced Usage

### Multiple Projects
The scanner can detect multiple projects in subdirectories:

```hcl
module "dev_server_autostart" {
  # ... other config ...
  scan_subdirectories = true
  max_depth          = 3
}
```

### Disable Specific Frameworks
```hcl
module "dev_server_autostart" {
  # ... other config ...
  disabled_frameworks = ["php", "java"]
}
```

### Custom Working Directory
```hcl
module "dev_server_autostart" {
  # ... other config ...
  work_dir = "/home/coder/projects"
}
```

This example provides a comprehensive starting point for automatic development server management in Coder workspaces.
