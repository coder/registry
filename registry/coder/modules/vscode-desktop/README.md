---
display_name: VS Code Desktop
description: Add a one-click button to launch VS Code Desktop
icon: ../../../../.icons/code.svg
verified: true
tags: [ide, vscode]
---

# VS Code Desktop

Add a button to open any workspace with a single click.

Uses the [Coder Remote VS Code Extension](https://github.com/coder/vscode-coder).

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
}
```

## Examples

### Open in a specific directory

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
}
```

### Pre-install extensions on the workspace host

Use `extensions` to install VS Code extension IDs before the first ordinary VS Code Desktop connection. The module downloads the official stable VS Code Server and installs the extensions under `~/.vscode-server/extensions`.

```tf
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id

  extensions = [
    "ms-python.python",
    "esbenp.prettier-vscode@12.4.0",
  ]
}
```

The installation blocks ordinary workspace login for up to 30 minutes so extensions are ready before VS Code Desktop connects. A download, extraction, validation, or extension installation failure remains visible in the Coder startup logs. Later workspace starts reuse the existing VS Code Server CLI and do not force extension updates.

The workspace image must provide Bash, `base64`, `sed`, `tar`, and either `curl` or `wget`. The workspace also needs HTTPS egress to the VS Code update and artifact hosts. Extension availability and compatibility depend on the Visual Studio Marketplace; use `publisher.extension@version` to request a specific version.
