---
display_name: Perplexica
description: Run Perplexica AI search engine in your workspace via Docker
icon: ../../../../.icons/perplexica.svg
verified: false
tags: [ai, search, docker]
---

# Perplexica

Run [Perplexica](https://github.com/ItzCrazyKns/Perplexica), a privacy-focused AI search engine, in your Coder workspace. Supports cloud providers (OpenAI, Anthropic Claude) and local LLMs via Ollama.

```tf
module "perplexica" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/perplexica/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

This module uses the full Perplexica image with embedded SearXNG for simpler setup with no external dependencies.

![Perplexica](../../.images/perplexica.png)

## Prerequisites

This module requires Docker to be available on the host.

## Examples

### With API Keys

```tf
module "perplexica" {
  count             = data.coder_workspace.me.start_count
  source            = "registry.coder.com/coder-labs/perplexica/coder"
  version           = "1.0.0"
  agent_id          = coder_agent.main.id
  openai_api_key    = var.openai_api_key
  anthropic_api_key = var.anthropic_api_key
}
```

### With Local Ollama

```tf
module "perplexica" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder-labs/perplexica/coder"
  version        = "1.0.0"
  agent_id       = coder_agent.main.id
  ollama_api_url = "http://ollama-external-endpoint:11434"
}
```
