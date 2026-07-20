---
display_name: Omnigent Docker
icon: ../../../../.icons/omnigent.svg
description: Docker workspace with Omnigent, Claude Code, and Codex pre-installed.
verified: false
tags: [docker, container, omnigent, ai, agent, ai-gateway]
---

# Omnigent Docker

A Docker-based workspace that combines three AI agent modules:

- **[Omnigent](https://registry.coder.com/modules/matifali/omnigent)** — private multi-agent coding orchestrator server
- **[Claude Code](https://registry.coder.com/modules/coder/claude-code)** — Anthropic's Claude in your terminal, authenticated through Coder AI Gateway
- **[Codex](https://registry.coder.com/modules/coder-labs/codex)** — OpenAI's Codex CLI, authenticated through Coder AI Gateway

The template clones `https://github.com/coder/coder` into `/home/coder/workspace/coder` with the [Git Clone](https://registry.coder.com/modules/coder/git-clone) module, then configures Claude Code and Codex to use that repo as their trusted workdir. Each workspace runs its own isolated Omnigent server. The admin password is derived from the workspace ID at runtime and never stored in Terraform state.

```tf
module "git_clone" {
  source  = "registry.coder.com/coder/git-clone/coder"
  version = "~> 2.0"

  agent_id    = coder_agent.main.id
  url         = "https://github.com/coder/coder"
  base_dir    = "/home/coder/workspace"
  folder_name = "coder"
}

module "codex" {
  source  = "registry.coder.com/coder-labs/codex/coder"
  version = "~> 5.2, >= 5.2.1"

  agent_id          = coder_agent.main.id
  workdir           = module.git_clone.repo_dir
  enable_ai_gateway = true
}

module "claude_code" {
  source  = "registry.coder.com/coder/claude-code/coder"
  version = "~> 5.2"

  agent_id          = coder_agent.main.id
  workdir           = module.git_clone.repo_dir
  enable_ai_gateway = true
}

module "omnigent" {
  source  = "registry.coder.com/matifali/omnigent/coder"
  version = "~> 0.0, >= 0.0.1"

  agent_id = coder_agent.main.id
}
```

## Prerequisites

- Docker with `sysbox-runc` runtime installed on the Coder host
- Coder Premium with AI Gateway enabled

The template checks for existing dependencies before installing missing packages. It installs `jq`, `tmux`, `bubblewrap`, and Node.js 22 when needed because the Claude Code module uses `jq` for setup, Codex needs a recent Node.js runtime, and Omnigent launches the Claude Code and Codex harnesses through local terminal sessions.
