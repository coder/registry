---
display_name: Personalize
description: Allow developers to customize their workspace on start
icon: ../../../../.icons/personalize.svg
verified: true
tags: [helper, personalize]
---

# Personalize

Run a script on workspace start that allows developers to run custom commands to personalize their workspace.

```tf
module "personalize" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/personalize/coder"
  version  = "1.0.31"
  agent_id = coder_agent.example.id
}
```
