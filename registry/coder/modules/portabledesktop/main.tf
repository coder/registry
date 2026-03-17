terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "install_dir" {
  type        = string
  description = "Optional directory to copy the binary into (e.g. /usr/local/bin). The binary is always stored in the agent's script data directory and available on PATH via CODER_SCRIPT_BIN_DIR."
  default     = null
}

variable "url" {
  type        = string
  description = "Custom download URL. Overrides the default GitHub latest release URL when set."
  default     = null
}

variable "sha256" {
  type        = string
  description = "SHA256 checksum. When set, the downloaded binary is verified against it."
  default     = null
}

locals {
  default_amd64_url = "https://github.com/coder/portabledesktop/releases/latest/download/portabledesktop-linux-x64"
  default_arm64_url = "https://github.com/coder/portabledesktop/releases/latest/download/portabledesktop-linux-arm64"

  using_custom_url = var.url != null

  amd64_url = local.using_custom_url ? var.url : local.default_amd64_url
  arm64_url = local.using_custom_url ? var.url : local.default_arm64_url

  # Empty string signals "skip verification" to the shell script.
  sha256      = var.sha256 != null ? var.sha256 : ""
  install_dir = var.install_dir != null ? var.install_dir : ""
}

resource "coder_script" "portabledesktop" {
  agent_id     = var.agent_id
  display_name = "Portable Desktop"
  icon         = "/icon/desktop.svg"
  script       = <<-EOT
    #!/bin/sh
    set -eu
    echo -n '${base64encode(file("${path.module}/run.sh"))}' | base64 -d > /tmp/portabledesktop-install.sh
    chmod +x /tmp/portabledesktop-install.sh
    ARG_AMD64_URL="$(echo -n '${base64encode(local.amd64_url)}' | base64 -d)" \
    ARG_ARM64_URL="$(echo -n '${base64encode(local.arm64_url)}' | base64 -d)" \
    ARG_SHA256="$(echo -n '${base64encode(local.sha256)}' | base64 -d)" \
    ARG_INSTALL_DIR="$(echo -n '${base64encode(local.install_dir)}' | base64 -d)" \
    /tmp/portabledesktop-install.sh
    EOT
  run_on_start = true
}
