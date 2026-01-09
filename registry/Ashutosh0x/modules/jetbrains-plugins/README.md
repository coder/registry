---
display_name: JetBrains Plugins
description: Pre-install JetBrains IDE plugins in Coder workspaces automatically
icon: ../../../../.icons/jetbrains-toolbox.svg
verified: false
tags: [jetbrains, ide, plugins, development, intellij, pycharm, goland]
---

# JetBrains Plugins

Automatically pre-install JetBrains IDE plugins in Coder workspaces on startup.

This module downloads and installs plugins from the [JetBrains Marketplace](https://plugins.jetbrains.com/) to your IDE's plugins directory, so they're ready when you open the IDE.

```tf
module "jetbrains_plugins" {
  source   = "registry.coder.com/Ashutosh0x/jetbrains-plugins/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  plugins = [
    "org.jetbrains.plugins.github",
    "com.intellij.kubernetes"
  ]

  ide_product_codes = ["IU", "GO"]
}
```

## Finding Plugin IDs

1. Go to [JetBrains Marketplace](https://plugins.jetbrains.com/)
2. Search for your plugin
3. The plugin ID is in the URL or on the plugin page

### Popular Plugin IDs

| Plugin | ID |
|--------|-----|
| GitHub | `org.jetbrains.plugins.github` |
| Kubernetes | `com.intellij.kubernetes` |
| Docker | `Docker` |
| Rust | `org.rust.lang` |
| Go | `org.jetbrains.plugins.go` |
| Python | `Pythonid` |
| GitToolBox | `zielu.gittoolbox` |
| Rainbow Brackets | `izhangzhihao.rainbow.brackets` |
| Material Theme UI | `com.chrisrm.idea.MaterialThemeUI` |

## IDE Product Codes

| Code | IDE |
|------|-----|
| IU | IntelliJ IDEA Ultimate |
| IC | IntelliJ IDEA Community |
| PY | PyCharm Professional |
| PC | PyCharm Community |
| GO | GoLand |
| WS | WebStorm |
| PS | PhpStorm |
| RD | Rider |
| CL | CLion |
| RM | RubyMine |
| RR | RustRover |

## Examples

### Install plugins for multiple IDEs

```tf
module "jetbrains_plugins" {
  source   = "registry.coder.com/Ashutosh0x/jetbrains-plugins/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  plugins = [
    "zielu.gittoolbox",
    "izhangzhihao.rainbow.brackets"
  ]

  ide_product_codes = ["IU", "PY", "GO", "WS"]
}
```

### With custom plugins directory

```tf
module "jetbrains_plugins" {
  source   = "registry.coder.com/Ashutosh0x/jetbrains-plugins/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id

  plugins     = ["Docker"]
  plugins_dir = "/home/coder/.jetbrains/plugins"
}
```

## How It Works

1. On workspace start, the module runs a script that:
   - Creates plugin directories for each target IDE
   - Downloads plugins from JetBrains Marketplace
   - Extracts them to the IDE's plugins folder
2. When you open the IDE, plugins are already available

## Notes

- Works with JetBrains Toolbox and standalone IDE installations
- Plugins are downloaded only if not already present
- Supports both Linux and macOS workspaces
