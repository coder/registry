---
display_name: Python
description: Install Python 3, pip, venv, and a python alias on Debian/Ubuntu workspaces
icon: ../../../../.icons/python.svg
maintainer_github: AttractiveToad
verified: false
tags: [helper, python]
---

# Python

Installs Python 3 and common Python tooling with `apt-get` on Debian/Ubuntu workspaces. The install script is idempotent: it skips work when all configured packages are already installed. When `python` is missing, the module creates `/usr/local/bin/python` as an alias for `python3`.

```tf
module "python" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/attractivetoad/python/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Examples

Install only a subset of Python packages:

```tf
module "python" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/attractivetoad/python/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id

  python_packages = ["python3", "python3-pip"]
}
```

Skip the package index update when your image already has a fresh apt cache:

```tf
module "python" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/attractivetoad/python/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id

  update_packages = false
}
```
