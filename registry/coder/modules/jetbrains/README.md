---
display_name: JetBrains Toolbox
description: Add JetBrains IDE integrations to your Coder workspaces with configurable options.
icon: ../../../../.icons/jetbrains.svg
maintainer_github: coder
verified: true
tags: [ide, jetbrains, parameter]
---

# JetBrains IDEs

This module adds JetBrains IDE integrations to your Coder workspaces, allowing users to launch IDEs directly from the dashboard or pre-configure specific IDEs for immediate use.

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"
}
```

> [!NOTE]
> This module requires Coder version 2.24+ to use the `multi-select` form type.

> [!WARNING]
> JetBrains recommends a minimum of 4 CPU cores and 8GB of RAM.
> Consult the [JetBrains documentation](https://www.jetbrains.com/help/idea/prerequisites.html#min_requirements) to confirm other system requirements.

![JetBrains IDEs list](../.images/jetbrains-gateway.png)

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
  default  = ["GO", "IU"] # Pre-configure GoLand and IntelliJ IDEA
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
  options = ["GO", "PY", "WS"] # Only these IDEs are available for selection
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
  default       = ["GO", "RR"]
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
    "GO" = {
      name  = "GoLand"
      icon  = "/custom/icons/goland.svg"
      build = "251.25410.140"
    }
    "PY" = {
      name  = "PyCharm"
      icon  = "/custom/icons/pycharm.svg"
      build = "251.23774.211"
    }
    "WS" = {
      name  = "WebStorm"
      icon  = "/icon/webstorm.svg"
      build = "251.23774.210"
    }
  }
}
```

### Air-Gapped and Offline Environments

This module supports air-gapped environments through automatic fallback mechanisms:

#### Option 1: Self-hosted JetBrains API Mirror

For organizations with internal JetBrains API mirrors:

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"

  default = ["GO", "IU"]

  # Custom API endpoints
  releases_base_link = "https://jetbrains-api.internal.company.com"
  download_base_link = "https://jetbrains-downloads.internal.company.com"
}
```

#### Option 2: Fully Air-Gapped (No Internet Access)

The module automatically falls back to static build numbers from `ide_config` when the JetBrains API is unreachable:

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/project"

  default = ["GO", "IU"]

  # Update these build numbers as needed for your environment
  ide_config = {
    "GO" = {
      name  = "GoLand"
      icon  = "/icon/goland.svg"
      build = "251.26927.50" # Static build number used when API is unavailable
    }
    "IU" = {
      name  = "IntelliJ IDEA"
      icon  = "/icon/intellij.svg"
      build = "251.26927.53" # Static build number used when API is unavailable
    }
  }
}
```

**How it works:**

- The module first attempts to fetch the latest build numbers from the JetBrains API
- If the API is unreachable (network timeout, DNS failure, etc.), it automatically falls back to the build numbers specified in `ide_config`
- This ensures the module works in both connected and air-gapped environments without configuration changes

### Single IDE for Specific Use Case

```tf
module "jetbrains_goland" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/go/src/project"

  default = ["GO"] # Only GoLand

  # Specific version for consistency
  major_version = "2025.1"
  channel       = "release"
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

- [GoLand (`GO`)](https://www.jetbrains.com/go/)
- [WebStorm (`WS`)](https://www.jetbrains.com/webstorm/)
- [IntelliJ IDEA Ultimate (`IU`)](https://www.jetbrains.com/idea/)
- [PyCharm Professional (`PY`)](https://www.jetbrains.com/pycharm/)
- [PhpStorm (`PS`)](https://www.jetbrains.com/phpstorm/)
- [CLion (`CL`)](https://www.jetbrains.com/clion/)
- [RubyMine (`RM`)](https://www.jetbrains.com/ruby/)
- [Rider (`RD`)](https://www.jetbrains.com/rider/)
- [RustRover (`RR`)](https://www.jetbrains.com/rust/)
