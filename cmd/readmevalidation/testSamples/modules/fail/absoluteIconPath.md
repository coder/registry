---
display_name: "Goose"
description: "Run the Goose agent in your workspace to generate code and perform tasks"
icon: "https://github.com/coder/registry/pull/599.svg"
verified: false
tags: ["ai", "agent"]
---

# Goose

Run the [Goose](https://block.github.io/goose/) agent in your workspace to generate code and perform tasks.

```tf
module "goose" {
  source        = "registry.coder.com/coder/goose/coder"
  version       = "1.0.31"
  agent_id      = coder_agent.main.id
  folder        = "/home/coder"
  install_goose = true
  goose_version = "v1.0.16"
}
```