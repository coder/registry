# Test template for Parsec module
# This shows how to use the Parsec module in a Coder workspace template

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Example agent (you would replace this with your actual agent)
resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux" # or "windows"
}

# Use the Parsec module
module "parsec" {
  count    = data.coder_workspace.me.start_count
  source   = "./modules/parsec"
  agent_id = coder_agent.main.id
  os       = "linux" # or "windows"
  port     = 8000
  subdomain = true
} 