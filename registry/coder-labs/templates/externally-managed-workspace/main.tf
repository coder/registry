terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.10"
    }
  }
}

data "coder_parameter" "agent_config" {
  name         = "agent_config"
  display_name = "Agent Configuration"
  description  = "Select the operating system and architecture combination for the agent"
  type         = "string"
  default      = "linux-amd64"

  option {
    name  = "Linux AMD64"
    value = "linux-amd64"
  }
  option {
    name  = "Linux ARM64"
    value = "linux-arm64"
  }
  option {
    name  = "Linux ARMv7"
    value = "linux-armv7"
  }
  option {
    name  = "Windows AMD64"
    value = "windows-amd64"
  }
  option {
    name  = "Windows ARM64"
    value = "windows-arm64"
  }
  option {
    name  = "macOS AMD64"
    value = "darwin-amd64"
  }
  option {
    name  = "macOS ARM64 (Apple Silicon)"
    value = "darwin-arm64"
  }
}

data "coder_workspace" "me" {}

locals {
  agent_config = split("-", data.coder_parameter.agent_config.value)
  agent_os     = local.agent_config[0]
  agent_arch   = local.agent_config[1]
}

resource "coder_agent" "main" {
  arch = local.agent_arch
  os   = local.agent_os
}

resource "coder_external_agent" "main" {
  agent_id = coder_agent.main.id
}

# Adds code-server
# See all available modules at https://registry.coder.com/modules
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/code-server/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = "~> 1.0"

  agent_id = coder_agent.main.id
}