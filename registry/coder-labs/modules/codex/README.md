---
display_name: Codex CLI
icon: ../../../../.icons/openai.svg
description: Run Codex CLI in your workspace with AgentAPI integration
verified: true
tags: [agent, codex, ai, openai, tasks]
---

# Codex CLI

Run Codex CLI in your workspace to access OpenAI's models through the Codex interface, with custom pre/post install scripts. This module integrates with [AgentAPI](https://github.com/coder/agentapi) for Coder Tasks compatibility.

```tf
module "codex" {
  source           = "registry.coder.com/coder-labs/codex/coder"
  version          = "1.0.0"
  agent_id         = coder_agent.example.id
  openai_api_key   = var.openai_api_key
  agentapi_version = "v0.3.2"
}
```

## Prerequisites

- You must add the [Coder Login](https://registry.coder.com/modules/coder-login/coder) module to your template
- OpenAI API key for Codex access

## Usage Example

- Simple usage Example:

```tf
module "codex" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder-labs/codex/coder"
  version             = "1.0.0"
  agent_id            = coder_agent.example.id
  openai_api_key      = "..."
  codex_model         = "o4-mini"
  install_codex       = true
  codex_version       = "latest"
  folder              = "/home/coder/project"
  codex_system_prompt = "You are a helpful coding assistant. Start every response with `Codex says:`"
  agentapi_version    = "v0.3.2"
}
```

- Example usage with Tasks:

```tf
# This
data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Initial prompt for the Codex CLI"
  mutable     = true
}

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.31"
  agent_id = coder_agent.example.id
}

module "codex" {
  source           = "/Users/jkmr/Documents/work/registry/registry/coder-labs/modules/codex"
  agent_id         = coder_agent.example.id
  openai_api_key   = "..."
  ai_prompt        = data.coder_parameter.ai_prompt.value
  agentapi_version = "v0.3.2"
}
```

## How it Works

- **Install**: The module installs Codex CLI and sets up the environment
- **System Prompt**: If `codex_system_prompt` and `folder` are set, creates the directory (if needed) and writes the prompt to `AGENTS.md`
- **Start**: Launches Codex CLI in the specified directory, wrapped by AgentAPI
- **Environment**: Sets `OPENAI_API_KEY` and `CODEX_MODEL` for the CLI (if variables provided)

## Troubleshooting

- Check logs in `/home/coder/.codex-module/` for install/start output
- Ensure your OpenAI API key has access to the specified model

> [!IMPORTANT]
> To use tasks with Codex CLI, ensure you have the `openai_api_key` variable set, and **you create an `ai_prompt` `coder_parameter` and pass it's value to codex `ai_prompt` variable**. [Tasks Template Example](https://registry.coder.com/templates/coder-labs/tasks-docker).
> The module automatically configures Codex with your API key and model preferences.
> Tasks are run with `--dangerously-bypass-approvals-and-sandbox`

## References

- [OpenAI API Documentation](https://platform.openai.com/docs)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
