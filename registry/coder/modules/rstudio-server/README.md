---
display_name: RStudio Server
description: Deploy the Rocker Project distribution of RStudio Server in your Coder workspace.
icon: ../../../../.icons/rstudio.svg
verified: true
tags: [rstudio, ide, web]
---

# RStudio Server

Deploy the Rocker Project distribution of RStudio Server in your Coder workspace.

![RStudio Server](../../.images/rstudio-server.png)

```tf
module "rstudio-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/rstudio-server/coder"
  version  = "0.9.0"
  agent_id = coder_agent.example.id
}
```
