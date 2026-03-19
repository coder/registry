---
display_name: Node.js
description: Install Node.js via nvm
icon: ../../../../.icons/node.svg
maintainer_github: TheZoker
verified: false
tags: [helper, nodejs]
---

# nodejs

Automatically installs [Node.js](https://github.com/nodejs/node) via [`nvm`](https://github.com/nvm-sh/nvm). It can also install multiple versions of node and set a default version. If no options are specified, the latest version is installed.

```tf
module "nodejs" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/thezoker/nodejs/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id
}
```

## Install multiple versions

This installs multiple versions of Node.js:

```tf
module "nodejs" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/thezoker/nodejs/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id
  node_versions = [
    "18",
    "20",
    "node"
  ]
  default_node_version = "20"
}
```

## Pre and Post Install Scripts

Use `pre_install_script` and `post_install_script` to run custom scripts before and after Node.js installation.

```tf
module "nodejs" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/thezoker/nodejs/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id

  pre_install_script  = "echo 'Setting up prerequisites...'"
  post_install_script = "npm install -g yarn pnpm"
}
```

## Cross-Module Dependency Ordering

This module uses `coder exp sync` to coordinate execution ordering with other modules. It exposes the following outputs for use with `coder exp sync want`:

- `install_script_name` — the sync name for the main Node.js installation script
- `pre_install_script_name` — the sync name for the pre-install script
- `post_install_script_name` — the sync name for the post-install script

For example, to ensure another module waits for Node.js to be fully installed:

```tf
module "nodejs" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/thezoker/nodejs/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id
}

# In another module's coder_script, wait for Node.js installation:
# coder exp sync want my-script ${module.nodejs[0].install_script_name}
```

## Full example

A example with all available options:

```tf
module "nodejs" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/thezoker/nodejs/coder"
  version            = "1.1.0"
  agent_id           = coder_agent.example.id
  nvm_version        = "v0.39.7"
  nvm_install_prefix = "/opt/nvm"
  node_versions = [
    "18",
    "20",
    "node"
  ]
  default_node_version = "20"
  pre_install_script   = "echo 'Pre-install setup'"
  post_install_script  = "npm install -g typescript"
}
```
