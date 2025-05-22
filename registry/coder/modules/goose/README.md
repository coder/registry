---
display_name: Goose
description: Run Goose in your workspace
icon: ../../../../.icons/goose.svg
maintainer_github: coder
verified: true
tags: [agent, goose, ai]
---

# Goose

Run the [Goose](https://block.github.io/goose/) agent in your workspace to generate code and perform tasks.

```tf
module "goose" {
  source        = "registry.coder.com/coder/goose/coder"
  version       = "1.2.0"
  agent_id      = coder_agent.example.id
  folder        = "/home/coder"
  install_goose = true
  goose_version = "v1.0.16"
}
```

## Prerequisites

- `screen` or `tmux` must be installed in your workspace to run Goose in the background
- You must add the [Coder Login](https://registry.coder.com/modules/coder-login) module to your template

The `codercom/oss-dogfood:latest` container image can be used for testing on container-based workspaces.

## Examples

Your workspace must have `screen` or `tmux` installed to use the background session functionality.

### Run in the background and report tasks (Experimental)

> This functionality is in early access as of Coder v2.21 and is still evolving.
> For now, we recommend testing it in a demo or staging environment,
> rather than deploying to production
>
> Learn more in [the Coder documentation](https://coder.com/docs/tutorials/ai-agents)
>
> Join our [Discord channel](https://discord.gg/coder) or
> [contact us](https://coder.com/contact) to get help or share feedback.

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

    # An API key is required for experiment_auto_configure
    # See https://block.github.io/goose/docs/getting-started/providers
    ANTHROPIC_API_KEY = var.anthropic_api_key # or use a coder_parameter
  }
}

module "goose" {
  count         = data.coder_workspace.me.start_count
  source        = "registry.coder.com/coder/goose/coder"
  version       = "1.2.0"
  agent_id      = coder_agent.example.id
  folder        = "/home/coder"
  install_goose = true
  goose_version = "v1.0.16"

  # Enable experimental features
  experiment_report_tasks = true

  # Run Goose in the background with screen (pick one: screen or tmux)
  experiment_use_screen = true
  # experiment_use_tmux = true  # Alternative: use tmux instead of screen

  # Optional: customize the session name (defaults to "goose")
  # session_name = "goose-session"

  # Avoid configuring Goose manually
  experiment_auto_configure = true

  # Required for experiment_auto_configure
  experiment_goose_provider = "anthropic"
  experiment_goose_model    = "claude-3-5-sonnet-latest"
}
```

### Adding Custom Extensions (MCP)

You can extend Goose's capabilities by adding custom extensions. For example, to add the desktop-commander extension:

```tf
module "goose" {
  # ... other configuration ...

  experiment_pre_install_script = <<-EOT
  npm i -g @wonderwhy-er/desktop-commander@latest
  EOT

  experiment_additional_extensions = <<-EOT
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

## Run standalone

Run Goose as a standalone app in your workspace. This will install Goose and run it directly without using screen or tmux, and without any task reporting to the Coder UI.

```tf
module "goose" {
  source        = "registry.coder.com/coder/goose/coder"
  version       = "1.2.0"
  agent_id      = coder_agent.example.id
  folder        = "/home/coder"
  install_goose = true
  goose_version = "v1.0.16"

  # Icon is not available in Coder v2.20 and below, so we'll use a custom icon URL
  icon = "https://raw.githubusercontent.com/block/goose/refs/heads/main/ui/desktop/src/images/icon.svg"
}
```
