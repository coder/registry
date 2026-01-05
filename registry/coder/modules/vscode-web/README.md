---
display_name: VS Code Web
description: VS Code Web - Visual Studio Code in the browser
icon: ../../../../.icons/code.svg
verified: true
tags: [ide, vscode, web]
---

# VS Code Web

Automatically install the [VS Code CLI](https://code.visualstudio.com/docs/editor/command-line) and run `code serve-web` in a workspace to access VS Code via the browser.

```tf
module "vscode-web" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "2.0.0"
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
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "2.0.0"
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
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "2.0.0"
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
  source     = "registry.coder.com/coder/vscode-web/coder"
  version    = "2.0.0"
  agent_id   = coder_agent.example.id
  extensions = ["dracula-theme.theme-dracula"]
  settings = {
    "workbench.colorTheme" = "Dracula"
  }
  accept_license = true
}
```

### Open an existing workspace on startup

To open an existing workspace on startup the `workspace` parameter can be used to represent a path on disk to a `code-workspace` file.
Note: Either `workspace` or `folder` can be used, but not both simultaneously. The `code-workspace` file must already be present on disk.

```tf
module "vscode-web" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "2.0.0"
  agent_id       = coder_agent.example.id
  workspace      = "/home/coder/coder.code-workspace"
  accept_license = true
}
```

### Use VS Code Insiders

Use the VS Code Insiders release channel to get the latest features and bug fixes:

```tf
module "vscode-web" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/vscode-web/coder"
  version         = "2.0.0"
  agent_id        = coder_agent.example.id
  release_channel = "insiders"
  accept_license  = true
}
```

### Pin a specific VS Code version

Use the `commit_id` variable to pin a specific VS Code Server version by its commit SHA:

```tf
module "vscode-web" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "2.0.0"
  agent_id       = coder_agent.example.id
  commit_id      = "e54c774e0add60467559eb0d1e229c6452cf8447"
  accept_license = true
}
```

You can find the commit SHA for a specific VS Code version on the [VS Code releases page](https://code.visualstudio.com/updates) or by checking the "About" dialog in VS Code.
