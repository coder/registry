---
display_name: Jupyter Notebook
description: A module that adds Jupyter Notebook in your Coder template.
icon: ../../../../.icons/jupyter.svg
verified: true
tags: [jupyter, ide, web]
---

# Jupyter Notebook

A module that adds Jupyter Notebook in your Coder template.

![Jupyter Notebook](../../.images/jupyter-notebook.png)

```tf
module "jupyter-notebook" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jupyter-notebook/coder"
  version  = "1.2.0"
  agent_id = coder_agent.example.id
}
```
