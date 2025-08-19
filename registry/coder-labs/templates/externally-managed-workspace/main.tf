terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

data "coder_workspace" "me" {}

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"
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