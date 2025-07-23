---
display_name: Gemini CLI
icon: ../../../../.icons/gemini.svg
description: Run Gemini CLI in your workspace with AgentAPI integration
verified: false
tags: [agent, gemini, ai, google]
---

# Gemini CLI

Run [Gemini CLI](https://ai.google.dev/gemini-api/docs/cli) in your workspace to access Google's Gemini AI models, and custom pre/post install scripts. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for Coder Tasks compatibility.

```tf
module "gemini" {
  source           = "registry.coder.com/anomaly/gemini/anomaly"
  version          = "1.0.0"
  agent_id         = coder_agent.example.id
  gemini_api_key   = var.gemini_api_key
  gemini_model     = "gemini-1.5-pro-latest"
  install_gemini   = true
  gemini_version   = "latest"
  agentapi_version = "latest"
}
```

## Prerequisites

- You must add the [Coder Login](https://registry.coder.com/modules/coder-login/coder) module to your template
- Node.js and npm will be installed automatically if not present

## Usage Example

```tf
variable "gemini_api_key" {
  type        = string
  description = "Gemini API key"
  sensitive   = true
}

module "gemini" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/anomaly/gemini/anomaly"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  gemini_api_key = var.gemini_api_key # we recommend providing this parameter inorder to have a smoother experience (i.e. no google sign-in)
  gemini_model   = "gemini-1.5-pro-latest"
  install_gemini = true
  gemini_version = "latest"
}
```

## How it Works

- **Install**: The module installs Gemini CLI using npm (installs Node.js if needed)
- **Configure**: Optionally writes your settings JSON to `~/.gemini/settings.json`
- **Start**: Launches Gemini CLI in the specified directory, wrapped by AgentAPI
- **Environment**: Sets `GEMINI_API_KEY`, `GOOGLE_GENAI_USE_VERTEXAI`, `GEMINI_MODEL` for the CLI (if variables provided)

## Troubleshooting

- If Gemini CLI is not found, ensure `install_gemini = true` and your API key is valid
- Node.js and npm are installed automatically if missing
- Check logs in `/home/coder/.gemini-module/` for install/start output

## References

- [Gemini CLI Documentation](https://ai.google.dev/gemini-api/docs/cli)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
