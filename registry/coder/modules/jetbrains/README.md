---
display_name: JetBrains Toolbox
description: Add JetBrains IDE integrations to your Coder workspaces with configurable options.
icon: ../../../../.icons/jetbrains.svg
verified: true
tags: [ide, jetbrains, parameter]
---

# JetBrains IDEs

This module adds JetBrains IDE buttons to launch IDEs directly from the dashboard by integrating with the JetBrains Toolbox.

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
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
  version  = "1.3.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
  default  = ["PY", "IU"] # Pre-configure GoLand and IntelliJ IDEA
}
```

### User Choice with Limited Options

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
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
  version       = "1.3.0"
  agent_id      = coder_agent.main.id
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
  version  = "1.3.0"
  agent_id = coder_agent.main.id
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
  version  = "1.3.0"
  agent_id = coder_agent.main.id
  folder   = "/workspace/project"

  default = ["PY"] # Only PyCharm

  # Specific version for consistency
  major_version = "2025.1"
  channel       = "release"
}
```

### Custom Tooltip

Add helpful tooltip text that appears when users hover over the IDE app buttons:

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
  default  = ["IU", "PY"]
  tooltip  = "You need to install [JetBrains Toolbox App](https://www.jetbrains.com/toolbox-app/) to use this button."
}
```

### Pre-install Plugins

Pre-install JetBrains plugins to ensure your team has the required tools ready when they open the IDE:

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/project"
  default  = ["IU", "GO"]

  # Pre-install common plugins
  plugins = [
    "org.jetbrains.plugins.github",      # GitHub integration
    "com.intellij.plugins.vscodekeymap", # VS Code keymap
    "String Manipulation",               # String manipulation tools
  ]
}
```

> [!NOTE]
> Plugin IDs can be found on the [JetBrains Marketplace](https://plugins.jetbrains.com). Go to any plugin's page and look under "Additional Information" for the Plugin ID.

#### How Plugin Pre-installation Works

1. **Project-level configuration**: Creates `.idea/externalDependencies.xml` in your project folder. When you open the project in your IDE, you'll be prompted to install any missing plugins.

2. **Background installation**: A background process monitors for IDE installation and automatically installs plugins when the IDE becomes available.

#### Popular Plugin IDs

| Plugin           | ID                                  |
| ---------------- | ----------------------------------- |
| GitHub           | `org.jetbrains.plugins.github`      |
| GitLab           | `org.jetbrains.plugins.gitlab`      |
| Docker           | `Docker`                            |
| Kubernetes       | `com.intellij.kubernetes`           |
| VS Code Keymap   | `com.intellij.plugins.vscodekeymap` |
| Rainbow Brackets | `izhangzhihao.rainbow.brackets`     |
| SonarLint        | `org.sonarlint.idea`                |
| Copilot          | `com.github.copilot`                |

### Accessing the IDE Metadata

You can now reference the output `ide_metadata` as a map.

```tf
# Add metadata to the container showing the installed IDEs and their build versions.
resource "coder_metadata" "container_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = one(docker_container.workspace).id

  dynamic "item" {
    for_each = length(module.jetbrains) > 0 ? one(module.jetbrains).ide_metadata : {}
    content {
      key   = item.value.build
      value = "${item.value.name} [${item.key}]"
    }
  }
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
