---
display_name: Aider
description: Run Aider AI pair programming in your workspace
icon: ../../../../.icons/aider.svg
verified: true
tags: [agent, ai, aider]
---

# Aider

Run [Aider](https://aider.chat) AI pair programming in your workspace. This module installs Aider with AgentAPI for seamless Coder Tasks Support.

```tf
module "aider" {
  source   = "registry.coder.com/coder/aider/coder"
  agent_id = coder_agent.example.id
  ai_api_key = var.api_key
  install_aider = true
  ai_provider = "google"
  ai_model = "gemini"
  install_agentapi = true
}
```

## Prerequisites

- Include the [Coder Login](https://registry.coder.com/modules/coder-login/coder) module in your template
- pipx is automatically installed if not already available


## Usage Example

```tf
data "coder_parameter" "ai_prompt" {
  name        = "AI Prompt"
  description = "Write an initial prompt for Aider to work on."
  type        = "string"
  default     = ""
  mutable     = true

}

variable "gemini_api_key" {
  type        = string
  description = "Gemini API key"
  sensitive   = true
}

module "aider" {
  source   = "registry.coder.com/coder/aider/coder"
  agent_id = coder_agent.example.id
  ai_api_key = var.gemini_api_key
  install_aider = true
  ai_provider = "google"
  ai_model = "gemini"
  install_agentapi = true
  task_prompt = data.coder_parameter.ai_prompt.value
  system_prompt = "..."
}
```

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
  agent_id            = coder_agent.example.id
  ai_provider         = "custom"
  custom_env_var_name = "MY_CUSTOM_API_KEY"
  ai_model            = "custom-model"
  ai_api_key          = var.custom_api_key
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
- Logs are written under `/home/coder/.aider-module/` (`install.log`, `agentapi-start.log`) for debugging
- If AgentAPI fails to start, verify that your container has network access and executable permissions for the scripts

> [!IMPORTANT]
> For using **Coder Tasks** with Aider, make sure to pass the `AI Prompt` parameter and set `ai_api_key`.
> This ensures task reporting and status updates work seamlessly.

## References

- [Aider Documentation](https://aider.chat/docs)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
