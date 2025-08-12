---
display_name: RStudio Server
description: A module that deploys Rocker Project distribution of RStudio Server in your Coder template.
icon: ../../../../.icons/rstudio.svg
verified: true
tags: [rstudio, ide, web]
---

# RStudio Server

A module that deploys Rocker Project distribution of RStudio Server in your Coder template.

![RStudio Server](../../.images/rstudio.png)

```tf
module "rstudio-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/rstudio-server/coder"
  version  = "0.9.0"
  agent_id = coder_agent.example.id
}
```
