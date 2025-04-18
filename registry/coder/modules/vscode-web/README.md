---
display_name: VS Code Web
description: VS Code Web - Visual Studio Code in the browser
icon: ../../../../.icons/code.svg
maintainer_github: coder
verified: true
tags: [helper, ide, vscode, web]
---

# VS Code Web

Automatically install [Visual Studio Code Server](https://code.visualstudio.com/docs/remote/vscode-server) in a workspace and create an app to access it via the dashboard.

```tf
module "vscode-web" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/modules/vscode-web/coder"
  version        = "1.0.30"
  agent_id       = coder_agent.example.id
  accept_license = true
}
```

![VS Code Web with GitHub Copilot and live-share](../../.images/vscode-web.gif)

## Examples

### Install VS Code Web to a custom folder

```tf
module "vscode-web" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/modules/vscode-web/coder"
  version        = "1.0.30"
  agent_id       = coder_agent.example.id
  install_prefix = "/home/coder/.vscode-web"
  folder         = "/home/coder"
  accept_license = true
}
```

### Install Extensions

```tf
module "vscode-web" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/modules/vscode-web/coder"
  version        = "1.0.30"
  agent_id       = coder_agent.example.id
  extensions     = ["github.copilot", "ms-python.python", "ms-toolsai.jupyter"]
  accept_license = true
}
```

### Pre-configure Settings

Configure VS Code's [settings.json](https://code.visualstudio.com/docs/getstarted/settings#_settings-json-file) file:

```tf
module "vscode-web" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/modules/vscode-web/coder"
  version    = "1.0.30"
  agent_id   = coder_agent.example.id
  extensions = ["dracula-theme.theme-dracula"]
  settings = {
    "workbench.colorTheme" = "Dracula"
  }
  accept_license = true
}
```

### Pin a specific VS Code Web version

By default, this module installs the latest. To pin a specific version, retrieve the commit ID from the [VS Code Update API](https://update.code.visualstudio.com/api/commits/stable/server-linux-x64-web) and verify its corresponding release on the [VS Code GitHub Releases](https://github.com/microsoft/vscode/releases).

```tf
module "vscode-web" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/modules/vscode-web/coder"
  version        = "1.0.30"
  agent_id       = coder_agent.example.id
  commit_id      = "e54c774e0add60467559eb0d1e229c6452cf8447"
  accept_license = true
}
```
