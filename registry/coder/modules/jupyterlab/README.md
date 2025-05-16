---
display_name: JupyterLab
description: A module that adds JupyterLab in your Coder template.
icon: ../../../../.icons/jupyter.svg
maintainer_github: coder
verified: true
tags: [jupyter, helper, ide, web]
---

# JupyterLab

A module that adds JupyterLab in your Coder template.

![JupyterLab](../../.images/jupyterlab.png)

```tf
module "jupyterlab" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jupyterlab/coder"
  version  = "1.0.31"
  agent_id = coder_agent.example.id
}
```
