# Add Development Server Auto-Start Module #204

## Summary

This PR introduces a new Coder module `dev-server-autostart` that automatically detects and starts development servers based on project type when a workspace starts. This addresses issue #204 by providing seamless development environment setup with minimal manual intervention.

## Features

### 🔍 **Automatic Project Detection**
- Scans workspace directory for common project files (package.json, requirements.txt, go.mod, etc.)
- Supports configurable scanning depth and subdirectory traversal
- Intelligent detection prevents false positives

### 🚀 **Multi-Framework Support**
- **Node.js/JavaScript**: npm, yarn, pnpm with framework detection (Next.js, React, Vue.js, Angular)
- **Python**: Django, FastAPI, Flask with automatic virtual environment detection
- **Ruby**: Ruby on Rails with bundle integration
- **Go**: Go modules with standard project layout
- **Java**: Maven and Gradle with Spring Boot detection
- **PHP**: Composer-based projects

### 📋 **Devcontainer Integration**
- Reads and executes commands from `devcontainer.json`
- Supports `postCreateCommand`, `postStartCommand`, and `postAttachCommand`
- Compatible with docker-compose based devcontainers
- Respects port forwarding configuration

### 🔧 **Highly Configurable**
```hcl
module "dev_server_autostart" {
  source   = "registry.coder.com/coder/dev-server-autostart/coder"
  agent_id = coder_agent.main.id
  
  # Project scanning
  work_dir            = "/workspaces"
  scan_subdirectories = true
  max_depth          = 3
  
  # Custom commands
  custom_commands = {
    "node"   = "npm run dev"
    "python" = "uvicorn main:app --reload --host 0.0.0.0"
  }
  
  # Framework control
  disabled_frameworks = ["php", "java"]
  
  # Devcontainer support
  devcontainer_integration = true
  devcontainer_service    = "web"
  
  # Dependency management
  auto_install_deps = true
  timeout_seconds  = 300
  
  # Monitoring
  health_check_enabled = true
  startup_delay       = 5
  log_level          = "info"
}
```

### 🔄 **Background Execution**
- Runs servers in tmux sessions for easy management
- Non-blocking startup process
- Graceful error handling and recovery
- Comprehensive logging for debugging

### 📊 **Health Monitoring**
- Basic health checks for common development ports
- Automatic retry logic for failed startups
- Integration with Coder's monitoring systems

## Implementation Details

### Module Structure
```
registry/coder/modules/dev-server-autostart/
├── main.tf          # Terraform configuration with variables and resources
├── run.sh           # Core detection and startup script
├── README.md        # Comprehensive documentation
└── main.test.ts     # Test suite for validation
```

### Detection Logic
The module uses a sophisticated detection system:

1. **File-based Detection**: Scans for framework-specific files
2. **Content Analysis**: Examines file contents for framework indicators
3. **Priority System**: Handles multiple frameworks in the same project
4. **Dependency Resolution**: Automatically installs requirements when needed

### Integration Points
- **Templates**: Added to `docker-devcontainer` template as example
- **Examples**: Complete example template demonstrating all features
- **Documentation**: Comprehensive guides and troubleshooting

## Testing

### Validation Tests
- Parameter validation for all input variables
- Terraform plan/apply tests for various configurations
- Error handling for edge cases

### Integration Tests
- Tested with real projects: Next.js, Django, Rails, Go applications
- Devcontainer.json compatibility validation
- Multi-project workspace scenarios

## Benefits

### For Developers
- **Zero Configuration**: Works out of the box with standard project structures
- **Familiar Workflow**: Respects existing project conventions and scripts
- **Multi-Project Support**: Handles monorepos and complex project structures
- **Debug Friendly**: Easy access to logs and running processes

### For Platform Teams
- **Standardized Setup**: Consistent development environment initialization
- **Reduced Support**: Fewer "how do I start this?" tickets
- **Flexible Configuration**: Adaptable to organization-specific workflows
- **Integration Ready**: Works with existing Coder templates and modules

### For DevOps
- **Container Optimization**: Faster workspace startup with pre-started services
- **Resource Efficiency**: Background processes don't block terminal access
- **Monitoring Integration**: Health checks and logging for operational visibility

## Migration Guide

### Existing Templates
Templates can easily adopt this module by adding:

```hcl
module "dev_server_autostart" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dev-server-autostart/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
}
```

### Devcontainer Projects
Projects with existing devcontainer.json files work automatically. The module:
- Executes existing postCreateCommand/postStartCommand
- Respects port forwarding configuration
- Maintains compatibility with VS Code dev containers

## Documentation

### Module Documentation
- Complete parameter reference
- Framework support matrix
- Configuration examples
- Troubleshooting guide

### Template Integration
- Updated docker-devcontainer template with auto-start
- New example template showcasing all features
- Migration guide for existing templates

## Future Enhancements

### Planned Features
- Support for additional frameworks (Rust, .NET, etc.)
- Advanced health checking with custom endpoints
- Integration with Coder's port forwarding
- Workspace-specific configuration override

### Extension Points
- Plugin system for custom project detection
- Webhook integration for external service startup
- Performance metrics and analytics

## Breaking Changes
None. This is a new module that doesn't affect existing functionality.

## Rollback Plan
If issues arise, the module can be easily disabled by:
1. Removing the module block from templates
2. Setting `count = 0` to disable
3. Reverting to manual development server management

---

This PR significantly improves the developer experience in Coder workspaces by eliminating the manual steps required to start development servers, while maintaining full flexibility and compatibility with existing workflows.
