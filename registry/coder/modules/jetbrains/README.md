---
display_name: JetBrains IDEs
description: Add a one-click button to launch JetBrains IDEs from the Coder dashboard.
icon: ../.icons/jetbrains.svg
maintainer_github: coder
partner_github: jetbrains
verified: true
tags: [ide, jetbrains, parameter]
---

# JetBrains IDEs

This module adds a JetBrains IDE Button to open any workspace with a single click.

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/example"
  default  = "GO"
}
```

> [!WARNING]
> JetBrains recommends a minimum of 4 CPU cores and 8GB of RAM.
> Consult the [JetBrains documentation](https://www.jetbrains.com/help/idea/prerequisites.html#min_requirements) to confirm other system requirements.

![JetBrains IDEs list](../.images/jetbrains-gateway.png)

## Examples

### Use the latest version of each IDE

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/example"
  options  = ["IU", "PY"]
  default  = ["IU"]
  latest   = true
}
```

### Use the latest EAP version

```tf
module "jetbrains" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/jetbrains/coder"
  version  = "1.0.0"
  agent_id = coder_agent.example.id
  folder   = "/home/coder/example"
  options  = ["GO", "WS"]
  default  = ["GO"]
  latest   = true
  channel  = "eap"
}
```

### Custom base link

Due to the highest priority of the `ide_download_link` parameter in the `(jetbrains-gateway://...` within IDEA, the pre-configured download address will be overridden when using [IDEA's offline mode](https://www.jetbrains.com/help/idea/fully-offline-mode.html). Therefore, it is necessary to configure the `download_base_link` parameter for the `jetbrains_gateway` module to change the value of `ide_download_link`.

```tf
module "jetbrains_gateway" {
  count              = data.coder_workspace.me.start_count
  source             = "registry.coder.com/modules/jetbrains-gateway/coder"
  version            = "1.0.0"
  agent_id           = coder_agent.example.id
  folder             = "/home/coder/example"
  options            = ["GO", "WS"]
  releases_base_link = "https://releases.internal.site/"
  download_base_link = "https://download.internal.site/"
  default            = ["GO"]
}
```

## Supported IDEs

JetBrains supports remote development for the following IDEs:

- [GoLand (`GO`)](https://www.jetbrains.com/go/)
- [WebStorm (`WS`)](https://www.jetbrains.com/webstorm/)
- [IntelliJ IDEA Ultimate (`IU`)](https://www.jetbrains.com/idea/)
- [PyCharm Professional (`PY`)](https://www.jetbrains.com/pycharm/)
- [PhpStorm (`PS`)](https://www.jetbrains.com/phpstorm/)
- [CLion (`CL`)](https://www.jetbrains.com/clion/)
- [RubyMine (`RM`)](https://www.jetbrains.com/ruby/)
- [Rider (`RD`)](https://www.jetbrains.com/rider/)
- [RustRover (`RR`)](https://www.jetbrains.com/rust/)
