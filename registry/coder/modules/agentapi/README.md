---
display_name: AgentAPI
description: Building block for modules that need to run an AgentAPI server
icon: ../../../../.icons/coder.svg
verified: true
tags: [internal, library]
---

# AgentAPI

> [!CAUTION]
> We do not recommend using this module directly. Instead, please consider using one of our [Tasks-compatible AI agent modules](https://registry.coder.com/modules?search=tag%3Atasks).

The AgentAPI module is a building block for modules that need to run an AgentAPI server. It is intended primarily for internal use by Coder to create modules compatible with Tasks.

```tf
module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.2.0"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Goose"
  cli_app_slug         = "goose-cli"
  cli_app_display_name = "Goose CLI"
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  enable_tasks         = var.enable_tasks # Set to false to disable AI tasks
  pre_install_script   = var.pre_install_script
  post_install_script  = var.post_install_script
  start_script         = local.start_script
  install_script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh

    ARG_PROVIDER='${var.goose_provider}' \
    ARG_MODEL='${var.goose_model}' \
    ARG_GOOSE_CONFIG="$(echo -n '${base64encode(local.combined_extensions)}' | base64 -d)" \
    ARG_INSTALL='${var.install_goose}' \
    ARG_GOOSE_VERSION='${var.goose_version}' \
    /tmp/install.sh
  EOT
}
```

## For module developers

For a complete example of how to use this module, see the [Goose module](https://github.com/coder/registry/blob/main/registry/coder/modules/goose/main.tf).
