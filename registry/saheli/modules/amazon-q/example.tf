# Example usage of the Amazon Q module with AgentAPI integration
# This shows how to use the saheli/amazon-q module in your Coder template

terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

# Required variables for AWS authentication
variable "aws_access_key_id" {
  type        = string
  description = "AWS Access Key ID"
  sensitive   = true
}

variable "aws_secret_access_key" {
  type        = string
  description = "AWS Secret Access Key"
  sensitive   = true
}

# Template parameters
data "coder_parameter" "ai_prompt" {
  name        = "AI Prompt"
  type        = "string"
  description = "Task for the AI agent to complete"
  default     = ""
  mutable     = true
}

# Workspace and owner data
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Amazon Q module with AgentAPI integration
module "amazon-q" {
  source = "registry.coder.com/saheli/amazon-q/coder"
  # version = "1.0.0"  # Use when published to registry
  
  agent_id              = coder_agent.main.id
  folder                = "/home/coder/project"
  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
  aws_region            = "us-east-1"
  aws_profile           = "default"
  
  # Task reporting and prompt configuration
  system_prompt = <<-EOT
    You are Amazon Q, an AI coding assistant integrated with Coder Tasks.
    
    YOU MUST REPORT ALL TASKS TO CODER.
    When reporting tasks, follow these instructions:
    - Report status immediately after receiving any user message
    - Be granular - report each step of multi-step tasks
    - Use "working" for active processing, "complete" for finished tasks
    - Keep task summaries under 160 characters
    
    Focus on writing clean, maintainable code and following best practices.
  EOT
  
  task_prompt = data.coder_parameter.ai_prompt.value
  
  # Optional: Use Aider instead of Amazon Q
  # use_aider = true
  
  # Optional: Enable task reporting (default: true)
  # experiment_report_tasks = true
}

# Coder agent
resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"
  
  startup_script = <<-EOT
    set -e
    
    # Create project directory
    mkdir -p /home/coder/project
    
    # Show welcome message
    echo "Amazon Q + AgentAPI workspace is ready!"
    echo "- Click 'Amazon Q' for web interface"
    echo "- Click 'Amazon Q CLI' for command line access"
  EOT
}

# Docker container (example infrastructure)
resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = "codercom/code-server:latest"
  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  
  hostname = data.coder_workspace.me.name
  
  entrypoint = ["sh", "-c", coder_agent.main.init_script]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
}