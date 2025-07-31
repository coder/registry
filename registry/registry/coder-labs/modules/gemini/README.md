---
display_name: Gemini CLI
icon: ../../../../.icons/gemini.svg
description: Run Gemini CLI in your workspace with AgentAPI integration
verified: true
tags: [agent, gemini, ai, google, tasks]
---

# Gemini CLI

Run [Gemini CLI](https://ai.google.dev/gemini-api/docs/quickstart) in your workspace to access Google's Gemini AI models, and custom pre/post install scripts. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for Coder Tasks compatibility.

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

## Getting a Gemini API Key

1. Go to [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Sign in with your Google account
3. Click "Create API Key"
4. Copy the generated API key
5. Use this key in the `gemini_api_key` variable

> **Important**: The API key is required for the best experience. Without it, you'll need to sign in to Google each time.

## Usage Example

- Example 1:

```tf
variable "gemini_api_key" {
  type        = string
  description = "Gemini API key from https://aistudio.google.com/app/apikey"
  sensitive   = true
}

module "gemini" {
  count                     = data.coder_workspace.me.start_count
  source                    = "registry.coder.com/coder-labs/gemini/coder"
  version                   = "1.0.0"
  agent_id                  = coder_agent.example.id
  gemini_api_key            = var.gemini_api_key # Required for smooth experience
  gemini_model              = "gemini-2.5-flash"
  install_gemini            = true
  gemini_version            = "latest"
  gemini_system_prompt      = "Start every response with `Gemini says:`"
  folder                    = "/workspace" # Change default directory
}
```

## Configuration Options

### Yolo Mode (Automatic Approvals)

To enable automatic approvals without manual confirmation:

```tf
module "gemini" {
  # ... other configuration
  gemini_settings_json = jsonencode({
    "geminicodeassist.agentYoloMode": true,
    "theme": "Default",
    "selectedAuthType": "gemini-api-key"
  })
}
```

### Custom Directory

By default, Gemini runs in `/home/coder`. To change this:

```tf
module "gemini" {
  # ... other configuration
  folder = "/workspace/my-project"
}
```

## How it Works

- **Install**: The module installs Gemini CLI using npm (installs Node.js via NVM if needed)
- **Configuration**: Sets up `~/.gemini/settings.json` with Coder integration and your preferences
- **Instruction Prompt**: If `gemini_system_prompt` and `folder` are set, creates the directory and writes the prompt to `GEMINI.md`
- **Start**: Launches Gemini CLI in the specified directory, wrapped by AgentAPI
- **Environment**: Sets `GEMINI_API_KEY`, `GOOGLE_GENAI_USE_VERTEXAI`, `GEMINI_MODEL` for the CLI (if variables provided)

## Troubleshooting

- **API Key Issues**: Ensure your API key is valid and from [Google AI Studio](https://aistudio.google.com/app/apikey)
- **Installation Issues**: If Gemini CLI is not found, ensure `install_gemini = true` and your API key is valid
- **Node.js Issues**: Node.js and npm are installed automatically if missing (using NVM)
- **Logs**: Check logs in `/home/coder/.gemini-module/` for install/start output
- **Yolo Mode**: If automatic approvals aren't working, ensure the `gemini_settings_json` includes `"geminicodeassist.agentYoloMode": true`

> [!IMPORTANT]
> To use tasks with Gemini CLI, ensure you have the `gemini_api_key` variable set, and **you pass the `AI Prompt` Parameter**.
> By default we inject the "theme": "Default" and "selectedAuthType": "gemini-api-key" to your ~/.gemini/settings.json along with the coder mcp server.
> In `gemini_system_prompt` and `AI Prompt` text we recommend using (\`\`) backticks instead of quotes to avoid escaping issues. Eg: gemini_system_prompt = "Start every response with \`Gemini says:\` "

## References

- [Gemini API Documentation](https://ai.google.dev/gemini-api/docs/quickstart)
- [Gemini CLI Documentation](https://ai.google.dev/gemini-api/docs/cli)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
