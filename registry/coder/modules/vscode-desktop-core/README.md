---
display_name: Coder VSCode Desktop Core
description: Building block for modules that need to link to an external VSCode-based IDE
icon: ../../../../.icons/coder.svg
verified: true
tags: [internal, library]
---

# VS Code Desktop Core

> [!CAUTION]
> We do not recommend using this module directly. Instead, please consider using one of our [Desktop IDE modules](https://registry.coder.com/modules?search=tag%3Aide).

The VSCode Desktop Core module is a building block for modules that need to expose access to VSCode-based IDEs. It is intended primarily for internal use by Coder to create modules for VSCode-based IDEs.

```tf
module "vscode-desktop-core" {
  source  = "registry.coder.com/coder/vscode-desktop-core/coder"
  version = "1.0.1"

  agent_id = var.agent_id

  web_app_icon         = "/icon/code.svg"
  web_app_slug         = "vscode"
  web_app_display_name = "VS Code Desktop"
  web_app_order        = var.order
  web_app_group        = var.group

  folder      = var.folder
  open_recent = var.open_recent
  protocol    = "vscode"
}
```
