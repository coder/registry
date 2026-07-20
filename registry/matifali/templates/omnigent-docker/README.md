---
display_name: Omnigent Docker
icon: ../../../../.icons/omnigent.svg
description: Omnigent with Claude Code, Codex, and Coder AI Gateway on Docker.
verified: false
tags: [docker, container, omnigent, ai, agent, ai-gateway]
---

# Omnigent Docker

Combines three AI agent modules on Docker:

- **[Omnigent](https://registry.coder.com/modules/matifali/omnigent)** — private multi-agent coding orchestrator server
- **[Claude Code](https://registry.coder.com/modules/coder/claude-code)** — Anthropic's Claude in your terminal, authenticated through Coder AI Gateway
- **[Codex](https://registry.coder.com/modules/coder-labs/codex)** — OpenAI's Codex CLI, authenticated through Coder AI Gateway

Clones `https://github.com/coder/coder` into `/home/coder/workspace/coder` with the [Git Clone](https://registry.coder.com/modules/coder/git-clone) module, then configures Claude Code and Codex to use the repository as their trusted workdir. Omnigent runs as an isolated server, with an admin password derived at runtime and never stored in Terraform state.

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
  version = "~> 5.2"

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
  version = "~> 0.0"

  agent_id = coder_agent.main.id
}
```

## Prerequisites

- Docker with `sysbox-runc` runtime installed on the Coder host
- Coder Premium with AI Gateway enabled

The setup checks for existing dependencies before installing missing packages. It installs `jq`, `tmux`, `bubblewrap`, and Node.js 22 when needed because the Claude Code module uses `jq` for setup, Codex needs a recent Node.js runtime, and Omnigent launches the Claude Code and Codex harnesses through local terminal sessions.
