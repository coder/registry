---
display_name: Python
description: Install Python 3, pip, venv, and python-is-python3 on Debian/Ubuntu workspaces
icon: ../../../../.icons/python.svg
maintainer_github: TheZoker
verified: false
tags: [helper, python]
---

# Python

Installs Python 3 and common Python tooling with `apt-get` on Debian/Ubuntu workspaces. The install script is idempotent: it skips work when all configured packages are already installed.

```tf
module "python" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/thezoker/python/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Examples

Install only a subset of Python packages:

```tf
module "python" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/thezoker/python/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id

  python_packages = ["python3", "python3-pip", "python3-venv"]
}
```

Run custom scripts before and after installation:

```tf
module "python" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/thezoker/python/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id

  pre_install_script  = "echo Preparing Python install"
  post_install_script = "python3 --version"
}
```
