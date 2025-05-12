---
display_name: Node.js
description: Install Node.js via nvm
icon: ../../../../.icons/node.svg
maintainer_github: TheZoker
verified: false
tags: [helper]
---

# nodejs

Automatically installs [Node.js](https://github.com/nodejs/node) via [`nvm`](https://github.com/nvm-sh/nvm). It can also install multiple versions of node and set a default version. If no options are specified, the latest version is installed.

```tf
module "nodejs" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/thezoker/nodejs/coder"
  version  = "1.0.11"
  agent_id = coder_agent.example.id
}
```

## Install multiple versions

This installs multiple versions of Node.js:

```tf
module "nodejs" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/thezoker/nodejs/coder"
  version  = "1.0.11"
  agent_id = coder_agent.example.id
  node_versions = [
    "18",
    "20",
    "node"
  ]
  default_node_version = "20"
}
```

## Full example

A example with all available options:

```tf
module "nodejs" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/thezoker/nodejs/coder"
  version            = "1.0.11"
  agent_id           = coder_agent.example.id
  nvm_version        = "v0.39.7"
  nvm_install_prefix = "/opt/nvm"
  node_versions = [
    "16",
    "18",
    "node"
  ]
  default_node_version = "16"
}
```
