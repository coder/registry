---
display_name: Amp
icon: ../../../../.icons/sourcegraph-amp.svg
description: Sourcegraph's AI coding agent with deep codebase understanding and intelligent code search capabilities
verified: true
tags: [agent, sourcegraph, amp, ai, tasks]
---

# Sourcegraph Amp CLI

Run [Amp CLI](https://ampcode.com/) in your workspace to access Sourcegraph's AI-powered code search and analysis tools, with AgentAPI integration for seamless Coder Tasks support.

```tf
module "amp-cli" {
  source                  = "registry.coder.com/coder-labs/sourcegraph-amp/coder"
  version                 = "2.0.2"
  agent_id                = coder_agent.main.id
  sourcegraph_amp_api_key = var.sourcegraph_amp_api_key
  install_sourcegraph_amp = true
  agentapi_version        = "latest"
}
```

## Prerequisites

- **Default (official installer)**: No prerequisites - the official installer includes its own runtime (Bun)
- **npm installation (`install_via_npm = true`)**: Requires Node.js and npm to be installed before Amp installation
  - Required for Alpine Linux or other musl-based systems
  - Ensure Node.js and npm are available in your workspace image or via earlier provisioning steps

## Usage Example

```tf
data "coder_parameter" "ai_prompt" {
  name        = "AI Prompt"
  description = "Write an initial prompt for Amp to work on."
  type        = "string"
  default     = ""
  mutable     = true
}

variable "amp_api_key" {
  type        = string
  description = "Sourcegraph Amp API key. Get one at https://ampcode.com/settings"
  sensitive   = true
}

module "amp-cli" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder-labs/sourcegraph-amp/coder"
  amp_version        = "2.0.1"
  agent_id           = coder_agent.main.id
  amp_api_key        = var.amp_api_key # recommended for tasks usage
  workdir            = "/home/coder/project"
  instruction_prompt = <<-EOT
      # Instructions
      - Start every response with `amp > `
EOT
  ai_prompt          = data.coder_parameter.ai_prompt.value
  base_amp_config = jsonencode({
    "amp.anthropic.thinking.enabled"              = true
    "amp.todos.enabled"                           = true
    "amp.tools.stopTimeout"                       = 600
    "amp.git.commit.ampThread.enabled"            = true
    "amp.git.commit.coauthor.enabled"             = true
    "amp.terminal.commands.nodeSpawn.loadProfile" = "daily"
    "amp.permissions" = [
      { "tool" : "mcp__coder__*", "action" : "allow" },
      { "tool" : "Bash", "action" : "allow", "context" : "thread" },
      { "tool" : "Bash", "matches" : { "cmd" : ["rm -rf /*", "rm -rf ~/*"] }, "action" : "reject", "context" : "subagent" },
      { "tool" : "edit_file", "action" : "allow" },
      { "tool" : "write_file", "action" : "allow" },
      { "tool" : "read_file", "action" : "allow" },
      { "tool" : "Grep", "action" : "allow" }
    ]
  })
}
```

## Troubleshooting

- If `amp` is not found, ensure `install_amp = true` and your API key is valid
- Logs are written under `/home/coder/.amp-module/` (`install.log`, `agentapi-start.log`) for debugging
- If AgentAPI fails to start, verify that your container has network access and executable permissions for the scripts

> [!IMPORTANT]
> To use tasks with Amp CLI, create a `coder_parameter` named `"AI Prompt"` and pass its value to the amp-cli module's `ai_prompt` variable. The `folder` variable is required for the module to function correctly.
> For using **Coder Tasks** with Amp CLI, make sure to set `amp_api_key`.
> This ensures task reporting and status updates work seamlessly.

## References

- [Amp CLI Documentation](https://ampcode.com/manual)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
