---
display_name: "Wrong Path"
description: "Test module with wrong icon path format"
icon: "../../../../.icons/invalid.svg"
verified: false
tags: ["test"]
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
