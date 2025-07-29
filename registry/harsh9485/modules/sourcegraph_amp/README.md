---
display_name: sourcegraph_amp
description: Describe what this module does
icon: ../../../../.icons/sourcegraph-amp.svg
verified: false
tags: [helper]
---

# sourcegraph_amp

<!-- Describes what this module does -->

```tf
module "sourcegraph_amp" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/harsh9485/sourcegraph_amp/coder"
  version = "1.0.0"
}
```

<!-- Add a screencast or screenshot here  put them in .images directory -->

## Examples

### Example 1

Install the Dracula theme from [OpenVSX](https://open-vsx.org/):

```tf
module "sourcegraph_amp" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/NAMESPACE/sourcegraph_amp/coder"
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
module "sourcegraph_amp" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/NAMESPACE/sourcegraph_amp/coder"
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
module "sourcegraph_amp" {
  source   = "registry.coder.com/NAMESPACE/sourcegraph_amp/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  offline  = true
}
```
