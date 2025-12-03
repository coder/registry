---
display_name: Open WebUI
description: A self-hosted AI chat interface supporting various LLM providers
icon: ../../../../.icons/openai.svg
verified: false
tags: [ai, llm, chat, web-ui, python]
---

# Open WebUI

Open WebUI is a user-friendly web interface for interacting with Large Language Models. It provides a ChatGPT-like interface that can connect to various LLM providers including OpenAI, Ollama, and more.

This module installs and runs Open WebUI using Python and pip within your Coder workspace.

## Prerequisites

- **Python 3.11 or higher** (automatically installed from deadsnakes PPA if not present)
- `pip` package manager
- `sudo` access (for automatic Python installation if needed)
- Port 8080 (default) or your custom port must be available

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

## Examples

### Custom Port

Run Open WebUI on a custom port:

```tf
module "open-webui" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/open-webui/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  port     = 3000
}
```

### Public Sharing

Make Open WebUI accessible to authenticated Coder users:

```tf
module "open-webui" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/open-webui/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  share    = "authenticated"
}
```

### Custom Log Path and Grouping

```tf
module "open-webui" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/open-webui/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  log_path = "/var/log/open-webui.log"
  group    = "AI Tools"
  order    = 1
}
```

## Features

- 🐍 Pure Python installation (no Docker required)
- 🔄 Automatic Python 3.11+ installation from deadsnakes PPA
- 💾 Data stored in `~/.open-webui` directory
- 🚀 Runs in background as a Python process
- 📝 Configurable logging
- 🌐 Subdomain support for clean URLs
- 🔧 Compatible with various LLM providers (OpenAI, Ollama, etc.)

## Data Persistence

Open WebUI data is stored in `~/.open-webui` directory in your workspace, which includes:
- User accounts
- Chat history
- Settings and configurations
- Model configurations

## Installation Process

The module automatically handles the installation:

1. **Check Python Version**: Looks for Python 3.11+ (checks python3.13, python3.12, python3.11, python3, python)
2. **Install Python if Needed**: If not found, installs Python 3.11 from deadsnakes PPA
3. **Install pip**: Ensures pip is available
4. **Install Open WebUI**: Installs open-webui package via pip
5. **Start Server**: Launches Open WebUI on the specified port

