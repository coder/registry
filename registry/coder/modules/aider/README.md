---
display_name: Aider
description: Run Aider AI pair programming in your workspace
icon: ../../../../.icons/code.svg
maintainer_github: coder
verified: true
tags: [agent, aider]
---

# Aider

Run [Aider](https://aider.chat) AI pair programming in your workspace. This module installs Aider and provides a persistent session using screen or tmux.

```tf
module "aider" {
  source   = "registry.coder.com/modules/aider/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Features

- **Interactive Parameter Selection**: Choose your AI provider, model, and configuration options when creating the workspace
- **Multiple AI Providers**: Supports Anthropic (Claude), OpenAI, DeepSeek, GROQ, and OpenRouter
- **Persistent Sessions**: Uses screen (default) or tmux to keep Aider running in the background
- **Optional Dependencies**: Install Playwright for web page scraping and PortAudio for voice coding
- **Project Integration**: Works with any project directory, including Git repositories
- **Browser UI**: Use Aider in your browser with a modern web interface instead of the terminal
- **Non-Interactive Mode**: Automatically processes tasks when provided via the `CODER_MCP_AIDER_TASK_PROMPT` environment variable

## Module Parameters

| Parameter                          | Description                                                                | Type     | Default             |
| ---------------------------------- | -------------------------------------------------------------------------- | -------- | ------------------- |
| `agent_id`                         | The ID of a Coder agent (required)                                         | `string` | -                   |
| `folder`                           | The folder to run Aider in                                                 | `string` | `/home/coder`       |
| `install_aider`                    | Whether to install Aider                                                   | `bool`   | `true`              |
| `aider_version`                    | The version of Aider to install                                            | `string` | `"latest"`          |
| `use_screen`                       | Whether to use screen for running Aider in the background                  | `bool`   | `true`              |
| `use_tmux`                         | Whether to use tmux instead of screen for running Aider in the background  | `bool`   | `false`             |
| `session_name`                     | Name for the persistent session (screen or tmux)                           | `string` | `"aider"`           |
| `order`                            | Position of the app in the UI presentation                                 | `number` | `null`              |
| `icon`                             | The icon to use for the app                                                | `string` | `"/icon/aider.svg"` |
| `experiment_report_tasks`          | Whether to enable task reporting                                           | `bool`   | `true`              |
| `experiment_task_conventions`      | Custom conventions for task reporting to be written to CONVENTIONS.md      | `string` | See default in code |
| `experiment_pre_install_script`    | Custom script to run before installing Aider                               | `string` | `null`              |
| `experiment_post_install_script`   | Custom script to run after installing Aider                                | `string` | `null`              |
| `experiment_additional_extensions` | Additional extensions configuration in YAML format to append to the config | `string` | `null`              |

> **Note**: `use_screen` and `use_tmux` cannot both be enabled at the same time. By default, `use_screen` is set to `true` and `use_tmux` is set to `false`.

## Usage Examples

### Basic setup

```tf
module "aider" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/aider/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder"
}
```

This basic setup will:

- Install Aider in the workspace
- Create a persistent screen session named "aider"
- Enable task reporting (configures Aider to report tasks to Coder MCP)

### With tmux instead of screen

```tf
module "aider" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/aider/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder"
  use_tmux = true
}
```

### With API key via environment variables

```tf
variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key"
  sensitive   = true
}

variable "anthropic_model" {
  type        = string
  description = "Anthropic Model"
  default     = "sonnet"
}

resource "coder_agent" "main" {
  # ...
}

# Set API key and model using coder_env resource
resource "coder_env" "anthropic" {
  agent_id = coder_agent.example.id
  name     = "ANTHROPIC_API_KEY"
  value    = var.anthropic_api_key
}

resource "coder_env" "aider_model" {
  agent_id = coder_agent.example.id
  name     = "AIDER_MODEL"
  value    = var.anthropic_model
}

module "aider" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/aider/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder"
}
```

### Adding Custom Extensions (Experimental)

You can extend Aider's capabilities by adding custom extensions:

```tf
module "aider" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/aider/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder"

  experiment_pre_install_script = <<-EOT
  pip install some-custom-dependency
  EOT

  experiment_additional_extensions = <<-EOT
  custom-extension:
    args: []
    cmd: custom-extension-command
    description: A custom extension for Aider
    enabled: true
    envs: {}
    name: custom-extension
    timeout: 300
    type: stdio
  EOT
}
```

Note: The indentation in the heredoc is preserved, so you can write the YAML naturally.

## Task Reporting (Experimental)

> This functionality is in early access as of Coder v2.21 and is still evolving.
> For now, we recommend testing it in a demo or staging environment,
> rather than deploying to production
>
> Learn more in [the Coder documentation](https://coder.com/docs/tutorials/ai-agents)
>
> Join our [Discord channel](https://discord.gg/coder) or
> [contact us](https://coder.com/contact) to get help or share feedback.

Your workspace must have either `screen` or `tmux` installed to use this.

Task reporting is **enabled by default** in this module, allowing you to:

- Send an initial prompt to Aider during workspace creation
- Monitor task progress in the Coder UI
- Use the `coder_parameter` resource to collect prompts from users

### Setting up Task Reporting

To use task reporting effectively:

1. Add the Coder Login module to your template
2. Configure the necessary environment variables to pass the task prompt and status slug
3. Optionally add a coder_parameter to collect prompts from users

Here's a complete example:

```tf
module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/coder-login/coder"
  version  = "1.0.15"
  agent_id = coder_agent.example.id
}

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key"
  sensitive   = true
}

variable "anthropic_model" {
  type        = string
  description = "Anthropic Model"
  default     = "sonnet"
}

data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Write a prompt for Aider"
  mutable     = true
  ephemeral   = true
}

# Configure environment variables for API key, model and task prompt
resource "coder_env" "anthropic" {
  agent_id = coder_agent.example.id
  name     = "ANTHROPIC_API_KEY"
  value    = var.anthropic_api_key
}

resource "coder_env" "aider_model" {
  agent_id = coder_agent.example.id
  name     = "AIDER_MODEL"
  value    = var.anthropic_model
}

resource "coder_env" "task_prompt" {
  agent_id = coder_agent.example.id
  name     = "CODER_MCP_AIDER_TASK_PROMPT"
  value    = data.coder_parameter.ai_prompt.value
}

resource "coder_env" "app_status" {
  agent_id = coder_agent.example.id
  name     = "CODER_MCP_APP_STATUS_SLUG"
  value    = "aider"
}

module "aider" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/aider/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder"
}
```

When a task prompt is provided, the module automatically:

1. Executes the task during workspace creation using the `--message` and `--yes-always` flags
2. Creates a flag file to prevent duplicate execution if the Aider button is clicked later
3. Logs task output to `$HOME/.aider.log` for reference

If you want to disable task reporting, set `experiment_report_tasks = false` in your module configuration.

## Using Aider in Your Workspace

After the workspace starts, Aider will be installed and configured according to your parameters. A persistent session will automatically be started during workspace creation.

### Session Options

You can run Aider in three different ways:

1. **Direct Mode**: Aider starts directly in the specified folder when you click the app button

   - Simple setup without persistent context
   - Suitable for quick coding sessions

2. **Screen Mode** (Default): Run Aider in a screen session that persists across connections

   - Session name: "aider" (or configured via `session_name`)

3. **Tmux Mode**: Run Aider in a tmux session instead of screen
   - Set `use_tmux = true` to enable
   - Session name: "aider" (or configured via `session_name`)

Persistent sessions (screen/tmux) allow you to:

- Disconnect and reconnect without losing context
- Run Aider in the background while doing other work
- Switch between terminal and browser interfaces

### Available AI Providers and Models

| Provider       | Available Models                    | API Key Source                                              |
| -------------- | ----------------------------------- | ----------------------------------------------------------- |
| **Anthropic**  | Claude 3.7 Sonnet, Claude 3.7 Haiku | [console.anthropic.com](https://console.anthropic.com/)     |
| **OpenAI**     | o3-mini, o1, GPT-4o                 | [platform.openai.com](https://platform.openai.com/api-keys) |
| **DeepSeek**   | DeepSeek R1, DeepSeek Chat V3       | [platform.deepseek.com](https://platform.deepseek.com/)     |
| **GROQ**       | Mixtral, Llama 3                    | [console.groq.com](https://console.groq.com/keys)           |
| **OpenRouter** | OpenRouter                          | [openrouter.ai](https://openrouter.ai/keys)                 |

For a complete and up-to-date list of supported LLMs and models, please refer to the [Aider LLM documentation](https://aider.chat/docs/llms.html) and the [Aider LLM Leaderboards](https://aider.chat/docs/leaderboards.html) which show performance comparisons across different models.

## Troubleshooting

If you encounter issues:

1. **Screen/Tmux issues**: If you can't reconnect to your session, check if the session exists with `screen -list` or `tmux list-sessions`
2. **API key issues**: Ensure you've entered the correct API key for your selected provider
3. **Browser mode issues**: If the browser interface doesn't open, check that you're accessing it from a machine that can reach your Coder workspace

For more information on using Aider, see the [Aider documentation](https://aider.chat/docs/).
