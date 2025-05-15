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
  source   = "registry.coder.com/coder/aider/coder"
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
- **Non-Interactive Mode**: Automatically processes tasks when provided via the `task_prompt` variable

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
| `system_prompt`                    | System prompt for instructing Aider on task reporting and behavior         | `string` | See default in code |
| `task_prompt`                      | Task prompt to use with Aider                                              | `string` | `""`                |
| `ai_provider`                      | AI provider to use with Aider (openai, anthropic, azure, etc.)             | `string` | `"anthropic"`       |
| `ai_model`                         | AI model to use (can use Aider's built-in aliases like "sonnet", "4o")     | `string` | `"sonnet"`          |
| `ai_api_key`                       | API key for the selected AI provider                                       | `string` | `""`                |
| `custom_env_var_name`              | Custom environment variable name when using custom provider                | `string` | `""`                |
| `experiment_pre_install_script`    | Custom script to run before installing Aider                               | `string` | `null`              |
| `experiment_post_install_script`   | Custom script to run after installing Aider                                | `string` | `null`              |
| `experiment_additional_extensions` | Additional extensions configuration in YAML format to append to the config | `string` | `null`              |

> **Note**: `use_screen` and `use_tmux` cannot both be enabled at the same time. By default, `use_screen` is set to `true` and `use_tmux` is set to `false`.

## Usage Examples

### Basic setup with API key

```tf
variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key"
  sensitive   = true
}

module "aider" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/aider/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.example.id
  ai_api_key = var.anthropic_api_key
}
```

This basic setup will:

- Install Aider in the workspace
- Create a persistent screen session named "aider"
- Configure Aider to use Anthropic Claude 3.7 Sonnet model
- Enable task reporting (configures Aider to report tasks to Coder MCP)

### Using OpenAI with tmux

```tf
variable "openai_api_key" {
  type        = string
  description = "OpenAI API key"
  sensitive   = true
}

module "aider" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/coder/aider/coder"
  version     = "1.0.0"
  agent_id    = coder_agent.example.id
  use_tmux    = true
  ai_provider = "openai"
  ai_model    = "4o" # Uses Aider's built-in alias for gpt-4o
  ai_api_key  = var.openai_api_key
}
```

### Using a custom provider

```tf
variable "custom_api_key" {
  type        = string
  description = "Custom provider API key"
  sensitive   = true
}

module "aider" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/aider/coder"
  version             = "1.0.0"
  agent_id            = coder_agent.example.id
  ai_provider         = "custom"
  custom_env_var_name = "MY_CUSTOM_API_KEY"
  ai_model            = "custom-model"
  ai_api_key          = var.custom_api_key
}
```

### Adding Custom Extensions (Experimental)

You can extend Aider's capabilities by adding custom extensions:

```tf
module "aider" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/aider/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.example.id
  ai_api_key = var.anthropic_api_key

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
2. Configure the necessary variables to pass the task prompt
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

data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Write a prompt for Aider"
  mutable     = true
  ephemeral   = true
}

module "aider" {
  count       = data.coder_workspace.me.start_count
  source      = "registry.coder.com/coder/aider/coder"
  version     = "1.0.0"
  agent_id    = coder_agent.example.id
  ai_api_key  = var.anthropic_api_key
  task_prompt = data.coder_parameter.ai_prompt.value

  # Optionally customize the system prompt
  system_prompt = <<-EOT
You are a helpful Coding assistant. Aim to autonomously investigate
and solve issues the user gives you and test your work, whenever possible.
Avoid shortcuts like mocking tests. When you get stuck, you can ask the user
but opt for autonomy.
YOU MUST REPORT ALL TASKS TO CODER.
When reporting tasks, you MUST follow these EXACT instructions:
- IMMEDIATELY report status after receiving ANY user message.
- Be granular. If you are investigating with multiple steps, report each step to coder.
Task state MUST be one of the following:
- Use "state": "working" when actively processing WITHOUT needing additional user input.
- Use "state": "complete" only when finished with a task.
- Use "state": "failure" when you need ANY user input, lack sufficient details, or encounter blockers.
Task summaries MUST:
- Include specifics about what you're doing.
- Include clear and actionable steps for the user.
- Be less than 160 characters in length.
  EOT
}
```

When a task prompt is provided via the `task_prompt` variable, the module automatically:

1. Combines the system prompt with the task prompt into a single message in the format:

```
SYSTEM PROMPT:
[system_prompt content]

This is your current task: [task_prompt]
```

2. Executes the task during workspace creation using the `--message` and `--yes-always` flags
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
- Configures tmux with mouse support for shared sessions

Persistent sessions (screen/tmux) allow you to:

- Disconnect and reconnect without losing context
- Run Aider in the background while doing other work
- Switch between terminal and browser interfaces

### Available AI Providers and Models

Aider supports various providers and models, and this module integrates directly with Aider's built-in model aliases:

| Provider      | Example Models/Aliases                        | Default Model          |
| ------------- | --------------------------------------------- | ---------------------- |
| **anthropic** | "sonnet" (Claude 3.7 Sonnet), "opus", "haiku" | "sonnet"               |
| **openai**    | "4o" (GPT-4o), "4" (GPT-4), "3.5-turbo"       | "4o"                   |
| **azure**     | Azure OpenAI models                           | "gpt-4"                |
| **google**    | "gemini" (Gemini Pro), "gemini-2.5-pro"       | "gemini-2.5-pro"       |
| **cohere**    | "command-r-plus", etc.                        | "command-r-plus"       |
| **mistral**   | "mistral-large-latest"                        | "mistral-large-latest" |
| **ollama**    | "llama3", etc.                                | "llama3"               |
| **custom**    | Any model name with custom ENV variable       | -                      |

For a complete and up-to-date list of supported aliases and models, please refer to the [Aider LLM documentation](https://aider.chat/docs/llms.html) and the [Aider LLM Leaderboards](https://aider.chat/docs/leaderboards.html) which show performance comparisons across different models.

## Troubleshooting

If you encounter issues:

1. **Screen/Tmux issues**: If you can't reconnect to your session, check if the session exists with `screen -list` or `tmux list-sessions`
2. **API key issues**: Ensure you've entered the correct API key for your selected provider
3. **Browser mode issues**: If the browser interface doesn't open, check that you're accessing it from a machine that can reach your Coder workspace

For more information on using Aider, see the [Aider documentation](https://aider.chat/docs/).

```

```
