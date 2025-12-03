---
display_name: Open WebUI
description: A self-hosted AI chat interface supporting various LLM providers
icon: ../../../../.icons/openwebui.svg
verified: true
tags: [ai, llm, chat, web-ui, python]
---

# Open WebUI

Open WebUI is a user-friendly web interface for interacting with Large Language Models. It provides a ChatGPT-like interface that can connect to various LLM providers including OpenAI, Ollama, and more.

This module installs and runs Open WebUI using Python and pip within your Coder workspace.

## Prerequisites

- **Python 3.11 or higher** (automatically installed from [deadsnakes PPA](https://launchpad.net/~deadsnakes/+archive/ubuntu/ppa) if not present)
- `pip` package manager
- `sudo` access (for automatic Python installation if needed)
- Port 7800 (default) or your custom port must be available

**Note:** If Python 3.11+ is not found, the module will automatically:
1. Add the deadsnakes PPA repository
2. Install Python 3.11 with venv and dev packages
3. Install pip if not available

## Basic Usage

```tf
module "open-webui" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/open-webui/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```