---
display_name: code-server
description: VS Code in the browser
icon: ../../../../.icons/code.svg
maintainer_github: coder
verified: true
tags: [helper, ide, web]
---

# code-server

Automatically install [code-server](https://github.com/coder/code-server) in a workspace, create an app to access it via the dashboard, install extensions, and pre-configure editor settings.

```tf
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/code-server/coder"
  version  = "1.0.31"
  agent_id = coder_agent.example.id
}
```

![Screenshot 1](https://github.com/coder/code-server/raw/main/docs/assets/screenshot-1.png?raw=true)

## Examples

### Pin Versions

```tf
module "code-server" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/modules/code-server/coder"
  version         = "1.0.31"
  agent_id        = coder_agent.example.id
  install_version = "4.8.3"
}
```

### Pre-install Extensions

Install the Dracula theme from [OpenVSX](https://open-vsx.org/):

```tf
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/code-server/coder"
  version  = "1.0.31"
  agent_id = coder_agent.example.id
  extensions = [
    "dracula-theme.theme-dracula"
  ]
}
```

Enter the `<author>.<name>` into the extensions array and code-server will automatically install on start.

### Pre-configure Settings

Configure VS Code's [settings.json](https://code.visualstudio.com/docs/getstarted/settings#_settings-json-file) file:

```tf
module "code-server" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/modules/code-server/coder"
  version    = "1.0.31"
  agent_id   = coder_agent.example.id
  extensions = ["dracula-theme.theme-dracula"]
  settings = {
    "workbench.colorTheme" = "Dracula"
  }
}
```

### Install multiple extensions

Just run code-server in the background, don't fetch it from GitHub:

```tf
module "code-server" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/modules/code-server/coder"
  version    = "1.0.31"
  agent_id   = coder_agent.example.id
  extensions = ["dracula-theme.theme-dracula", "ms-azuretools.vscode-docker"]
}
```

### Offline and Use Cached Modes

By default the module looks for code-server at `/tmp/code-server` but this can be changed with `install_prefix`.

Run an existing copy of code-server if found, otherwise download from GitHub:

```tf
module "code-server" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/modules/code-server/coder"
  version    = "1.0.31"
  agent_id   = coder_agent.example.id
  use_cached = true
  extensions = ["dracula-theme.theme-dracula", "ms-azuretools.vscode-docker"]
}
```

Just run code-server in the background, don't fetch it from GitHub:

```tf
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/code-server/coder"
  version  = "1.0.31"
  agent_id = coder_agent.example.id
  offline  = true
}
```
