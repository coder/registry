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

![Open WebUI](../../.images/openwebui.png)

## Prerequisites

- **Python 3.11 or higher** must be installed in your image (with `venv` module)
- Port 7800 (default) or your custom port must be available

For Ubuntu/Debian, you can install Python 3.11 from [deadsnakes PPA](https://launchpad.net/~deadsnakes/+archive/ubuntu/ppa):

```shell
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt-get update
sudo apt-get install -y python3.11 python3.11-venv
```

## Basic Usage

```tf
module "open-webui" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder-labs/open-webui/coder"
  version  = "0.9.0"
  agent_id = coder_agent.main.id

  openai_api_key = "sk-proj-1234..."
}
```
