---
display_name: JetBrains with Plugin Configuration
description: A complete JetBrains IDE module with automatic plugin pre-configuration for workspaces.
icon: ../../../../.icons/jetbrains.svg
maintainer_github: sahelisaha04
verified: false
tags: [ide, jetbrains, plugins, parameter]
---

# JetBrains IDEs with Plugin Configuration

This module provides complete JetBrains IDE integration with automatic plugin pre-configuration capabilities. It implements full JetBrains Gateway functionality with plugin management features.

```tf
module "jetbrains_with_plugins" {
  source   = "registry.coder.com/saheli/jetbrains-plugins/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
  
  # Standard JetBrains module options
  default = ["IU", "PY"]
  
  # NEW: Plugin pre-configuration
  plugins = [
    "org.jetbrains.plugins.github",           # GitHub integration
    "com.intellij.ml.llm",                    # AI Assistant
    "Pythonid",                               # Python support for IntelliJ
    "org.intellij.plugins.markdown"           # Markdown support
  ]
}
```

## Features

✅ **Complete JetBrains integration** - Full IDE functionality with Gateway support  
✅ **Plugin pre-configuration** - Automatically suggests plugins when IDE opens  
✅ **Project-level integration** - Creates `.idea/externalDependencies.xml`  
✅ **Gateway compatible** - Works with JetBrains Gateway workflow  
✅ **Zero setup required** - No manual IDE installation needed  
✅ **Standalone implementation** - No external module dependencies

## How It Works

1. **JetBrains apps** are created directly with full Gateway integration
2. **Plugin configuration script** runs on workspace start (when plugins specified)
3. **IDE configuration files** are created for automatic plugin suggestions
4. **When connecting via Gateway** → IDE suggests configured plugins → User accepts → Plugins install

## Plugin Configuration

### Finding Plugin IDs

Plugin IDs can be found on the [JetBrains Marketplace](https://plugins.jetbrains.com/):

1. Navigate to the plugin page
2. Look for the plugin ID in the URL or plugin details
3. Common examples:
   - `org.jetbrains.plugins.github` - GitHub integration
   - `com.intellij.ml.llm` - AI Assistant
   - `Pythonid` - Python support for IntelliJ IDEA
   - `org.intellij.plugins.markdown` - Markdown support

### Configuration Process

The module creates:
- **IDE config directories**: `~/.config/JetBrains/[IDE]2025.1/`
- **Plugin suggestions**: `enabled_plugins.txt` and `pluginAdvertiser.xml`
- **Project requirements**: `/workspace/.idea/externalDependencies.xml`

## Examples

### Basic Usage with Plugins

```tf
module "jetbrains_with_plugins" {
  source   = "registry.coder.com/saheli/jetbrains-plugins/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  folder   = "/workspace"
  default  = ["IU"]
  
  plugins = [
    "org.jetbrains.plugins.github"
  ]
}
```

### Multiple IDEs with Specific Plugins

```tf
module "jetbrains_full_stack" {
  source   = "registry.coder.com/saheli/jetbrains-plugins/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
  folder   = "/workspace"
  default  = ["IU", "PY", "WS"]
  
  plugins = [
    "org.jetbrains.plugins.github",           # GitHub (all IDEs)
    "com.intellij.ml.llm",                    # AI Assistant (all IDEs)
    "Pythonid",                               # Python (IntelliJ)
    "JavaScript",                             # JavaScript (IntelliJ)
    "org.intellij.plugins.markdown"           # Markdown (all IDEs)
  ]
}
```

## Module Parameters

This module accepts all parameters from the base `coder/jetbrains` module, plus:

### New Plugin Parameter

- **`plugins`** (list(string), default: []): List of plugin IDs to pre-configure

### Base Module Parameters

- **`agent_id`** (string, required): Coder agent ID
- **`folder`** (string, required): Project folder path
- **`default`** (set(string), default: []): Pre-selected IDEs or empty for user choice
- **`options`** (set(string)): Available IDE choices
- **`major_version`** (string): IDE version (e.g., "2025.1" or "latest")
- **`channel`** (string): Release channel ("release" or "eap")

## Supported IDEs

All JetBrains IDEs with remote development support:
- CLion (`CL`)
- GoLand (`GO`) 
- IntelliJ IDEA Ultimate (`IU`)
- PhpStorm (`PS`)
- PyCharm Professional (`PY`)
- Rider (`RD`)
- RubyMine (`RM`)
- RustRover (`RR`)
- WebStorm (`WS`)

## Contributing

This module addresses [GitHub Issue #208](https://github.com/coder/registry/issues/208) by providing plugin pre-configuration capabilities while following the namespace guidelines for community contributions.