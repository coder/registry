---
display_name: JetBrains Gateway
description: Add a one-click button to launch JetBrains Gateway IDEs in the dashboard.
icon: ../../../../.icons/gateway.svg
verified: true
tags: [ide, jetbrains, parameter, gateway]
---

# JetBrains Gateway

This module adds a JetBrains Gateway Button to open any workspace with a single click.

JetBrains recommends a minimum of 4 CPU cores and 8GB of RAM.
Consult the [JetBrains documentation](https://www.jetbrains.com/help/idea/prerequisites.html#min_requirements) to confirm other system requirements.

```tf
module "jetbrains_gateway" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.3"
  agent_id       = coder_agent.example.id
  folder         = "/home/coder/example"
  jetbrains_ides = ["CL", "GO", "IU", "PY", "WS"]
  default        = "GO"
}
```

![JetBrains Gateway IDes list](../.images/jetbrains-gateway.png)

## Examples

### Add GoLand and WebStorm as options with the default set to GoLand

```tf
module "jetbrains_gateway" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.3"
  agent_id       = coder_agent.example.id
  folder         = "/home/coder/example"
  jetbrains_ides = ["GO", "WS"]
  default        = "GO"
}
```

### Embed the agent name in the Gateway URL

This can be used when support for connecting to multiple agents within one workspace is required.

To utilise this both `embed_agent_name` and `agent_name` must be populated on each instance of the module.
In addition each instance must have a unique `slug` and `ide_parameter_name` variable defined.

```tf
module "jetbrains_gateway" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder/jetbrains-gateway/coder"
  version            = "1.2.3"
  agent_id           = coder_agent.example.id
  folder             = "/home/coder/example"
  jetbrains_ides     = ["CL", "GO"]
  default            = "GO"
  embed_agent_name   = true
  agent_name         = "main"
  ide_parameter_name = "jetbrains_ide" # default variable value
  slug               = "gateway"       # default variable value
}

module "jetbrains_gateway_agent2" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder/jetbrains-gateway/coder"
  version            = "1.2.3"
  agent_id           = coder_agent.jetbrainsagent2.id
  folder             = "/home/coder/example"
  jetbrains_ides     = ["CL", "GO", "IU", "PY", "WS"]
  default            = "GO"
  embed_agent_name   = true
  agent_name         = "jetbrainsagent2"
  ide_parameter_name = "jetbrains_ide_agent2"
  slug               = "gateway-agent2"
}
```

### Use the latest version of each IDE

```tf
module "jetbrains_gateway" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.3"
  agent_id       = coder_agent.example.id
  folder         = "/home/coder/example"
  jetbrains_ides = ["IU", "PY"]
  default        = "IU"
  latest         = true
}
```

### Use fixed versions set by `jetbrains_ide_versions`

```tf
module "jetbrains_gateway" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.3"
  agent_id       = coder_agent.example.id
  folder         = "/home/coder/example"
  jetbrains_ides = ["IU", "PY"]
  default        = "IU"
  latest         = false
  jetbrains_ide_versions = {
    "IU" = {
      build_number = "243.21565.193"
      version      = "2024.3"
    }
    "PY" = {
      build_number = "243.21565.199"
      version      = "2024.3"
    }
  }
}
```

### Use the latest EAP version

```tf
module "jetbrains_gateway" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.3"
  agent_id       = coder_agent.example.id
  folder         = "/home/coder/example"
  jetbrains_ides = ["GO", "WS"]
  default        = "GO"
  latest         = true
  channel        = "eap"
}
```

### Custom base link

Due to the highest priority of the `ide_download_link` parameter in the `(jetbrains-gateway://...` within IDEA, the pre-configured download address will be overridden when using [IDEA's offline mode](https://www.jetbrains.com/help/idea/fully-offline-mode.html). Therefore, it is necessary to configure the `download_base_link` parameter for the `jetbrains_gateway` module to change the value of `ide_download_link`.

```tf
module "jetbrains_gateway" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/coder/jetbrains-gateway/coder"
  version            = "1.2.3"
  agent_id           = coder_agent.example.id
  folder             = "/home/coder/example"
  jetbrains_ides     = ["GO", "WS"]
  releases_base_link = "https://releases.internal.site/"
  download_base_link = "https://download.internal.site/"
  default            = "GO"
}
```

## Supported IDEs

This module and JetBrains Gateway support the following JetBrains IDEs:

- [GoLand (`GO`)](https://www.jetbrains.com/go/)
- [WebStorm (`WS`)](https://www.jetbrains.com/webstorm/)
- [IntelliJ IDEA Ultimate (`IU`)](https://www.jetbrains.com/idea/)
- [PyCharm Professional (`PY`)](https://www.jetbrains.com/pycharm/)
- [PhpStorm (`PS`)](https://www.jetbrains.com/phpstorm/)
- [CLion (`CL`)](https://www.jetbrains.com/clion/)
- [RubyMine (`RM`)](https://www.jetbrains.com/ruby/)
- [Rider (`RD`)](https://www.jetbrains.com/rider/)
- [RustRover (`RR`)](https://www.jetbrains.com/rust/)
