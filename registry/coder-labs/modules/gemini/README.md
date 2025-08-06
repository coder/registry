---
display_name: Gemini CLI
description: Run Gemini CLI in your workspace for AI pair programming
icon: ../../../../.icons/gemini.svg
verified: true
tags: [agent, gemini, ai, google, tasks]
---

# Gemini CLI

Run [Gemini CLI](https://github.com/google-gemini/gemini-cli) in your workspace to access Google's Gemini AI models for interactive coding assistance and automated task execution.

```tf
module "gemini" {
  source   = "registry.coder.com/coder-labs/gemini/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

## Features

- **Interactive AI Assistance**: Run Gemini CLI directly in your terminal for coding help
- **Automated Task Execution**: Execute coding tasks automatically via AgentAPI integration
- **Multiple AI Models**: Support for Gemini 2.5 Pro, Flash, and other Google AI models
- **API Key Integration**: Seamless authentication with Gemini API
- **MCP Server Integration**: Built-in Coder MCP server for task reporting
- **Persistent Sessions**: Maintain context across workspace sessions

## Prerequisites

- Node.js and npm will be installed automatically if not present
- The [Coder Login](https://registry.coder.com/modules/coder/coder-login) module is required

## Examples

### Basic setup

```tf
variable "gemini_api_key" {
  type        = string
  description = "Gemini API key"
  sensitive   = true
}

module "gemini" {
  source         = "registry.coder.com/coder-labs/gemini/coder"
  version        = "1.1.0"
  agent_id       = coder_agent.example.id
  gemini_api_key = var.gemini_api_key
  folder         = "/home/coder/project"
}
```

This basic setup will:

- Install Gemini CLI in the workspace
- Configure authentication with your API key
- Set Gemini to run in `/home/coder/project` directory
- Enable interactive use from the terminal
- Set up MCP server integration for task reporting

### Automated task execution (Experimental)

> This functionality is in early access and is still evolving.
> For now, we recommend testing it in a demo or staging environment,
> rather than deploying to production
>
> Learn more in [the Coder documentation](https://coder.com/docs/ai-coder)

```tf
variable "gemini_api_key" {
  type        = string
  description = "Gemini API key"
  sensitive   = true
}

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.example.id
}

data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Task prompt for automated Gemini execution"
  mutable     = true
}

module "gemini" {
  count                = data.coder_workspace.me.start_count
  source               = "registry.coder.com/coder-labs/gemini/coder"
  version              = "1.1.0"
  agent_id             = coder_agent.example.id
  gemini_api_key       = var.gemini_api_key
  gemini_model         = "gemini-2.5-flash"
  folder               = "/home/coder/project"
  task_prompt          = data.coder_parameter.ai_prompt.value
  enable_yolo_mode     = true # Auto-approve all tool calls for automation
  gemini_system_prompt = <<-EOT
    You are a helpful coding assistant. Always explain your code changes clearly.
    YOU MUST REPORT ALL TASKS TO CODER.
  EOT
}
```

> [!WARNING]
> YOLO mode automatically approves all tool calls without user confirmation. The agent has access to your machine's file system and terminal. Only enable in trusted, isolated environments.

### Using Vertex AI (Enterprise)

For enterprise users who prefer Google's Vertex AI platform:

```tf
module "gemini" {
  source         = "registry.coder.com/coder-labs/gemini/coder"
  version        = "1.1.0"
  agent_id       = coder_agent.example.id
  gemini_api_key = var.gemini_api_key
  folder         = "/home/coder/project"
  use_vertexai   = true
}
```

## Troubleshooting

- If Gemini CLI is not found, ensure your API key is valid (`install_gemini` defaults to `true`)
- Check logs in `~/.gemini-module/` for install/start output
- Use the `gemini_api_key` variable to avoid requiring Google sign-in

The module creates log files in the workspace's `~/.gemini-module` directory for debugging purposes.

## References

- [Gemini CLI Documentation](https://github.com/google-gemini/gemini-cli/blob/main/docs/index.md)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/ai-coder)
