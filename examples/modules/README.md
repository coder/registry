---
display_name: MODULE_NAME
description: Describe what this module does
icon: ../../../../.icons/<A_RELEVANT_ICON>.svg
verified: false
tags: [helper]
---

# MODULE_NAME

<!-- Describes what this module does -->

```tf
module "MODULE_NAME" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/NAMESPACE/MODULE_NAME/coder"
  version = "1.0.0"
}
```

<!-- Add a screencast or screenshot here  put them in .images directory -->

## Examples

### Example 1

Install the Dracula theme from [OpenVSX](https://open-vsx.org/):

```tf
module "MODULE_NAME" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/NAMESPACE/MODULE_NAME/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  extensions = [
    "dracula-theme.theme-dracula"
  ]
}
```

Enter the `<author>.<name>` into the extensions array and code-server will automatically install on start.

### Example 2

Configure VS Code's [settings.json](https://code.visualstudio.com/docs/getstarted/settings#_settingsjson) file:

```tf
module "MODULE_NAME" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/NAMESPACE/MODULE_NAME/coder"
  version    = "1.0.0"
  agent_id   = coder_agent.example.id
  extensions = ["dracula-theme.theme-dracula"]
  settings = {
    "workbench.colorTheme" = "Dracula"
  }
}
```

### Example 3

Run code-server in the background, don't fetch it from GitHub:

```tf
module "MODULE_NAME" {
  source   = "registry.coder.com/NAMESPACE/MODULE_NAME/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  offline  = true
}
```

### Example 4: Air-Gapped Deployment with Git Source

For air-gapped environments, reference modules from internal Git repositories:

```tf
module "code_server" {
  source   = "git::https://internal-git.company.com/coder-modules.git//modules/code-server?ref=v1.0.19"
  agent_id = coder_agent.example.id
  offline  = true # Prevent external downloads
}
```

### Example 5: Air-Gapped Deployment with Local Path

Vendor modules directly in your template repository:

```tf
module "code_server" {
  source   = "./modules/code-server" # Relative path to vendored module
  agent_id = coder_agent.example.id
}
```

### Example 6: Private Registry

Use a private Terraform registry for air-gapped deployments:

```tf
module "code_server" {
  source   = "private-registry.company.com/coder/code-server/coder"
  version  = "1.0.19"
  agent_id = coder_agent.example.id
}
```
