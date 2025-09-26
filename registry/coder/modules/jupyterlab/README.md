---
display_name: JupyterLab
description: A module that adds JupyterLab in your Coder template.
icon: ../../../../.icons/jupyter.svg
verified: true
tags: [jupyter, ide, web]
---

# JupyterLab

A module that adds JupyterLab in your Coder template.

![JupyterLab](../../.images/jupyterlab.png)

```tf
module "jupyterlab" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jupyterlab/coder"
  version  = "1.2.0"
  agent_id = coder_agent.example.id
}
```

## Configuration

JupyterLab is automatically configured to work with Coder's iframe embedding. For advanced configuration, you can use the `config` parameter to provide additional JupyterLab server settings according to the [JupyterLab configuration documentation](https://jupyter-server.readthedocs.io/en/latest/users/configuration.html).

```tf
module "jupyterlab" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jupyterlab/coder"
  version  = "1.2.0"
  agent_id = coder_agent.example.id
  config = {
    ServerApp = {
      # Required for Coder Tasks iFrame embedding - do not remove
      tornado_settings = {
        headers = {
          "Content-Security-Policy" = "frame-ancestors 'self' ${data.coder_workspace.me.access_url}"
        }
      }
      # Your additional configuration here
      root_dir = "/workspace/notebooks"
    }
  }
}
```
