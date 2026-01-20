---
display_name: "Docker Container"
description: "Develop in a container on a Docker host"
icon: "../../../../.icons/invalid.svg"
verified: true
tags: ["docker", "container"]
supported_os: ["linux", "macos"]
---

# Wrong Path

This should fail validation.

```tf
module "test" {
  source   = "registry.coder.com/coder/test/coder"
  version  = "1.0.0"
  agent_id = coder_agent.main.id
}
```
