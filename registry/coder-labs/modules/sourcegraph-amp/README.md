---
display_name: Amp CLI
icon: ../../../../.icons/sourcegraph-amp.svg
description: Sourcegraph's AI coding agent with deep codebase understanding and intelligent code search capabilities
verified: false
tags: [agent, sourcegraph, amp, ai, tasks]
---

# Sourcegraph Amp CLI

Run [Amp CLI](https://ampcode.com/) in your workspace to access Sourcegraph's AI-powered code search and analysis tools, with AgentAPI integration for seamless Coder Tasks support.

```tf
module "amp-cli" {
  source                  = "registry.coder.com/coder-labs/sourcegraph-amp/coder"
  version                 = "2.0.0"
  agent_id                = coder_agent.example.id
  sourcegraph_amp_api_key = var.sourcegraph_amp_api_key
  folder                  = "/home/coder/project"
}
```

## Prerequisites

- Include the [Coder Login](https://registry.coder.com/modules/coder-login/coder) module in your template
- **Node.js and npm must be sourced/available before the amp cli installs** - ensure they are installed in your workspace image or via earlier provisioning steps

## Usage Example

```tf
data "coder_parameter" "ai_prompt" {
  name        = "AI Prompt"
  description = "Write an initial prompt for Amp to work on."
  type        = "string"
  default     = ""
  mutable     = true
}

variable "sourcegraph_amp_api_key" {
  type        = string
  description = "Sourcegraph Amp API key. Get one at https://ampcode.com/settings"
  sensitive   = true
}

module "amp-cli" {
  count                   = data.coder_workspace.me.start_count
  source                  = "registry.coder.com/coder-labs/sourcegraph-amp/coder"
  sourcegraph_amp_version = "2.0.0"
  agent_id                = coder_agent.example.id
  sourcegraph_amp_api_key = var.sourcegraph_amp_api_key # recommended for tasks usage
  install_sourcegraph_amp = true
  folder                  = "/home/coder/project"
  system_prompt           = <<-EOT
      You are an Amp assistant that helps developers debug and write code efficiently.

      Always log task status to Coder.
EOT
  ai_prompt               = data.coder_parameter.ai_prompt.value

}
```

## Troubleshooting

- If `amp` is not found, ensure `install_sourcegraph_amp = true` and your API key is valid
- Logs are written under `/home/coder/.sourcegraph-amp-module/` (`install.log`, `agentapi-start.log`) for debugging
- If AgentAPI fails to start, verify that your container has network access and executable permissions for the scripts

> [!IMPORTANT]
> To use tasks with Amp CLI, create a `coder_parameter` named `"AI Prompt"` and pass its value to the amp-cli module's `ai_prompt` variable. The `folder` variable is required for the module to function correctly.
> For using **Coder Tasks** with Amp CLI, make sure to set `sourcegraph_amp_api_key`.
> This ensures task reporting and status updates work seamlessly.

## References

- [Amp CLI Documentation](https://ampcode.com/manual)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
