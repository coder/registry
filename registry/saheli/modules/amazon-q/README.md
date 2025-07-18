---
display_name: Amazon Q
description: Run Amazon Q with AgentAPI as a web chat interface, with optional Aider integration and Coder Tasks support.
icon: ../../../../.icons/amazon-q.svg
maintainer_github: coder
verified: true
tags: [agent, ai, aws, amazon-q, agentapi, tasks, aider]
---

# Amazon Q

Run [Amazon Q](https://aws.amazon.com/q/) with [AgentAPI](https://github.com/coder/agentapi) as a web chat interface, with optional [Aider](https://aider.chat) integration and full Coder Tasks support. This module provides a modern web interface for Amazon Q with automatic task reporting.

```tf
module "amazon-q" {
  source       = "registry.coder.com/coder/amazon-q/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.example.id
  auth_tarball = var.amazon_q_auth_tarball
}
```

![Amazon-Q with AgentAPI](../../.images/amazon-q-agentapi.png)

## Prerequisites

- You must add the [Coder Login](https://registry.coder.com/modules/coder-login) module to your template
- You must generate an authenticated Amazon Q tarball on another machine:
  ```sh
  cd ~/.local/share/amazon-q && tar -c . | zstd | base64 -w 0
  ```
  Paste the result into the `auth_tarball` variable.
- For Aider mode: Python 3 and pip3 must be installed in your workspace

<details>
<summary><strong>How to generate the Amazon Q auth tarball (step-by-step)</strong></summary>

**1. Install and authenticate Amazon Q on your local machine:**

- Download and install Amazon Q from the [official site](https://aws.amazon.com/q/developer/).
- Run `q login` and complete the authentication process in your terminal.

**2. Locate your Amazon Q config directory:**

- The config is typically stored at `~/.local/share/amazon-q`.

**3. Generate the tarball:**

- Run the following command in your terminal:
  ```sh
  cd ~/.local/share/amazon-q
  tar -c . | zstd | base64 -w 0
  ```

**4. Copy the output:**

- The command will output a long string. Copy this entire string.

**5. Paste into your Terraform variable:**

- Assign the string to the `experiment_auth_tarball` variable in your Terraform configuration, for example:
  ```tf
  variable "amazon_q_auth_tarball" {
    type    = string
    default = "PASTE_LONG_STRING_HERE"
  }
  ```

**Note:**

- You must re-generate the tarball if you log out or re-authenticate Amazon Q on your local machine.
- This process is required for each user who wants to use Amazon Q in their workspace.

[Reference: Amazon Q documentation](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/generate-docs.html)

</details>

## Examples

### Basic Amazon Q with AgentAPI

```tf
module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.15"
  agent_id = coder_agent.example.id
}

module "amazon-q" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/amazon-q/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.example.id
  auth_tarball = var.amazon_q_auth_tarball
}
```

### Using Aider instead of Amazon Q

```tf
variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key for Aider"
  sensitive   = true
}

resource "coder_agent" "main" {
  env = {
    ANTHROPIC_API_KEY = var.anthropic_api_key
  }
}

module "amazon-q" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/amazon-q/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.main.id
  use_aider    = true
  auth_tarball = "dummy" # Not needed for Aider mode
}
```

### With Task Automation

```tf
data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Task"
  default     = ""
  description = "Task for the AI agent to complete"
  mutable     = true
}

module "amazon-q" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/amazon-q/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.example.id
  auth_tarball = var.amazon_q_auth_tarball
  task_prompt  = data.coder_parameter.ai_prompt.value
}
```

### With Custom Extensions

```tf
module "amazon-q" {
  count        = data.coder_workspace.me.start_count
  source       = "registry.coder.com/coder/amazon-q/coder"
  version      = "2.0.0"
  agent_id     = coder_agent.example.id
  auth_tarball = var.amazon_q_auth_tarball
  
  additional_extensions = <<-EOT
custom-tool:
  args: []
  cmd: custom-tool-command
  description: A custom tool for the AI agent
  enabled: true
  envs: {}
  name: custom-tool
  timeout: 300
  type: stdio
EOT
}
```

## Features

- **Web Chat Interface**: Modern web interface powered by AgentAPI
- **Coder Tasks Integration**: Full integration with Coder's Tasks system
- **Dual AI Support**: Choose between Amazon Q or Aider
- **Task Reporting**: Automatic status reporting to Coder dashboard
- **Persistent Sessions**: Sessions persist across browser refreshes
- **Custom Extensions**: Support for additional MCP extensions

## Module Parameters

| Parameter | Description | Type | Default |
|-----------|-------------|------|---------|
| `agent_id` | The ID of a Coder agent (required) | `string` | - |
| `auth_tarball` | Base64 encoded Amazon Q auth tarball | `string` | - |
| `use_aider` | Whether to use Aider instead of Amazon Q | `bool` | `false` |
| `task_prompt` | Initial task prompt | `string` | `""` |
| `additional_extensions` | Additional extensions in YAML format | `string` | `null` |
| `install_agentapi` | Whether to install AgentAPI | `bool` | `true` |
| `agentapi_version` | Version of AgentAPI to install | `string` | `"latest"` |

## Migration from v1.x

The v2.0 release introduces AgentAPI integration and breaking changes:

- `experiment_auth_tarball` → `auth_tarball`
- `experiment_report_tasks` → Always enabled
- `experiment_use_screen/tmux` → Replaced by AgentAPI
- New web interface replaces terminal-only access
- Full Coder Tasks integration

## Notes

- This module now uses AgentAPI for web interface and task reporting
- Task reporting is always enabled in v2.0
- For legacy behavior, use v1.x of this module
- For more details, see the [main.tf](./main.tf) source.
