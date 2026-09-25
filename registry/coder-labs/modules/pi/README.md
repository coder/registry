---
display_name: Pi
description: Install and configure the Pi coding agent CLI in your workspace.
icon: ../../../../.icons/pi.svg
verified: false
tags: [agent, pi, ai]
---

# Pi

Install and configure the [Pi](https://pi.dev/) coding agent CLI in your workspace. Pi is a customizable terminal coding agent harness built by [earendil-works](https://github.com/earendil-works/pi). Starting Pi is left to the caller (template command, IDE launcher, or a custom `coder_script`).

```tf
module "pi" {
  source            = "registry.coder.com/coder-labs/pi/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.main.id
  anthropic_api_key = "xxxx-xxxxx-xxxx"
}
```

## Prerequisites

The module installs Pi via `npm install -g @earendil-works/pi-coding-agent`, so the workspace image must already have Node.js (>= 22.19.0) and npm available. Set `install_pi = false` if Pi is pre-installed elsewhere on `PATH`.

Provide credentials for whichever model providers you use. Pi reads standard provider environment variables directly, so any combination can be set:

- `anthropic_api_key` sets `ANTHROPIC_API_KEY`.
- `openai_api_key` sets `OPENAI_API_KEY`.
- `gemini_api_key` sets `GEMINI_API_KEY`.
- `extra_env` sets arbitrary additional environment variables for other providers Pi supports (Azure OpenAI, Mistral, Groq, DeepSeek, and more).

Alternatively, users can skip all of the above and run `/login` inside Pi to authenticate interactively against a Claude Pro/Max, ChatGPT Plus/Pro, or GitHub Copilot subscription.

## workdir

`workdir` is optional. When set, the module pre-creates the directory if it is missing. Leave `workdir` unset if you only want the module to install and configure the CLI; users can `cd` into any project themselves.

## Examples

### Standalone mode with a launcher app

```tf
locals {
  pi_workdir = "/home/coder/project"
}

module "pi" {
  source            = "registry.coder.com/coder-labs/pi/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.main.id
  workdir           = local.pi_workdir
  anthropic_api_key = "xxxx-xxxxx-xxxx"
}

resource "coder_app" "pi" {
  agent_id     = coder_agent.main.id
  slug         = "pi"
  display_name = "Pi"
  icon         = "/icon/pi.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    cd ${local.pi_workdir}
    pi
  EOT
}
```

> [!NOTE]
> `coder_app.command` runs when the user clicks the app tile. Combine with `anthropic_api_key`, `openai_api_key`, `gemini_api_key`, or `extra_env` on the module to pre-authenticate the CLI.

### Advanced configuration

This example shows version pinning and multiple provider credentials.

```tf
module "pi" {
  source   = "registry.coder.com/coder-labs/pi/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder/project"

  pi_version = "0.12.0" # Pin to a specific Pi CLI version.

  anthropic_api_key = "xxxx-xxxxx-xxxx"
  openai_api_key    = "xxxx-xxxxx-xxxx"
  gemini_api_key    = "xxxx-xxxxx-xxxx"

  extra_env = {
    MISTRAL_API_KEY = "xxxx-xxxxx-xxxx"
  }
}
```

### Project trust

By default the module sets `defaultProjectTrust = "always"` in `~/.pi/agent/settings.json` so Pi does not prompt to trust a project folder on first run in the workspace. Set `default_project_trust` to `"ask"` or `"never"` to change this behavior.

```tf
module "pi" {
  source                = "registry.coder.com/coder-labs/pi/coder"
  version               = "1.0.0"
  agent_id              = coder_agent.main.id
  workdir               = "/home/coder/project"
  anthropic_api_key     = "xxxx-xxxxx-xxxx"
  default_project_trust = "ask"
}
```

> [!NOTE]
> Pi does not include built-in MCP (Model Context Protocol) support. See the [Pi documentation](https://github.com/earendil-works/pi) for extending Pi with custom tools and extensions instead.

### Serialize a downstream `coder_script` after the install pipeline

The module exposes the `coder exp sync` name of each script it creates via the `scripts` output: an ordered list (`pre_install`, `install`, `post_install`) of names for scripts this module actually creates. Scripts that were not configured are absent from the list.

```tf
module "pi" {
  source            = "registry.coder.com/coder-labs/pi/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.main.id
  workdir           = "/home/coder/project"
  anthropic_api_key = "xxxx-xxxxx-xxxx"
}

resource "coder_script" "post_pi" {
  agent_id     = coder_agent.main.id
  display_name = "Run after Pi install"
  run_on_start = true
  script       = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'coder exp sync complete post-pi' EXIT
    coder exp sync want post-pi ${join(" ", module.pi.scripts)}
    coder exp sync start post-pi

    # Your work here runs after pi finishes installing.
    pi --version
  EOT
}
```

## Troubleshooting

If you encounter any issues, check the log files in the `~/.coder-modules/coder-labs/pi/logs` directory within your workspace for detailed information.

```bash
# Installation logs
cat ~/.coder-modules/coder-labs/pi/logs/install.log

# Pre/post install script logs
cat ~/.coder-modules/coder-labs/pi/logs/pre_install.log
cat ~/.coder-modules/coder-labs/pi/logs/post_install.log
```

## References

- [Pi Documentation](https://github.com/earendil-works/pi)
