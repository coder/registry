---
display_name: Sourcegraph AMP
icon: ../../../../.icons/sourcegraph-amp.svg
description: Run Sourcegraph AMP CLI in your workspace with AgentAPI integration
verified: false
tags: [agent, sourcegraph, amp, ai, tasks]
---

# Sourcegraph AMP CLI

Run [Sourcegraph AMP CLI](https://sourcegraph.com/amp) in your workspace to access Sourcegraph's AI-powered code search and analysis tools, with AgentAPI integration for seamless Coder Tasks support.

```tf
module "sourcegraph_amp" {
  source                  = "registry.coder.com/coder-labs/sourcegraph_amp/coder"
  version                 = "1.0.0"
  agent_id                = coder_agent.example.id
  sourcegraph_amp_api_key = var.sourcegraph_amp_api_key
  install_sourcegraph_amp = true
  agentapi_version        = "latest"
}
```

## Prerequisites

- Include the [Coder Login](https://registry.coder.com/modules/coder-login/coder) module in your template
- Node.js and npm are automatically installed (via NVM) if not already available

## Usage Example

```tf
data "coder_parameter" "ai_prompt" {
  name        = "AI Prompt"
  description = "Write an initial prompt for AMP to work on."
  type        = "string"
  default     = ""
  mutable     = true

}

# Set system prompt for Sourcegraph Amp via environment variables
resource "coder_agent" "main" {
  # ...
  env = {
    SOURCEGRAPH_AMP_SYSTEM_PROMPT = <<-EOT
      You are an AMP assistant that helps developers debug and write code efficiently.

      Always log task status to Coder.
    EOT
    SOURCEGRAPH_AMP_TASK_PROMPT   = data.coder_parameter.ai_prompt.value
  }
}

variable "sourcegraph_amp_api_key" {
  type        = string
  description = "Sourcegraph AMP API key"
  sensitive   = true
}

module "sourcegraph_amp" {
  count                   = data.coder_workspace.me.start_count
  source                  = "registry.coder.com/coder-labs/sourcegraph_amp/coder"
  version                 = "1.0.0"
  agent_id                = coder_agent.example.id
  sourcegraph_amp_api_key = var.sourcegraph_amp_api_key # recommended for authenticated usage
  install_sourcegraph_amp = true
}
```

## How it Works

- **Install**: Installs Sourcegraph AMP CLI using npm (installs Node.js via NVM if required)
- **Start**: Launches AMP CLI in the specified directory, wrapped with AgentAPI to enable tasks and AI interactions
- **Environment Variables**: Sets `SOURCEGRAPH_AMP_API_KEY` and `SOURCEGRAPH_AMP_START_DIRECTORY` for the CLI execution

## Troubleshooting

- If `amp` is not found, ensure `install_sourcegraph_amp = true` and your API key is valid
- Logs are written under `/home/coder/.sourcegraph-amp-module/` (`install.log`, `agentapi-start.log`) for debugging
- If AgentAPI fails to start, verify that your container has network access and executable permissions for the scripts

> [!IMPORTANT]
> For using **Coder Tasks** with Sourcegraph AMP, make sure to pass the `AI Prompt` parameter and set `sourcegraph_amp_api_key`.
> This ensures task reporting and status updates work seamlessly.

## References

- [Sourcegraph AMP Documentation](https://ampcode.com/manual)
- [AgentAPI Documentation](https://github.com/coder/agentapi)
- [Coder AI Agents Guide](https://coder.com/docs/tutorials/ai-agents)
