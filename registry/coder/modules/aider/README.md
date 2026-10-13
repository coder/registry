---
display_name: Aider
description: Install and configure Aider AI pair programming in your workspace
icon: ../../../../.icons/aider.svg
verified: true
tags: [agent, ai, aider]
---

# Aider

Install and configure [Aider](https://aider.chat) AI pair programming in your workspace.

```tf
module "aider" {
  source      = "registry.coder.com/coder/aider/coder"
  version     = "3.0.0"
  agent_id    = coder_agent.main.id
  api_key     = var.gemini_api_key
  ai_provider = "google"
  model       = "gemini"
}
```

> [!WARNING]
> If upgrading from v2.x.x of this module: v3 is a major refactor that drops support for Coder Tasks and AgentAPI. The module now only installs and configures Aider; launch it with your own `coder_app`. `order`, `group`, `report_tasks`, `subdomain`, `cli_app`, `web_app_display_name`, `cli_app_display_name`, `install_agentapi`, `agentapi_version`, `ai_prompt`, `system_prompt`, and `experiment_additional_extensions` are removed. `workdir` is now optional, `base_aider_config` is written to `~/.aider.conf.yml`, and `ai_provider = "ollama"` exports `api_key` as `OLLAMA_API_KEY`. Keep using v2.x.x if you depend on Coder Tasks.

## Examples

### Standalone mode with a launcher app

```tf
locals {
  aider_workdir = "/home/coder/project"
}

module "aider" {
  source      = "registry.coder.com/coder/aider/coder"
  version     = "3.0.0"
  agent_id    = coder_agent.main.id
  workdir     = local.aider_workdir
  ai_provider = "anthropic"
  model       = "sonnet"
  api_key     = var.anthropic_api_key
}

resource "coder_app" "aider" {
  agent_id     = coder_agent.main.id
  slug         = "aider"
  display_name = "Aider"
  icon         = "/icon/aider.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    cd "${local.aider_workdir}"
    exec aider
  EOT
}
```

See [Aider options](https://aider.chat/docs/config/options.html) for launcher flags such as `--yes-always` and `--watch-files`.

> [!NOTE]
> The `coder_app` command re-executes on every pane reconnect. This works for the interactive `aider` chat, but one-shot commands like `aider --message` will re-run each time. For one-shot prompts, use a `coder_script` (runs once at startup) and a `coder_app` that attaches to the existing session (for example, with tmux).

### Custom provider

```tf
module "aider" {
  source              = "registry.coder.com/coder/aider/coder"
  version             = "3.0.0"
  agent_id            = coder_agent.main.id
  ai_provider         = "custom"
  custom_env_var_name = "DEEPSEEK_API_KEY"
  model               = "deepseek"
  api_key             = var.deepseek_api_key
}
```

`api_key` is exported as the provider's environment variable (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `AZURE_OPENAI_API_KEY`, `GEMINI_API_KEY`, `COHERE_API_KEY`, `MISTRAL_API_KEY`, `OLLAMA_API_KEY`, or `custom_env_var_name`) and `model` as `AIDER_MODEL`. See [Aider API keys](https://aider.chat/docs/config/api-keys.html) and [connecting to LLMs](https://aider.chat/docs/llms.html).

### Configuration file

```tf
module "aider" {
  source   = "registry.coder.com/coder/aider/coder"
  version  = "3.0.0"
  agent_id = coder_agent.main.id
  model    = "gemini"
  api_key  = var.gemini_api_key

  base_aider_config = <<-EOT
    read:
      - CONVENTIONS.md
    auto-commits: false
  EOT
}
```

`base_aider_config` is written to `~/.aider.conf.yml`. See the [YAML config file](https://aider.chat/docs/config/aider_conf.html) reference.

### Serialize a downstream `coder_script` after the install pipeline

The module exposes the `scripts` output: an ordered list of `coder exp sync` names for the scripts this module creates (pre_install, install, post_install). Scripts that were not configured are absent.

```tf
module "aider" {
  source   = "registry.coder.com/coder/aider/coder"
  version  = "3.0.0"
  agent_id = coder_agent.main.id
  model    = "gemini"
}

resource "coder_script" "post_aider" {
  agent_id     = coder_agent.main.id
  display_name = "Run after Aider install"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'coder exp sync complete post-aider' EXIT
    coder exp sync want post-aider ${join(" ", module.aider.scripts)}
    coder exp sync start post-aider

    aider --version
  EOT
}
```

## Troubleshooting

Check the log files in `~/.coder-modules/coder/aider/logs/` for detailed information.

```bash
cat ~/.coder-modules/coder/aider/logs/install.log
cat ~/.coder-modules/coder/aider/logs/pre_install.log
cat ~/.coder-modules/coder/aider/logs/post_install.log
```

## References

- [Aider documentation](https://aider.chat/docs/)
- [Aider installation](https://aider.chat/docs/install.html)
- [Aider configuration](https://aider.chat/docs/config.html)
- [Aider API keys](https://aider.chat/docs/config/api-keys.html)
