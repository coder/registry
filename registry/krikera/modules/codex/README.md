---
display_name: "OpenAI Codex"
description: "Rust-based OpenAI Codex CLI with AgentAPI web chat UI and task reporting"
icon: "../../../../.icons/claude.svg"
verified: false
tags: ["ai", "assistant", "codex", "openai", "rust", "tasks"]
---

# OpenAI Codex CLI

A Rust-based OpenAI Codex CLI tool with AgentAPI web chat UI integration and full task reporting support for Coder + Tasks UI.


```tf
module "codex" {
  source   = "registry.coder.com/krikera/codex/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Examples

### Basic Usage

```tf
module "codex" {
  source   = "registry.coder.com/krikera/codex/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

### Custom Configuration

```tf
module "codex" {
  source       = "registry.coder.com/krikera/codex/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.example.id
  openai_model = "gpt-4"
  temperature  = 0.7
  max_tokens   = 2048
  folder       = "/home/coder/workspace"
}
```

### With Custom OpenAI API Key

```tf
module "codex" {
  source         = "registry.coder.com/krikera/codex/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  openai_api_key = var.openai_api_key
}
```

### Advanced Configuration

```tf
module "codex" {
  source             = "registry.coder.com/krikera/codex/coder"
  version            = "1.0.0"
  agent_id           = coder_agent.example.id
  openai_model       = "gpt-4"
  temperature        = 0.2
  max_tokens         = 4096
  install_codex      = true
  codex_version      = "latest"
  pre_install_script = "apt-get update && apt-get install -y build-essential"
  folder             = "/workspace"
  order              = 1
  group              = "AI Tools"
}
```

### With Task Reporting

```tf
data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Write a prompt for the Codex CLI"
  mutable     = true
}

module "codex" {
  source         = "registry.coder.com/krikera/codex/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.example.id
  openai_api_key = var.openai_api_key
  ai_prompt      = data.coder_parameter.ai_prompt.value
  folder         = "/home/coder/projects"
}
```
