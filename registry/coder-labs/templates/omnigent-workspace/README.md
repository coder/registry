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
- **[Claude Code](https://registry.coder.com/modules/coder/claude-code)** — Anthropic's Claude in your terminal, authenticated through Coder AI Gateway
- **[Codex](https://registry.coder.com/modules/coder-labs/codex)** — OpenAI's Codex CLI, authenticated through Coder AI Gateway

Each workspace runs its own isolated Omnigent server. The admin password is derived from the workspace ID at runtime and never stored in Terraform state.

```tf
module "codex" {
  source  = "registry.coder.com/coder-labs/codex/coder"
  version = "5.0.0"

  agent_id          = coder_agent.main.id
  enable_ai_gateway = true
}

module "claude_code" {
  source  = "registry.coder.com/coder/claude-code/coder"
  version = ">= 4.0.0"

  agent_id          = coder_agent.main.id
  enable_ai_gateway = true
}

module "omnigent" {
  source  = "registry.coder.com/coder-labs/omnigent/coder"
  version = "1.0.0"

  agent_id = coder_agent.main.id
}
```

## Prerequisites

- Docker with `sysbox-runc` runtime installed on the Coder host
- Coder Premium with AI Gateway enabled

The template installs `tmux` and `bubblewrap` before the AI tools start because Omnigent launches the Claude Code and Codex harnesses through local terminal sessions.
