# AI Agent Modules

The Coder Registry provides Terraform modules for integrating various AI coding agents into your development workspaces. These modules enable seamless AI-powered development experiences with web interfaces, task reporting, and automated setup.

## Available AI Agent Modules

### Core AI Agents (`coder` namespace)

#### Aider

- **Module**: `registry.coder.com/coder/aider/coder`
- **Description**: AI pair programming tool for editing code in your local git repository
- **Features**: Git-aware code editing, multiple AI provider support, automatic commits
- **Supported Providers**: OpenAI, Anthropic, Google, Azure, Ollama
- **AgentAPI**: ✅ Supported
- **Documentation**: [View Module](https://registry.coder.com/modules/aider/coder)

#### Claude Code

- **Module**: `registry.coder.com/coder/claude-code/coder`
- **Description**: Anthropic's Claude AI assistant with subagent support
- **Features**: Code generation, debugging, specialized subagents for different tasks
- **Subagents**: 46+ specialized agents for various development tasks
- **AgentAPI**: ✅ Supported
- **Documentation**: [View Module](https://registry.coder.com/modules/claude-code/coder)

#### Goose

- **Module**: `registry.coder.com/coder/goose/coder`
- **Description**: AI-powered development assistant with toolkit integration
- **Features**: Code analysis, generation, development workflow automation
- **Toolkits**: Extensible toolkit system for custom workflows
- **AgentAPI**: ✅ Supported
- **Documentation**: [View Module](https://registry.coder.com/modules/goose/coder)

#### Amazon Q

- **Module**: `registry.coder.com/coder/amazon-q/coder`
- **Description**: Amazon's AI coding assistant with AWS integration
- **Features**: AWS-integrated development, MCP support, comprehensive CLI integration
- **Version**: v2.0.0 (Major rewrite with AgentAPI support)
- **AgentAPI**: ✅ Supported
- **Documentation**: [View Module](https://registry.coder.com/modules/amazon-q/coder)

#### Cursor IDE

- **Module**: `registry.coder.com/coder/cursor/coder`
- **Description**: Launch Cursor IDE with AI-powered development features
- **Features**: One-click IDE launch, folder support, recent workspace access
- **Type**: IDE Integration (not CLI agent)
- **AgentAPI**: ❌ Not applicable (IDE launcher)
- **Documentation**: [View Module](https://registry.coder.com/modules/cursor/coder)

### Experimental AI Agents (`coder-labs` namespace)

#### Gemini

- **Module**: `registry.coder.com/coder-labs/gemini/coder-labs`
- **Description**: Google's Gemini AI model for code assistance
- **Features**: Multi-modal AI assistance, code generation, analysis
- **Version**: v1.1.0 (Cleaned up and refactored)
- **AgentAPI**: ✅ Supported
- **Documentation**: [View Module](https://registry.coder.com/modules/gemini/coder-labs)

#### OpenAI Codex

- **Module**: `registry.coder.com/coder-labs/codex/coder-labs`
- **Description**: OpenAI's Codex model for code generation and completion
- **Features**: Code completion, generation, natural language to code translation
- **Implementation**: Rust-based CLI with comprehensive task reporting
- **AgentAPI**: ✅ Supported
- **Documentation**: [View Module](https://registry.coder.com/modules/codex/coder-labs)

#### Sourcegraph Amp

- **Module**: `registry.coder.com/coder-labs/sourcegraph-amp/coder-labs`
- **Description**: Sourcegraph's AI-powered code search and analysis tool
- **Features**: Code search, analysis, AI-powered development insights
- **Integration**: Full task prompt support and system prompt configuration
- **AgentAPI**: ✅ Supported
- **Documentation**: [View Module](https://registry.coder.com/modules/sourcegraph-amp/coder-labs)

#### Cursor CLI

- **Module**: `registry.coder.com/coder-labs/cursor-cli/coder-labs`
- **Description**: Cursor CLI for AI-assisted development
- **Features**: Command-line interface for Cursor's AI capabilities, MCP settings integration
- **Installation**: Automatic via npm with Node.js bootstrapping
- **AgentAPI**: ✅ Supported (cursor-agent)
- **Documentation**: [View Module](https://registry.coder.com/modules/cursor-cli/coder-labs)

#### Auggie

- **Module**: `registry.coder.com/coder-labs/auggie/coder-labs`
- **Description**: AI coding assistant with extensive configuration options
- **Features**: Task automation, MCP server integration, configurable AI models
- **Configuration**: Supports custom prompts, workspace rules, and model selection
- **AgentAPI**: ✅ Supported
- **Documentation**: [View Module](https://registry.coder.com/modules/auggie/coder-labs)

### Community Modules

#### Docker Claude Template

- **Template**: `registry.coder.com/sharkymark/docker-claude/sharkymark`
- **Description**: Docker-based template with Claude integration
- **Type**: Complete workspace template
- **Maintainer**: Community (sharkymark)

## Module Features

### Common Features

All AI agent modules provide:

- **🚀 One-Click Setup**: Automatic installation and configuration
- **🌐 Web Interface**: AgentAPI integration for browser-based chat
- **📋 Task Integration**: Seamless Coder Tasks support with status reporting
- **🔧 Configurable**: Extensive customization options
- **📝 Documentation**: Comprehensive usage guides and examples
- **🧪 Tested**: Full test coverage with Terraform and TypeScript tests

### AgentAPI Integration

Modules with AgentAPI support provide:

- **Interactive Chat**: Web-based chat interface
- **Task Reporting**: Automatic status updates to Coder Tasks UI
- **Health Checks**: Agent status monitoring
- **File Context**: Share workspace files with AI agents
- **Custom Prompts**: System and task prompt configuration

## Usage Patterns

### Basic Usage

```terraform
module "ai_agent" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/<agent>/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

### With API Key Configuration

```terraform
variable "ai_api_key" {
  type        = string
  description = "API key for AI service"
  sensitive   = true
}

module "ai_agent" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/<agent>/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  api_key  = var.ai_api_key
}
```

### With Task Prompt Support

```terraform
data "coder_parameter" "ai_prompt" {
  name        = "AI Prompt"
  description = "Initial prompt for the AI agent"
  type        = "string"
  default     = ""
  mutable     = true
}

module "ai_agent" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/coder/<agent>/coder"
  version     = "1.0.0"
  agent_id    = coder_agent.main.id
  ai_prompt   = data.coder_parameter.ai_prompt.value
}
```

## Prerequisites

### Required Modules

Most AI agent modules require:

```terraform
module "coder_login" {
  source   = "registry.coder.com/modules/coder-login/coder"
  agent_id = coder_agent.main.id
}
```

### Runtime Dependencies

- **Node.js**: Automatically installed via NVM for npm-based agents
- **Python**: Required for Python-based agents (aider, goose)
- **Git**: Required for git-aware agents
- **Network Access**: Required for API-based agents

## Configuration Best Practices

### Environment Variables

Use `coder_env` resources instead of inline exports:

```terraform
# ✅ Good
resource "coder_env" "api_key" {
  agent_id = coder_agent.main.id
  name     = "OPENAI_API_KEY"
  value    = var.openai_api_key
}

# ❌ Avoid
resource "coder_agent" "main" {
  env = {
    OPENAI_API_KEY = var.openai_api_key
  }
}
```

### System Prompts

Configure system prompts for consistent behavior:

```terraform
resource "coder_env" "system_prompt" {
  agent_id = coder_agent.main.id
  name     = "AI_SYSTEM_PROMPT"
  value    = <<-EOT
    You are a helpful coding assistant.
    Always log task status to Coder.
    Focus on clean, maintainable code.
  EOT
}
```

### Namespace Guidelines

- **`coder`**: Stable, production-ready modules maintained by Coder
- **`coder-labs`**: Experimental modules, may have breaking changes
- **Community**: Third-party modules, varying maintenance levels

## Development Workflow

### Adding New AI Agent Modules

1. **AgentAPI Support**: First add agent support to [coder/agentapi](https://github.com/coder/agentapi)
2. **Module Creation**: Create module in appropriate namespace
3. **Testing**: Add comprehensive tests (`.tftest.hcl` and `.test.ts`)
4. **Documentation**: Include detailed README with examples
5. **Review**: Follow [contributing guidelines](CONTRIBUTING.md)

### Module Structure

```
registry/<namespace>/modules/<agent>/
├── main.tf              # Terraform configuration
├── README.md            # Documentation
├── main.test.ts         # TypeScript tests
├── <agent>.tftest.hcl   # Terraform tests
├── scripts/
│   ├── install.sh       # Installation script
│   └── start.sh         # Startup script
└── testdata/
    └── <agent>-mock.sh  # Mock for testing
```

## Troubleshooting

### Common Issues

1. **Module Not Found**: Check namespace and module name spelling
2. **Agent Installation Fails**: Verify network access and dependencies
3. **AgentAPI Connection**: Check port configuration and firewall settings
4. **Task Reporting**: Ensure proper prompt parameter configuration

### Debug Information

Module logs are typically located at:

```
/home/coder/.<module-name>-module/
├── install.log
├── agentapi-start.log
└── <agent>-debug.log
```

### Getting Help

- **Issues**: [GitHub Issues](https://github.com/coder/registry/issues)
- **Discussions**: [GitHub Discussions](https://github.com/coder/registry/discussions)
- **Discord**: [Coder Community](https://discord.gg/coder)
- **Documentation**: [Coder Docs](https://coder.com/docs)

## Contributing

We welcome contributions for new AI agent modules! Please:

1. Review the [contributing guidelines](CONTRIBUTING.md)
2. Check existing issues for planned agents
3. Follow the module structure and testing requirements
4. Ensure AgentAPI support is available
5. Submit a PR with comprehensive documentation

### Bounty Program

Some AI agent modules are part of our bounty program. Look for issues labeled `🙋 Bounty claim` for opportunities to contribute and earn rewards.

