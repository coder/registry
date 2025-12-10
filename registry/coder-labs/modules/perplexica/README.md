---
display_name: Perplexica
description: Run Perplexica AI search engine in your workspace via Docker
icon: ../../../../.icons/perplexica.svg
verified: false
tags: [ai, search, docker]
---

# Perplexica

Run [Perplexica](https://github.com/ItzCrazyKns/Perplexica), a privacy-focused AI search engine, in your Coder workspace.

```tf
module "perplexica" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/perplexica/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```

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
