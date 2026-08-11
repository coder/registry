---
display_name: Python
description: Install and manage a configurable Python version with pyenv
icon: ../../../../.icons/python.svg
maintainer_github: AttractiveToad
verified: false
tags: [helper, python]
---

# Python

Installs pyenv and uses it to build and select a configurable Python version on Debian/Ubuntu workspaces. The module installs the required build dependencies with `apt-get` and skips Python builds that already exist.

```tf
module "python" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/attractivetoad/python/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Examples

Install and globally select a different Python version:

```tf
module "python" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/attractivetoad/python/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id

  python_version = "3.12.11"
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
