---
display_name: Gemini CLI
icon: ../../../../.icons/gemini.svg
description: Run Gemini CLI in your workspace with AgentAPI integration
verified: true
tags: [agent, gemini, ai, google, tasks]
---

# Gemini CLI

Run [Gemini CLI](https://ai.google.com/docs/gemini/tools/cli) in your workspace to access Google's Gemini AI models, and custom pre/post install scripts. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for Coder Tasks compatibility.

## Getting Started

1. **Get a Gemini API Key**:
   - Visit [Google AI Studio](https://makersuite.google.com/app/apikey)
   - Create a new API key or use an existing one
   - The API key starts with "AIza..."

2. **Add the required variable to your template**:

```tf
variable "gemini_api_key" {
  type        = string
  description = "Gemini API key (get one at https://makersuite.google.com/app/apikey)"
  sensitive   = true
}
```

> [!NOTE]
> The `gemini_api_key` variable is **strongly recommended** for automatic setup and task execution. Without it, you'll need to authenticate manually each time Gemini starts.

3. **Add the module**:

```tf
module "gemini" {
  source           = "registry.coder.com/coder-labs/gemini/coder"
  version          = "1.0.0"
  agent_id         = coder_agent.example.id
  gemini_api_key   = var.gemini_api_key
  gemini_model     = "gemini-2.5-pro"
  install_gemini   = true
  gemini_version   = "latest"
  agentapi_version = "latest"
}
```

## Prerequisites

- You must add the [Coder Login](https://registry.coder.com/modules/coder-login/coder) module to your template
- Node.js and npm will be installed automatically if not present

## Usage Example

**Simple setup with API key**:

```tf
variable "gemini_api_key" {
  type        = string
  description = "Gemini API key (get one at https://makersuite.google.com/app/apikey)"
  sensitive   = true
}

module "gemini" {
  count                     = data.coder_workspace.me.start_count
  source                    = "registry.coder.com/coder-labs/gemini/coder"
  version                   = "1.0.0"
  agent_id                  = coder_agent.example.id
  gemini_api_key            = var.gemini_api_key # Required for automated setup
  gemini_model              = "gemini-2.5-flash"
  install_gemini           = true
  gemini_version           = "latest"
  auto_approve             = true    # Automatically approve API key usage
  yolo_mode               = true    # Enable faster responses without confirmations
  folder                  = "/home/coder/project" # Custom working directory
  gemini_system_prompt    = "Start every response with `Gemini says:`"
}
```

**Advanced setup with AI Prompt parameter (for task automation)**:

```tf
variable "gemini_api_key" {
  type        = string
  description = "Gemini API key (get one at https://makersuite.google.com/app/apikey)"
  sensitive   = true
}

data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Initial prompt for the Gemini CLI"
  mutable     = true
}

data "coder_parameter" "system_prompt" {
  type        = "string"
  name        = "System Prompt"
  default     = "You are a helpful assistant that can help with code."
  description = "System prompt for Gemini"
  mutable     = true
}

module "gemini" {
  count                     = data.coder_workspace.me.start_count
  source                    = "registry.coder.com/coder-labs/gemini/coder"
  version                   = "1.0.0"
  agent_id                  = coder_agent.example.id
  gemini_api_key            = var.gemini_api_key
  ai_prompt                 = data.coder_parameter.ai_prompt.value
  gemini_model              = "gemini-2.5-flash"
  install_gemini           = true
  gemini_version           = "latest"
  auto_approve             = true
  yolo_mode               = true
  folder                  = "/home/coder/project"
  gemini_system_prompt    = data.coder_parameter.system_prompt.value
}
```

## How it Works

- **Install**: The module installs Gemini CLI using npm (installs Node.js via NVM if needed)
- **Configuration**: Automatically configures `~/.gemini/settings.json` with optimal settings for Coder integration
- **System Prompt**: If `gemini_system_prompt` is provided, creates the working directory and writes the prompt to `GEMINI.md`
- **Start**: Launches Gemini CLI in the specified directory (default: `/home/coder/project`), wrapped by AgentAPI
- **Environment**: Sets `GEMINI_API_KEY`, `GOOGLE_GENAI_USE_VERTEXAI`, `GEMINI_MODEL` for the CLI
- **Task Integration**: When an AI Prompt is provided, Gemini receives a task-focused prompt for better integration with Coder's task system

## Troubleshooting

- **Gemini CLI not found**: Ensure `install_gemini = true` and your API key is valid
- **Node.js/npm issues**: Node.js and npm are installed automatically if missing (using NVM)
- **Installation logs**: Check logs in `/home/coder/.gemini-module/` for install/start output
- **API key setup**: We highly recommend using the `gemini_api_key` variable for smooth operation without manual sign-in
- **Approval/confirmation prompts**: 
  - Set `auto_approve = true` to automatically approve API key usage
  - Set `yolo_mode = true` to enable faster responses without confirmation prompts
  - These settings are configured in `~/.gemini/settings.json` automatically
- **Working directory**: By default, Gemini starts in `/home/coder/project`. Change with the `folder` variable
- **Custom settings**: Use `gemini_settings_json` to override default settings, but note that `auto_approve` and `yolo_mode` variables are preferred for common configurations

> [!IMPORTANT]
> To use tasks with Gemini CLI, ensure you have the `gemini_api_key` variable set, and **pass either the `ai_prompt` variable or use the `AI Prompt` parameter**.
> By default we inject the "theme": "Default", "selectedAuthType": "gemini-api-key", "autoApproveApiKey": true, and various yolo mode settings to your ~/.gemini/settings.json along with the coder mcp server.
> In `gemini_system_prompt` and AI prompt text we recommend using (\`\`) backticks instead of quotes to avoid escaping issues. Eg: gemini_system_prompt = "Start every response with \`Gemini says:\` "

## References

- [Gemini CLI Documentation](https://ai.google.dev/gemini-api/docs/cli)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)

## Summary of UX Improvements

This module provides:
- ✅ **Automatic API key configuration** - Set `gemini_api_key` variable for seamless operation
- ✅ **Smart defaults** - Runs in `/home/coder/project` with auto-approval and yolo mode enabled
- ✅ **Flexible prompting** - Supports both system prompts (via `gemini_system_prompt`) and task prompts (via `ai_prompt`)
- ✅ **Clear error messages** - Helpful guidance when API key is missing
- ✅ **Consistent with Claude Code** - Similar parameter patterns for easy migration between AI modules
