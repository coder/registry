terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# Mock agent for testing
resource "coder_agent" "test" {
  os   = "linux"
  arch = "amd64"
}

# Test basic functionality
module "auto_dev_server_basic" {
  source   = "../"
  agent_id = coder_agent.test.id
}

# Test with custom configuration
module "auto_dev_server_custom" {
  source              = "../"
  agent_id            = coder_agent.test.id
  project_dir         = "/workspace"
  enabled_frameworks  = ["nodejs", "django"]
  start_delay         = 45
  log_level          = "DEBUG"
  use_devcontainer   = false
  custom_commands    = {
    nodejs = "npm run dev"
    django = "python manage.py runserver 0.0.0.0:3000"
  }
}

# Test outputs
output "basic_log_file" {
  value = module.auto_dev_server_basic.log_file
}

output "custom_frameworks" {
  value = module.auto_dev_server_custom.enabled_frameworks
}
