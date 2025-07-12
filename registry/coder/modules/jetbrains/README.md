---
display_name: JetBrains Toolbox
description: Add JetBrains IDE integrations to your Coder workspaces with configurable options.
icon: ../../../../.icons/jetbrains.svg
maintainer_github: coder
verified: true
tags: [ide, jetbrains, parameter]
---

# JetBrains IDEs

This module adds JetBrains IDE buttons to launch IDEs directly from the dashboard by integrating with the JetBrains Toolbox.

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

![JetBrains IDEs list](../../.images/jetbrains-dropdown.png)

> [!IMPORTANT]
> This module requires Coder version 2.24+ and [JetBrains Toolbox](https://www.jetbrains.com/toolbox-app/) version 2.7 or higher.

> [!WARNING]
> JetBrains recommends a minimum of 4 CPU cores and 8GB of RAM.
> Consult the [JetBrains documentation](https://www.jetbrains.com/help/idea/prerequisites.html#min_requirements) to confirm other system requirements.

## Examples

### Pre-configured Mode (Direct App Creation)

When `default` contains IDE codes, those IDEs are created directly without user selection:

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
  default  = ["PY", "IU"] # Pre-configure GoLand and IntelliJ IDEA
}
```

### User Choice with Limited Options

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
  # Show parameter with limited options
  options = ["IU", "PY"] # Only these IDEs are available for selection
}
```

### Early Access Preview (EAP) Versions

```tf
module "jetbrains" {
  count         = data.coder_workspace.me.start_count
  source        = "registry.coder.com/coder/jetbrains/coder"
  version       = "1.0.0"
  agent_id      = coder_agent.example.id
  folder        = "/home/coder/project"
  default       = ["IU", "PY"]
  channel       = "eap"    # Use Early Access Preview versions
  major_version = "2025.2" # Specific major version
}
```

### Custom IDE Configuration

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/workspace/project"

  # Custom IDE metadata (display names and icons)
  ide_config = {
    "IU" = {
      name  = "IntelliJ IDEA"
      icon  = "/custom/icons/intellij.svg"
      build = "251.26927.53"
    }
    "PY" = {
      name  = "PyCharm"
      icon  = "/custom/icons/pycharm.svg"
      build = "251.23774.211"
    }
  }
}
```

### Single IDE for Specific Use Case

```tf
module "jetbrains_pycharm" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/workspace/project"

  default = ["PY"] # Only PyCharm

  # Specific version for consistency
  major_version = "2025.1"
  channel       = "release"
}
```

### Pre-installing JetBrains Plugins

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
  default  = ["IU", "PY"]

  # Pre-install plugins for all selected IDEs
  plugins = [
    "org.jetbrains.plugins.github",           # GitHub plugin
    "com.intellij.ml.llm",                    # AI Assistant
    "com.jetbrains.plugins.remotesdk",        # Remote Development
    "Pythonid",                               # Python support (for IntelliJ)
    "org.intellij.plugins.markdown"           # Markdown support
  ]
}
```

## Behavior

### Parameter vs Direct Apps

- **`default = []` (empty)**: Creates a `coder_parameter` allowing users to select IDEs from `options`
- **`default` with values**: Skips parameter and directly creates `coder_app` resources for the specified IDEs

### Version Resolution

- Build numbers are fetched from the JetBrains API for the latest compatible versions when internet access is available
- If the API is unreachable (air-gapped environments), the module automatically falls back to build numbers from `ide_config`
- `major_version` and `channel` control which API endpoint is queried (when API access is available)

## Supported IDEs

All JetBrains IDEs with remote development capabilities:

- [CLion (`CL`)](https://www.jetbrains.com/clion/)
- [GoLand (`GO`)](https://www.jetbrains.com/go/)
- [IntelliJ IDEA Ultimate (`IU`)](https://www.jetbrains.com/idea/)
- [PhpStorm (`PS`)](https://www.jetbrains.com/phpstorm/)
- [PyCharm Professional (`PY`)](https://www.jetbrains.com/pycharm/)
- [Rider (`RD`)](https://www.jetbrains.com/rider/)
- [RubyMine (`RM`)](https://www.jetbrains.com/ruby/)
- [RustRover (`RR`)](https://www.jetbrains.com/rust/)
- [WebStorm (`WS`)](https://www.jetbrains.com/webstorm/)

## Plugin Configuration

The module supports pre-configuring JetBrains plugins for automatic installation when IDEs are first accessed via JetBrains Gateway. This works seamlessly with JetBrains' Remote Development architecture.

### How Plugin Configuration Works

1. When `plugins` parameter contains plugin IDs, a startup script creates IDE configuration files
2. The script runs when the workspace starts, setting up plugin suggestions and recommendations
3. When you connect via JetBrains Gateway, the IDE backend is automatically downloaded
4. The IDE detects the plugin configuration and prompts for installation
5. You can accept the suggestions to install all configured plugins at once

### Finding Plugin IDs

Plugin IDs can be found on the [JetBrains Marketplace](https://plugins.jetbrains.com/):

1. Navigate to the plugin page
2. Look for the plugin ID in the URL or on the plugin details page
3. Common plugin ID examples:
   - `org.jetbrains.plugins.github` - GitHub integration
   - `com.intellij.ml.llm` - AI Assistant
   - `Pythonid` - Python support for IntelliJ IDEA
   - `org.intellij.plugins.markdown` - Markdown support

### Demo-Ready Features

- ✅ **Works with existing JetBrains Gateway workflow** - No need to pre-install IDEs
- ✅ **Creates project-level plugin suggestions** - Visible in `.idea/externalDependencies.xml`
- ✅ **Sets up IDE configuration files** - Ready for when IDE backend downloads
- ✅ **Visual feedback** - Script shows configuration progress in workspace logs
- ✅ **Easy to demonstrate** - Connect via Gateway → IDE suggests plugins → Accept → Done!

### Important Notes

- Works with JetBrains Gateway's automatic IDE backend downloading
- Plugin suggestions appear when opening projects in the configured IDEs
- No manual IDE installation required on the workspace server
- Compatible with all JetBrains IDEs that support Remote Development
- Configuration persists across workspace restarts
