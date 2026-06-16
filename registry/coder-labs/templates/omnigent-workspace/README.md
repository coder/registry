---
display_name: Omnigent Workspace
icon: ../../../../.icons/omnigent.svg
description: Docker workspace with Omnigent, Claude Code, and Codex pre-installed.
verified: false
tags: [docker, omnigent, claude-code, codex, ai, multi-agent]
---

# Omnigent Workspace

A Docker-based workspace that combines three AI agent modules:

- **[Omnigent](https://registry.coder.com/modules/coder-labs/omnigent)** — private multi-agent coding orchestrator server
- **[Claude Code](https://registry.coder.com/modules/coder/claude-code)** — Anthropic's Claude in your terminal
- **[Codex](https://registry.coder.com/modules/coder-labs/codex)** — OpenAI's Codex CLI

Each workspace runs its own isolated Omnigent server. The admin password is derived from the workspace ID at runtime and never stored in Terraform state.

```tf
module "omnigent" {
  source   = "registry.coder.com/coder-labs/omnigent/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}

module "codex" {
  source         = "registry.coder.com/coder-labs/codex/coder"
  version        = "5.0.0"
  agent_id       = coder_agent.main.id
  openai_api_key = var.openai_api_key
}

module "claude_code" {
  source            = "registry.coder.com/coder/claude-code/coder"
  version           = ">= 4.0.0"
  agent_id          = coder_agent.main.id
  anthropic_api_key = var.anthropic_api_key
}
```

## Prerequisites

- Docker with `sysbox-runc` runtime installed on the Coder host
- `ANTHROPIC_API_KEY` and `OPENAI_API_KEY` set as Coder template variables
