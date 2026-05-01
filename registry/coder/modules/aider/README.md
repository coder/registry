---
display_name: Aider
description: Install and configure Aider AI pair programming in your workspace
icon: ../../../../.icons/aider.svg
verified: true
tags: [agent, ai, aider]
---

# Aider

Install and configure [Aider](https://aider.chat) AI pair programming in your workspace. Starting Aider is left to the caller (template command, IDE launcher, or a custom `coder_script`).

```tf
locals {
  aider_workdir = "/home/coder/project"
}

module "aider" {
  source      = "registry.coder.com/coder/aider/coder"
  version     = "2.0.2"
  agent_id    = coder_agent.main.id
  api_key     = xxxx-xxxx-xxxx-xxxx"
  ai_provider = "google"
  model       = "gemini"
}

resource "coder_app" "aider" {
  agent_id     = coder_agent.main.id
  slug         = "aider"
  display_name = "Aider"
  icon         = "/icon/aider.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/bin/bash
    set -e
    cd ${local.aider_workdir}
    aider --model module.aider.model
  EOT
}
```
> [!WARNING]
> If upgrading from v2.x.x of this module: v3 is a major refactor that drops support for [Coder Tasks](https://coder.com/docs/ai-coder/tasks). We plan to add those back in a follow-up. Keep using v2.x.x if you depend on them.

## Prerequisites

- pipx is automatically installed if not already available

### Using a custom provider

```tf
variable "custom_api_key" {
  type        = string
  description = "Custom provider API key"
  sensitive   = true
}

module "aider" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/aider/coder"
  version             = "2.0.2"
  agent_id            = coder_agent.main.id
  workdir             = "/home/coder"
  ai_provider         = "custom"
  custom_env_var_name = "OPENROUTER_API_KEY"
  model               = "openrouter/anthropic/claude-3-haiku"
  api_key             = var.custom_api_key
}
```

### Available AI Providers and Models

Aider supports various providers and models, and this module integrates directly with Aider's built-in model aliases:

| Provider      | Example Models/Aliases                        | Default Model          |
| ------------- | --------------------------------------------- | ---------------------- |
| **anthropic** | "sonnet" (Claude 3.7 Sonnet), "opus", "haiku" | "sonnet"               |
| **openai**    | "4o" (GPT-4o), "4" (GPT-4), "3.5-turbo"       | "4o"                   |
| **azure**     | Azure OpenAI models                           | "gpt-4"                |
| **google**    | "gemini" (Gemini Pro), "gemini-2.5-pro"       | "gemini-2.5-pro"       |
| **cohere**    | "command-r-plus", etc.                        | "command-r-plus"       |
| **mistral**   | "mistral-large-latest"                        | "mistral-large-latest" |
| **ollama**    | "llama3", etc.                                | "llama3"               |
| **custom**    | Any model name with custom ENV variable       | -                      |

For a complete and up-to-date list of supported aliases and models, please refer to the [Aider LLM documentation](https://aider.chat/docs/llms.html) and the [Aider LLM Leaderboards](https://aider.chat/docs/leaderboards.html) which show performance comparisons across different models.

## Troubleshooting

- If `aider` is not found, ensure `install_aider = true` and your API key is valid
- Logs are written under `.coder-modules/coder/aider/logs/install.log` (`install.log`) for debugging

## References

- [Aider Documentation](https://aider.chat/docs)
