terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of the Coder agent for the workspace that will consume PADE."
}

variable "pade_version" {
  type        = string
  description = "PADE release version to install."
  default     = "v0.4.1"

  validation {
    condition     = can(regex("^v?[0-9]+\\.[0-9]+\\.[0-9]+$", var.pade_version))
    error_message = "pade_version must be a semantic version such as v0.4.1 or 0.4.0."
  }
}

variable "broker_endpoint" {
  type        = string
  description = "The HTTPS endpoint of an existing PADE broker."

  validation {
    condition     = can(regex("^https://", var.broker_endpoint))
    error_message = "broker_endpoint must be an HTTPS URL."
  }
}

variable "broker_audience" {
  type        = string
  description = "OIDC audience requested for the PADE broker. Defaults to broker_endpoint."
  default     = null
  nullable    = true

  validation {
    condition     = var.broker_audience == null ? true : trimspace(var.broker_audience) != ""
    error_message = "broker_audience must be null or a non-empty string."
  }
}

variable "broker_identity" {
  type        = string
  description = "PADE workload identity adapter. The GCE path is the integration proven by Experiment 001."
  default     = "gce"

  validation {
    condition     = contains(["gce", "cursor"], var.broker_identity)
    error_message = "broker_identity must be one of the identity adapters supported by the current PADE Consumer: gce or cursor."
  }
}

variable "broker_capabilities" {
  type        = set(string)
  description = "Static capability bindings managed by this module. Leave empty when a trusted downstream integration will populate the bindings after installation."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for capability in var.broker_capabilities : trimspace(capability) != ""])
    error_message = "broker_capabilities must contain only non-empty capability names."
  }
}

locals {
  pade_version    = startswith(var.pade_version, "v") ? var.pade_version : "v${var.pade_version}"
  broker_audience = var.broker_audience != null ? var.broker_audience : var.broker_endpoint

  broker_binding = {
    provider = "broker"
    broker = {
      endpoint = var.broker_endpoint
      audience = local.broker_audience
      identity = var.broker_identity
    }
  }

  bindings = yamlencode({
    version = "0.1"
    capabilities = {
      for capability in var.broker_capabilities : capability => local.broker_binding
    }
  })
}

locals {
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    PADE_VERSION     = local.pade_version
    BINDINGS_B64     = base64encode(local.bindings)
    DYNAMIC_BINDINGS = length(var.broker_capabilities) == 0 ? "1" : "0"
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.2"

  agent_id            = var.agent_id
  module_directory    = "$HOME/.coder-modules/after-certainty/pade"
  display_name_prefix = "PADE"
  install_script      = local.install_script
}

output "broker_binding" {
  description = "Non-secret broker binding template for trusted downstream integrations to use when constructing the bindings file. This is configuration, not an authorization grant."
  value       = local.broker_binding
}

output "bindings_path" {
  description = "Workspace-local path written by this module. Set PADE_BINDINGS to this path or pass it with --bindings."
  value       = "~/.config/pade/coder-bindings.yaml"
}

output "pade_version" {
  description = "PADE version installed by the module."
  value       = local.pade_version
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order."
  value       = module.coder_utils.scripts
}
