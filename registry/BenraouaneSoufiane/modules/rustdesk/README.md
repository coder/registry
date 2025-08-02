---
display_name: Rustdesk
description: Create desktop environmetn & run rustdesk in your workspace
icon: ../../../../.icons/rustdesk.svg
verified: false
tags: [rustdesk, rdp, vm]
---

# RustDesk Coder Module

This is the basic Coder's rustdesk module that install minimal desktop environment (xfce) & launches the rustdesk within your workspace

---

## Features

- Installs RustDesk & launches it in GUI not with black screen
- Outputs the RustDesk ID and password
- Automatically launches RustDesk on workspace start
- Provides an external app link to the [RustDesk web client](https://rustdesk.com/web)

---

## Usage

### Prerequisites

- Coder v2.5 or higher
- A workspace agent compatible with Linux and `apt` package manager
- Root scope (to install desktop environment, rustdesk & execute rustdesk --password "somepassword", because rustdesk cli does not provide a way to get the password else setup in advance, the command rustdesk --password "somepassword" only for root users)


---

### Quickstart

1. Add the module to your [Coder Terraform workspace](https://registry.coder.com)
2. Include it in your `main.tf`:

```hcl
module "rustdesk" {
  source    = "registry.coder.com/BenraouaneSoufiane/rustdesk/BenraouaneSoufiane"
  agent_id  = var.agent_id
}
```
Also add this within resource "docker_container" "workspace":
 
```hcl
privileged = true
  user       = "root"
  network_mode = "host"
  ports {
  internal = 21115
  external = 21115
}
ports {
  internal = 21116
  external = 21116
}
ports {
  internal = 21118
  external = 21118
}
ports {
  internal = 21119
  external = 21119
}
```
