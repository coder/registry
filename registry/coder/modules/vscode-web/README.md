---
display_name: VS Code Web
description: VS Code Web - Visual Studio Code in the browser
icon: ../../../../.icons/code.svg
verified: true
tags: [ide, vscode, web]
---

# VS Code Web

Automatically install [Visual Studio Code Server](https://code.visualstudio.com/docs/remote/vscode-server) in a workspace and create an app to access it via the dashboard.

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

### Keep extension secrets across browser reloads

Enable the official VS Code CLI's `serve-web` launcher on glibc-based Linux or macOS (x64/arm64) to provide encrypted browser secret storage. The existing `serve-local` launcher remains the default. CLI mode currently excludes Alpine. Linux uses the official tar archives; macOS uses the official ZIP archives with the system's `unzip` and BSD `tar`.

```tf
module "vscode-web" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "2.0.0"
  agent_id       = coder_agent.example.id
  accept_license = true
  use_cli        = true
  subdomain      = true
  folder         = "/home/coder/project"
}
```

Use a Coder deployment with wildcard application URLs and HTTPS. Each workspace needs its own application subdomain because browser secrets are scoped to an origin. The module downloads the server archive for the selected `platform` and prepares a launcher for that version. The launcher passes the custom extensions directory and workspace trust option to the server started by the CLI. These options can be used together. Choose an archive that runs on your workspace OS and architecture.

The server's encryption key, version marker, and server cache live under `$HOME/.coder-modules/coder/vscode-web/`. Persist that directory along with the workspace home. Secrets also depend on the browser's site data: deleting that data, losing the server key, or changing the app origin requires signing in again. Existing in-memory sessions are not migrated when switching launch modes.

CLI mode installs its executable under the module directory by default; a custom `install_prefix` changes the executable location. Installation and startup diagnostics are in `logs/install.log` and `logs/start.log` under the module directory. The running server writes to `logs/serve-web.log`, or to a custom `log_path` when supplied. Machine settings stay under `$HOME/.vscode-server`. Set `extensions_dir` to use the same custom directory for extension installation and startup.

With `use_cached = true`, the recorded version is reused unless `commit_id` selects another version. Offline mode requires both the matching CLI and server to have been installed previously, and cannot install extensions. An explicit commit ID pins both downloads. The server is prepared in the CLI's commit-based cache so existing settings and extension installation can be reused without introducing a second installation pipeline.

#### Upgrading from 1.x

Version 2.x requires the Coder Terraform provider **2.13 or later** for `coder-utils`, including when CLI mode is disabled. Terraform **1.2 or later** is required for resource preconditions. The default launcher and its existing options remain unchanged. Terraform migrates the existing startup resource address automatically.

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

### Pre-configure Machine Settings

Configure VS Code's [Machine settings.json](https://code.visualstudio.com/docs/getstarted/settings#_settings-json-file). These settings are merged with any existing machine settings on startup:

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

> [!WARNING]
> Merging settings requires `jq` or `python3`. If neither is available, existing machine settings will be preserved. User settings configured through the VS Code UI are stored in browser local storage and will not persist across different browsers or devices.

### Pin a specific VS Code Web version

By default, this module installs the latest. To pin a specific version, retrieve the commit ID from the [VS Code Update API](https://update.code.visualstudio.com/api/commits/stable/server-linux-x64-web) and verify its corresponding release on the [VS Code GitHub Releases](https://github.com/microsoft/vscode/releases).

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

### Open an existing workspace on startup

To open an existing workspace on startup the `workspace` parameter can be used to represent a path on disk to a `code-workspace` file.
Note: Either `workspace` or `folder` can be used, but not both simultaneously. The `code-workspace` file must already be present on disk.

```tf
module "vscode-web" {
  count     = data.coder_workspace.me.start_count
  source    = "registry.coder.com/coder/vscode-web/coder"
  version   = "2.0.0"
  agent_id  = coder_agent.example.id
  workspace = "/home/coder/coder.code-workspace"
}
```
