run "required_variables" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    workdir          = "/home/coder"
    external_auth_id = "github"
  }

  assert {
    condition     = var.agent_id == "test-agent-id"
    error_message = "Agent ID should be set correctly"
  }

  assert {
    condition     = var.workdir == "/home/coder"
    error_message = "Workdir should be set correctly"
  }

  assert {
    condition     = var.external_auth_id == "github"
    error_message = "External auth ID should be set correctly"
  }
}

run "minimal_config" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    workdir          = "/home/coder"
    external_auth_id = "github"
  }

  assert {
    condition     = resource.coder_env.mcp_app_status_slug.name == "CODER_MCP_APP_STATUS_SLUG"
    error_message = "Status slug environment variable not configured correctly"
  }

  assert {
    condition     = resource.coder_env.mcp_app_status_slug.value == "copilot-cli"
    error_message = "Status slug value should be 'copilot-cli'"
  }

  assert {
    condition     = var.copilot_model == "claude-sonnet-4"
    error_message = "Default model should be 'claude-sonnet-4'"
  }

  assert {
    condition     = var.report_tasks == true
    error_message = "Task reporting should be enabled by default"
  }
}

run "custom_model" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    workdir          = "/home/coder"
    external_auth_id = "github"
    copilot_model    = "claude-sonnet-4.5"
  }

  assert {
    condition     = var.copilot_model == "claude-sonnet-4.5"
    error_message = "Custom model should be set correctly"
  }
}

run "custom_copilot_config" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    workdir          = "/home/coder"
    external_auth_id = "github"
    copilot_config = jsonencode({
      banner = "auto"
      theme  = "light"
      trusted_folders = ["/home/coder", "/workspace"]
    })
  }

  assert {
    condition     = var.copilot_config != ""
    error_message = "Custom copilot config should be provided"
  }
}

run "trusted_directories" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    workdir             = "/home/coder"
    external_auth_id    = "github"
    trusted_directories = ["/workspace", "/projects"]
  }

  assert {
    condition     = length(var.trusted_directories) == 2
    error_message = "Trusted directories should be set correctly"
  }
}

run "mcp_config" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    workdir          = "/home/coder"
    external_auth_id = "github"
    mcp_config = jsonencode({
      mcpServers = {
        custom = {
          command = "custom-server"
          args    = ["--config", "custom.json"]
        }
      }
    })
  }

  assert {
    condition     = var.mcp_config != ""
    error_message = "Custom MCP config should be provided"
  }
}

run "tool_permissions" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    workdir          = "/home/coder"
    external_auth_id = "github"
    allow_tools      = ["fs_read", "fs_write"]
    deny_tools       = ["execute_bash"]
  }

  assert {
    condition     = length(var.allow_tools) == 2
    error_message = "Allow tools should be set correctly"
  }

  assert {
    condition     = length(var.deny_tools) == 1
    error_message = "Deny tools should be set correctly"
  }
}

run "ui_customization" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    workdir          = "/home/coder"
    external_auth_id = "github"
    order            = 5
    group            = "AI Tools"
    icon             = "/icon/custom-copilot.svg"
  }

  assert {
    condition     = var.order == 5
    error_message = "Order should be set correctly"
  }

  assert {
    condition     = var.group == "AI Tools"
    error_message = "Group should be set correctly"
  }

  assert {
    condition     = var.icon == "/icon/custom-copilot.svg"
    error_message = "Icon should be set correctly"
  }
}

run "install_scripts" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    workdir             = "/home/coder"
    external_auth_id    = "github"
    pre_install_script  = "echo 'Pre-install setup'"
    post_install_script = "echo 'Post-install cleanup'"
  }

  assert {
    condition     = var.pre_install_script == "echo 'Pre-install setup'"
    error_message = "Pre-install script should be set correctly"
  }

  assert {
    condition     = var.post_install_script == "echo 'Post-install cleanup'"
    error_message = "Post-install script should be set correctly"
  }
}

run "model_validation" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    workdir          = "/home/coder"
    external_auth_id = "github"
    copilot_model    = "gpt-5"
  }

  assert {
    condition     = contains(["claude-sonnet-4", "claude-sonnet-4.5", "gpt-5"], var.copilot_model)
    error_message = "Model should be one of the valid options"
  }
}

run "task_reporting_disabled" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    workdir          = "/home/coder"
    external_auth_id = "github"
    report_tasks     = false
  }

  assert {
    condition     = var.report_tasks == false
    error_message = "Task reporting should be disabled when set to false"
  }

  assert {
    condition     = resource.coder_env.mcp_app_status_slug.name == "CODER_MCP_APP_STATUS_SLUG"
    error_message = "Status slug should still be configured even when task reporting is disabled"
  }
}