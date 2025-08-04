terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    # Add your infrastructure provider here
    # docker = {
    #   source = "kreuzwerker/docker"
    # }
  }
}

# Coder data sources
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Coder agent configuration
resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    #!/bin/bash
    # Add startup commands here
    echo "Starting workspace..."
  EOT

  # Metadata for resource monitoring
  metadata {
    key          = "cpu"
    display_name = "CPU Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat cpu"
  }
  metadata {
    key          = "memory"
    display_name = "Memory Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat mem"
  }
  metadata {
    key          = "disk"
    display_name = "Disk Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat disk"
  }
}

# Registry modules for IDEs and tools
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  order    = 1
}

module "git-config" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
}

# Your infrastructure resources
# Example: Docker container
# resource "docker_container" "workspace" {
#   count = data.coder_workspace.me.start_count
#   name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
#   image = "codercom/enterprise-base:ubuntu"
#   # ... additional configuration
# }

# Workspace metadata
resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = coder_agent.main.id

  item {
    key   = "platform"
    value = "PLATFORM_NAME"
  }
}
