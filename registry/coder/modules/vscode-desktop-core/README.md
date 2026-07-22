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

Wrapper modules can also use the core to pre-install extensions before the first IDE connection. The wrapper remains responsible for supplying its verified remote server CLI, extension storage path, and a finite bootstrap script when the CLI is not available on a new workspace. The core creates no extension installation script when `extensions` is empty.

The dedicated extension script blocks ordinary workspace login by default and has a 30-minute timeout. Coder users can manually bypass startup blocking, and an installation failure leaves the workspace marked incomplete. Repeated starts do not force-update extensions that the remote CLI already recognizes as installed; wrappers can pass an explicit `publisher.extension@version` when they need a specific version.

```tf
module "vscode-desktop-core" {
  source  = "registry.coder.com/coder/vscode-desktop-core/coder"
  version = "1.2.0"

  agent_id = var.agent_id

  coder_app_icon         = "/icon/code.svg"
  coder_app_slug         = "vscode"
  coder_app_display_name = "VS Code Desktop"
  coder_app_order        = var.order
  coder_app_group        = var.group

  folder      = var.folder
  open_recent = var.open_recent
  protocol    = "vscode"
  config_dir  = var.config_dir

  extensions             = var.extensions
  extensions_dir         = local.remote_extensions_dir
  ide_cli_path           = local.remote_ide_cli_path
  ide_cli_install_script = local.install_remote_ide_cli
}
```
