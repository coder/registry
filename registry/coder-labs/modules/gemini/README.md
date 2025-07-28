---
display_name: Gemini CLI
icon: ../../../../.icons/gemini.svg
description: Run Gemini CLI in your workspace with AgentAPI integration
verified: true
tags: [agent, gemini, ai, google, tasks]
---

# Gemini CLI

Run [Gemini CLI](https://ai.google.dev/gemini-api/docs/cli) in your workspace to access Google's Gemini AI models, and custom pre/post install scripts. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for Coder Tasks compatibility.

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

- Example 1:

```tf
variable "gemini_api_key" {
  type        = string
  description = "Gemini API key"
  sensitive   = true
}

module "gemini" {
  count                     = data.coder_workspace.me.start_count
  source                    = "registry.coder.com/coder-labs/gemini/coder"
  version                   = "1.0.0"
  agent_id                  = coder_agent.example.id
  gemini_api_key            = var.gemini_api_key # we recommend providing this parameter inorder to have a smoother experience (i.e. no google sign-in)
  gemini_model              = "gemini-2.5-flash"
  install_gemini            = true
  gemini_version            = "latest"
  gemini_instruction_prompt = "Start every response with `Gemini says:`"
}
```

## How it Works

- **Install**: The module installs Gemini CLI using npm (installs Node.js via NVM if needed)
- **Instruction Prompt**: If `GEMINI_INSTRUCTION_PROMPT` and `GEMINI_START_DIRECTORY` are set, creates the directory (if needed) and writes the prompt to `GEMINI.md`
- **Start**: Launches Gemini CLI in the specified directory, wrapped by AgentAPI
- **Environment**: Sets `GEMINI_API_KEY`, `GOOGLE_GENAI_USE_VERTEXAI`, `GEMINI_MODEL` for the CLI (if variables provided)

## Troubleshooting

- If Gemini CLI is not found, ensure `install_gemini = true` and your API key is valid
- Node.js and npm are installed automatically if missing (using NVM)
- Check logs in `/home/coder/.gemini-module/` for install/start output
- We highly recommend using the `gemini_api_key` variable, this also ensures smooth tasks running without needing to sign in to Google.

> [!IMPORTANT]
> To use tasks with Gemini CLI, ensure you have the `gemini_api_key` variable set, and **you pass the `AI Prompt` Parameter**.
> By default we inject the "theme": "Default" and "selectedAuthType": "gemini-api-key" to your ~/.gemini/settings.json along with the coder mcp server.
> In `gemini_instruction_prompt` and `AI Prompt` text we recommend using (\`\`) backticks instead of quotes to avoid escaping issues. Eg: gemini_instruction_prompt = "Start every response with \`Gemini says:\` "

## References

- [Gemini CLI Documentation](https://ai.google.dev/gemini-api/docs/cli)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
