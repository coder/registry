---
display_name: Gemini CLI
icon: ../../../../.icons/gemini.svg
description: Run Gemini CLI in your workspace with AgentAPI integration
verified: true
tags: [agent, gemini, ai, google, tasks]
---

# Gemini CLI

Run [Gemini CLI](https://ai.google.dev/gemini-api/docs/cli) in your workspace to access Google's Gemini AI models and perform tasks.

```tf
module "gemini" {
  source         = "registry.coder.com/coder-labs/gemini/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  gemini_api_key = var.gemini_api_key
  install_gemini = true
  gemini_version = "latest"
}
```

## Prerequisites

- Node.js and npm will be installed automatically if not present
- You must add the [Coder Login](https://registry.coder.com/modules/coder-login) module to your template
- A valid [Gemini API key](https://aistudio.google.com/app/apikey)

## Examples

### Run in the background and report tasks

```tf
variable "gemini_api_key" {
  type        = string
  description = "The Gemini API key. Obtain from https://aistudio.google.com/app/apikey"
  sensitive   = true
}

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.15"
  agent_id = coder_agent.example.id
}

data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Write a prompt for Gemini"
  mutable     = true
}

# Set the prompt for Gemini via environment variables
resource "coder_agent" "main" {
  # ...
  env = {
    GEMINI_API_KEY               = var.gemini_api_key
    CODER_MCP_GEMINI_TASK_PROMPT = data.coder_parameter.ai_prompt.value
  }
}

module "gemini" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder-labs/gemini/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.main.id
  gemini_api_key = var.gemini_api_key
  gemini_model   = "gemini-2.5-flash"
}
```

## Run standalone

Run Gemini CLI as a standalone app in your workspace without task reporting.

```tf
module "gemini" {
  source         = "registry.coder.com/coder-labs/gemini/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  gemini_api_key = var.gemini_api_key
  install_gemini = true
  gemini_version = "latest"
}
```

> [!IMPORTANT]
> To use tasks with Gemini CLI, ensure you have the `gemini_api_key` variable set, and **you pass the `AI Prompt` Parameter**.
> By default we inject the "theme": "Default" and "selectedAuthType": "gemini-api-key" to your ~/.gemini/settings.json along with the coder mcp server.
> In `gemini_instruction_prompt` and `AI Prompt` text we recommend using (\`\`) backticks instead of quotes to avoid escaping issues. Eg: gemini_instruction_prompt = "Start every response with \`Gemini says:\` "

## Troubleshooting

The module will create log files in the workspace's `~/.gemini-module` directory. If you run into any issues, look at them for more information.

## References

- [Gemini CLI Documentation](https://ai.google.dev/gemini-api/docs/cli)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
