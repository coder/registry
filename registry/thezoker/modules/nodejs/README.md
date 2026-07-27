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
  default_node_version = "1.0.13"
}
```

## Pre and Post Install Scripts

Use `pre_install_script` and `post_install_script` to run custom scripts before and after Node.js is installed. They are orchestrated with the [`coder-utils`](https://registry.coder.com/modules/coder/coder-utils) module, which runs them in order via `coder exp sync`.

> [!NOTE]
> Node.js is installed via nvm, which only loads automatically in interactive login shells. `post_install_script` runs in a fresh non-interactive shell, so source nvm first to put `node` and `npm` on `PATH`. nvm is installed at `$HOME/<nvm_install_prefix>/nvm` (default `$HOME/.nvm/nvm`).

```tf
module "nodejs" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/thezoker/nodejs/coder"
  version  = "1.1.0"
  agent_id = coder_agent.example.id

  pre_install_script  = "echo 'Setting up prerequisites...'"
  post_install_script = <<-EOT
    export NVM_DIR="$HOME/.nvm/nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    npm install -g yarn pnpm
  EOT
}
```

## Full example

A example with all available options:

```tf
module "nodejs" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/thezoker/nodejs/coder"
  version            = "1.1.0"
  agent_id           = coder_agent.example.id
  nvm_version        = "1.0.13"
  nvm_install_prefix = "/opt/nvm"
  node_versions = [
    "16",
    "18",
    "node"
  ]
  default_node_version = "1.0.13"
  pre_install_script   = "echo 'Pre-install setup'"
  post_install_script  = <<-EOT
    export NVM_DIR="$HOME/opt/nvm/nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    npm install -g typescript
  EOT
}
```
