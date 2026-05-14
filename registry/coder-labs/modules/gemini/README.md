---
display_name: Gemini CLI
description: Run Gemini CLI in your workspace for AI pair programming
icon: ../../../../.icons/gemini.svg
verified: true
tags: [agent, gemini, ai, google, tasks]
---

# Gemini CLI

Install and configure the [Gemini CLI](https://github.com/google-gemini/gemini-cli) in your workspace to access Google's Gemini AI models for interactive coding assistance.

```tf
module "gemini" {
  source   = "registry.coder.com/coder-labs/gemini/coder"
  version  = "4.0.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
}
```

> [!WARNING]
> If upgrading from v3.x.x of this module: v4 is a major refactor that drops support for [Coder Tasks](https://coder.com/docs/ai-coder/tasks). Keep using v3.x.x if you depend on them. See the [PR description](https://github.com/coder/registry/pull/879) for a full migration guide.

## Features

- **Interactive AI Assistance**: Run Gemini CLI directly in your terminal for coding help
- **Multiple AI Models**: Support for Gemini 2.5 Pro, Flash, and other Google AI models
- **API Key Integration**: Seamless authentication with Gemini API
- **MCP Server Integration**: Built-in Coder MCP server for task reporting
- **Persistent Sessions**: Maintain context across workspace sessions

## Prerequisites

- **Node.js and npm must be sourced/available before the gemini module installs** - ensure they are installed in your workspace image or via earlier provisioning steps
- The [Coder Login](https://registry.coder.com/modules/coder/coder-login) module is required

## Examples

### Basic setup

- Install Gemini CLI in the workspace
- Configure authentication with your API key
- Enable interactive use from the terminal
- Set up MCP server integration for task reporting

```tf
locals {
  gemini_workdir = "/home/coder/project"
}

variable "gemini_api_key" {
  type        = string
  description = "Gemini API key"
  sensitive   = true
}

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
}

module "gemini" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder-labs/gemini/coder"
  version            = "4.0.0"
  agent_id           = coder_agent.main.id
  gemini_api_key     = var.gemini_api_key
  gemini_model       = "gemini-2.5-flash"
  workdir            = locals.workdir
  pre_install_script = <<-EOT
    #!/bin/bash
    set -e

    echo "Installing Node.js via NodeSource..."

    sudo apt-get update -qq && sudo apt-get install -y curl ca-certificates

    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo bash -

    sudo apt-get install -y nodejs

    echo "Node version: $(node -v)"
    echo "npm version: $(npm -v)"
    echo "Node install complete."
  EOT
}

resource "coder_app" "gemini" {
  agent_id     = coder_agent.main.id
  slug         = "gemini"
  display_name = "Gemini"
  icon         = "/icon/openai.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/bin/bash
    set -e
    cd "${local.gemini_workdir}"
    gemini
  EOT
}
```

### Using Vertex AI (Enterprise)

For enterprise users who prefer Google's Vertex AI platform:

```tf
module "gemini" {
  source         = "registry.coder.com/coder-labs/gemini/coder"
  version        = "4.0.0"
  agent_id       = coder_agent.main.id
  gemini_api_key = var.gemini_api_key
  workdir        = "/home/coder/project"
  use_vertexai   = true
}
```

## Troubleshooting

Check the log files in `~/.coder-modules/coder-labs/gemini/logs/` for detailed information.

```bash
cat ~/.coder-modules/coder-labs/gemini/logs/install.log
cat ~/.coder-modules/coder-labs/gemini/logs/pre_install.log
cat ~/.coder-modules/coder-labs/gemini/logs/post_install.log
```

## References

- [Gemini CLI Documentation](https://github.com/google-gemini/gemini-cli/blob/main/docs/index.md)
- [Coder AI Agents Guide](https://coder.com/docs/ai-coder)
