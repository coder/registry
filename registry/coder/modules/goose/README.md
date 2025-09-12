---
display_name: Goose
description: Run Goose in your workspace
icon: ../../../../.icons/goose.svg
verified: true
tags: [agent, goose, ai, tasks]
---

# Goose

Run the [Goose](https://block.github.io/goose/) agent in your workspace to generate code and perform tasks.

```tf
module "goose" {
  source           = "registry.coder.com/coder/goose/coder"
  version          = "2.1.2"
  agent_id         = coder_agent.example.id
  folder           = "/home/coder"
  install_goose    = true
  goose_version    = "v1.0.31"
  goose_provider   = "anthropic"
  goose_model      = "claude-3-5-sonnet-latest"
  agentapi_version = "latest"
}
```

## Prerequisites

- You must add the [Coder Login](https://registry.coder.com/modules/coder-login) module to your template

The `codercom/oss-dogfood:latest` container image can be used for testing on container-based workspaces.

## Examples

### Run in the background and report tasks

```tf
module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.0.15"
  agent_id = coder_agent.example.id
}

variable "anthropic_api_key" {
  type        = string
  description = "The Anthropic API key"
  sensitive   = true
}

data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Write a prompt for Goose"
  mutable     = true
}

# Set the prompt and system prompt for Goose via environment variables
resource "coder_agent" "main" {
  # ...
  env = {
    GOOSE_SYSTEM_PROMPT = <<-EOT
      You are a helpful assistant that can help write code.

      Run all long running tasks (e.g. npm run dev) in the background and not in the foreground.

      Periodically check in on background tasks.

      Notify Coder of the status of the task before and after your steps.
    EOT
    GOOSE_TASK_PROMPT   = data.coder_parameter.ai_prompt.value

    # See https://block.github.io/goose/docs/getting-started/providers
    ANTHROPIC_API_KEY = var.anthropic_api_key # or use a coder_parameter
  }
}

module "goose" {
  count            = data.coder_workspace.me.start_count
  source           = "registry.coder.com/coder/goose/coder"
  version          = "2.1.2"
  agent_id         = coder_agent.example.id
  folder           = "/home/coder"
  install_goose    = true
  goose_version    = "v1.0.31"
  agentapi_version = "latest"

  goose_provider = "anthropic"
  goose_model    = "claude-3-5-sonnet-latest"
}
```

### Adding Custom Extensions (MCP)

You can extend Goose's capabilities by adding custom extensions. For example, to add the desktop-commander extension:

```tf
module "goose" {
  # ... other configuration ...

  pre_install_script = <<-EOT
  npm i -g @wonderwhy-er/desktop-commander@latest
  EOT

  additional_extensions = <<-EOT
  desktop-commander:
    args: []
    cmd: desktop-commander
    description: Ideal for background tasks
    enabled: true
    envs: {}
    name: desktop-commander
    timeout: 300
    type: stdio
  EOT
}
```

This will add the desktop-commander extension to Goose, allowing it to run commands in the background. The extension will be available in the Goose interface and can be used to run long-running processes like development servers.

Note: The indentation in the heredoc is preserved, so you can write the YAML naturally.

## Troubleshooting

By default, this module is configured to run the embedded chat interface as a path-based application. In production, we recommend that you configure a [wildcard access URL](https://coder.com/docs/admin/setup#wildcard-access-url) and set `subdomain = true`. See [here](https://coder.com/docs/tutorials/best-practices/security-best-practices#disable-path-based-apps) for more details.

The module will create log files in the workspace's `~/.goose-module` directory. If you run into any issues, look at them for more information.
