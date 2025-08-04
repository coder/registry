---
display_name: VS Code Desktop Enhanced
description: Add a one-click button to launch VS Code Desktop with pre-installed extensions and settings
icon: ../../../../.icons/code.svg
verified: true
tags: [ide, vscode, extensions, settings]
---

# VS Code Desktop Enhanced

Add a button to open any workspace with a single click, with support for pre-installing VS Code extensions and applying custom settings. This module extends the basic VS Code Desktop functionality by automatically setting up your development environment.

Uses the [Coder Remote VS Code Extension](https://github.com/coder/vscode-coder).

## Features

- 🚀 One-click VS Code Desktop launch
- 📦 Automatic extension installation
- ⚙️ Custom settings configuration
- 📁 Workspace-specific recommendations
- 🔄 Settings merging with existing configuration

## Quick Start

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop-enhanced/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
}
```

## Examples

### Basic usage with extensions

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop-enhanced/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  
  extensions = [
    "ms-python.python",
    "ms-vscode.vscode-typescript-next",
    "esbenp.prettier-vscode"
  ]
}
```

### With custom settings

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop-enhanced/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  
  extensions = [
    "ms-python.python",
    "ms-vscode.pylint"
  ]
  
  settings = jsonencode({
    "python.defaultInterpreterPath" = "/usr/bin/python3"
    "editor.fontSize" = 14
    "editor.tabSize" = 4
    "workbench.colorTheme" = "Dark+ (default dark)"
    "files.autoSave" = "afterDelay"
    "terminal.integrated.defaultProfile.linux" = "bash"
  })
}
```

### Open in a specific directory with full configuration

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop-enhanced/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
  
  extensions = [
    "ms-vscode.vscode-json",
    "redhat.vscode-yaml",
    "ms-vscode.vscode-typescript-next",
    "esbenp.prettier-vscode",
    "bradlc.vscode-tailwindcss"
  ]
  
  settings = jsonencode({
    "editor.formatOnSave" = true
    "editor.codeActionsOnSave" = {
      "source.fixAll.eslint" = true
    }
    "prettier.singleQuote" = true
    "prettier.semi" = false
    "workbench.startupEditor" = "newUntitledFile"
    "explorer.confirmDelete" = false
  })
}
```

### Development team configuration

```tf
locals {
  # Shared development extensions
  dev_extensions = [
    "ms-vscode.vscode-typescript-next",
    "esbenp.prettier-vscode",
    "ms-vscode.vscode-eslint",
    "bradlc.vscode-tailwindcss",
    "ms-vscode.vscode-json"
  ]
  
  # Team settings
  team_settings = {
    "editor.formatOnSave" = true
    "editor.tabSize" = 2
    "editor.insertSpaces" = true
    "files.trimTrailingWhitespace" = true
    "files.insertFinalNewline" = true
    "workbench.editor.enablePreview" = false
    "git.autofetch" = true
    "prettier.singleQuote" = true
    "prettier.trailingComma" = "es5"
  }
}

module "vscode" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/vscode-desktop-enhanced/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.example.id
  folder     = "/home/coder/workspace"
  extensions = local.dev_extensions
  settings   = jsonencode(local.team_settings)
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `agent_id` | The ID of a Coder agent | `string` | n/a | yes |
| `folder` | The folder to open in VS Code | `string` | `""` | no |
| `open_recent` | Open the most recent workspace or folder | `bool` | `false` | no |
| `order` | The order determines the position of app in the UI presentation | `number` | `null` | no |
| `group` | The name of a group that this app belongs to | `string` | `null` | no |
| `extensions` | List of VS Code extension IDs to pre-install | `list(string)` | `[]` | no |
| `settings` | VS Code settings in JSON format to be applied | `string` | `"{}"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vscode_url` | VS Code Desktop URL |
| `extensions_installed` | List of VS Code extensions that will be installed |
| `settings_applied` | Status of VS Code settings configuration |

## Extension Installation

Extensions are installed automatically when the workspace starts. The module:

1. Creates the necessary VS Code server directories
2. Downloads and installs the VS Code CLI if not available
3. Installs each extension specified in the `extensions` variable
4. Creates workspace recommendations in `.vscode/extensions.json`

## Settings Configuration

Settings are applied by:

1. Creating or updating the VS Code user settings file
2. Merging new settings with existing ones (when `jq` is available)
3. Ensuring settings persist across workspace restarts

## Popular Extension Examples

### Web Development
```tf
extensions = [
  "ms-vscode.vscode-typescript-next",
  "esbenp.prettier-vscode",
  "ms-vscode.vscode-eslint",
  "bradlc.vscode-tailwindcss",
  "formulahendry.auto-rename-tag",
  "ms-vscode.vscode-json"
]
```

### Python Development
```tf
extensions = [
  "ms-python.python",
  "ms-python.pylint",
  "ms-python.black-formatter",
  "ms-python.isort",
  "ms-toolsai.jupyter"
]
```

### Go Development
```tf
extensions = [
  "golang.go",
  "ms-vscode.vscode-json"
]
```

### DevOps/Infrastructure
```tf
extensions = [
  "hashicorp.terraform",
  "ms-kubernetes-tools.vscode-kubernetes-tools",
  "ms-vscode.vscode-docker",
  "redhat.vscode-yaml"
]
```

## Requirements

- Coder agent with internet access for extension downloads
- VS Code Desktop with the Coder Remote extension installed
- Bash shell (for the setup script)

## Notes

- Extensions are installed on the remote host (workspace), not locally
- Settings are applied to the VS Code server configuration
- The setup script runs automatically when the workspace starts
- Extensions and settings are preserved across workspace restarts
- If extension installation fails, the workspace will still start normally
