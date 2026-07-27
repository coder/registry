terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The resource ID of a Coder agent."
}

variable "jetbrains_plugins" {
  type        = map(list(string))
  description = "Map of IDE product codes to plugin ID lists. Example: { IU = [\"com.foo\"], GO = [\"org.bar\"] }."
  default     = {}

  validation {
    condition = alltrue([
      for code in keys(var.jetbrains_plugins) : contains(
        ["CL", "GO", "IU", "PS", "PY", "RD", "RM", "RR", "WS"], code
      )
    ])
    error_message = "Keys must be valid JetBrains product codes: CL, GO, IU, PS, PY, RD, RM, RR, WS."
  }
}

locals {
  plugin_map_b64        = base64encode(jsonencode(var.jetbrains_plugins))
  plugin_install_script = file("${path.module}/scripts/install_plugins.sh")
}

resource "coder_script" "install_jetbrains_plugins" {
  count        = length(var.jetbrains_plugins) > 0 ? 1 : 0
  agent_id     = var.agent_id
  display_name = "Install JetBrains Plugins"
  run_on_start = true

  script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    CONFIG_DIR="$HOME/.config/JetBrains"

    mkdir -p "$CONFIG_DIR"
    echo -n "${local.plugin_map_b64}" | base64 -d > "$CONFIG_DIR/plugins.json"
    chmod 600 "$CONFIG_DIR/plugins.json"

    echo -n '${base64encode(local.plugin_install_script)}' | base64 -d > /tmp/install_plugins.sh
    chmod +x /tmp/install_plugins.sh

    /tmp/install_plugins.sh
  EOT
}
