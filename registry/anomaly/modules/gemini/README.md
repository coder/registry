---
display_name: Gemini
icon: ../../../../.icons/gemini.svg
description: Run Gemini CLI in your workspace with AgentAPI integration
verified: false
tags: [agent, gemini, ai, tasks]
---

# Gemini

Run [Gemini CLI](https://ai.google.dev/gemini-api/docs/cli) in your workspace to access Google's Gemini AI models, with support for background operation, task reporting, and custom pre/post install scripts. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for Coder Tasks compatibility.

```tf
module "gemini" {
  source              = "registry.coder.com/anomaly/gemini/anomaly"
  version             = "1.0.0"
  agent_id            = coder_agent.example.id
  gemini_api_key      = var.gemini_api_key
  gemini_model        = "gemini-1.5-pro-latest"
  install_gemini      = true
  gemini_version      = "latest"
  agentapi_version    = "latest"
}
```

## Prerequisites

- You must add the [Coder Login](https://registry.coder.com/modules/coder-login/coder) module to your template
- Node.js and npm will be installed automatically if not present

## Features

- **Gemini CLI**: Installs and runs Gemini CLI in your workspace
- **AgentAPI Integration**: Enables Coder Tasks and background operation
- **Customizable**: Choose Gemini model, version, and settings
- **Pre/Post Install Hooks**: Run custom scripts before/after install
- **Vertex AI Support**: Optionally use Google Vertex AI endpoints


## Usage Example

```tf
variable "gemini_api_key" {
  type        = string
  description = "Gemini API key"
  sensitive   = true
}

module "gemini" {
  count             = data.coder_workspace.me.start_count
  source            = "registry.coder.com/anomaly/gemini/anomaly"
  version           = "1.0.0"
  agent_id          = coder_agent.example.id
  gemini_api_key    = var.gemini_api_key # we recommend providing this parameter inorder to have a smoother experience (i.e. no google sign-in)
  gemini_model      = "gemini-1.5-pro-latest"
  install_gemini    = true
  gemini_version    = "latest"
}
```

## How it Works

- **Install**: The module installs Gemini CLI using npm (installs Node.js if needed)
- **Configure**: Optionally writes your settings JSON to `~/.gemini/settings.json`
- **Start**: Launches Gemini CLI in the specified directory, wrapped by AgentAPI for Coder Tasks compatibility
- **Environment**: Sets `GOOGLE_API_KEY`, `GOOGLE_GENAI_USE_VERTEXAI`, `GEMINI_MODEL`, and `GEMINI_START_DIRECTORY` for the CLI

## Customization

- **Custom Pre/Post Install Scripts**: Use `pre_install_script` and `post_install_script` to run custom shell commands before or after install
- **Gemini Settings**: Pass a JSON string to `gemini_settings_json` to configure Gemini CLI (written to `~/.gemini/settings.json`)

## Troubleshooting

- If Gemini CLI is not found, ensure `install_gemini = true` and your API key is valid
- Node.js and npm are installed automatically if missing
- Check logs in `/home/coder/.gemini-module/` for install/start output

## References

- [Gemini CLI Documentation](https://ai.google.dev/gemini-api/docs/cli)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
