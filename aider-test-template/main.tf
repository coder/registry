terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0"
    }
  }
}

provider "docker" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# This variable will prompt you for your API key when you create the workspace.
variable "api_key" {
  description = "API Key for your AI provider (e.g., OpenAI)."
  sensitive   = true
  default     = ""
}

# This parameter is required by the agentapi module to accept the initial user prompt.
data "coder_parameter" "ai_prompt" {
  name        = "AI Prompt"
  description = "Write an initial prompt for Aider to work on."
  type        = "string"
  default     = ""
  mutable     = true
  ephemeral   = true
}


# Create a persistent volume for the home directory.
resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
}

# Create the Docker container for the workspace.
resource "docker_container" "workspace" {
  count      = data.coder_workspace.me.start_count
  image      = "codercom/enterprise-base:ubuntu"
  name       = "coder-${data.coder_workspace.me.id}"
  hostname   = data.coder_workspace.me.name
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
  }
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = data.coder_provisioner.me.arch
  # Set the AI provider's API key as an environment variable in the agent.
  # This is how the Aider module will access it.
  env = {
    OPENAI_API_KEY    = var.api_key
    AIDER_TASK_PROMPT = data.coder_parameter.ai_prompt.value
  }
}

# This is the most important part!
# It includes your local Aider module into this template.
module "aider" {
  source = "./aider" # Use the local copy of the module

  agent_id    = coder_agent.main.id
  ai_provider = "openai"
  ai_model    = "4o" # Aider's alias for gpt-4o
  ai_api_key  = var.api_key
}