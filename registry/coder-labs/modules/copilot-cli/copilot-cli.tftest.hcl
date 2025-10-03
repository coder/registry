run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = var.copilot_model == "claude-sonnet-4.5"
    error_message = "Default model should be 'claude-sonnet-4.5'"
  }

  assert {
    condition     = var.report_tasks == true
    error_message = "Task reporting should be enabled by default"
  }

  assert {
    condition     = var.resume_session == true
    error_message = "Session resumption should be enabled by default"
  }

  assert {
    condition     = var.allow_all_tools == false
    error_message = "allow_all_tools should be disabled by default"
  }

  assert {
    condition     = resource.coder_env.mcp_app_status_slug.name == "CODER_MCP_APP_STATUS_SLUG"
    error_message = "Status slug env var should be created"
  }

  assert {
    condition     = resource.coder_env.mcp_app_status_slug.value == "copilot-cli"
    error_message = "Status slug value should be 'copilot-cli'"
  }
}

run "github_token_creates_env_var" {
  command = plan

  variables {
    agent_id     = "test-agent"
    workdir      = "/home/coder"
    github_token = "test_github_token_abc123"
  }

  assert {
    condition     = length(resource.coder_env.github_token) == 1
    error_message = "github_token env var should be created when token is provided"
  }

  assert {
    condition     = resource.coder_env.github_token[0].name == "GITHUB_TOKEN"
    error_message = "github_token env var name should be 'GITHUB_TOKEN'"
  }

  assert {
    condition     = resource.coder_env.github_token[0].value == "test_github_token_abc123"
    error_message = "github_token env var value should match input"
  }
}

run "github_token_not_created_when_empty" {
  command = plan

  variables {
    agent_id     = "test-agent"
    workdir      = "/home/coder"
    github_token = ""
  }

  assert {
    condition     = length(resource.coder_env.github_token) == 0
    error_message = "github_token env var should not be created when empty"
  }
}

run "copilot_model_env_var_for_non_default" {
  command = plan

  variables {
    agent_id      = "test-agent"
    workdir       = "/home/coder"
    copilot_model = "claude-sonnet-4"
  }

  assert {
    condition     = length(resource.coder_env.copilot_model) == 1
    error_message = "copilot_model env var should be created for non-default model"
  }

  assert {
    condition     = resource.coder_env.copilot_model[0].name == "COPILOT_MODEL"
    error_message = "copilot_model env var name should be 'COPILOT_MODEL'"
  }

  assert {
    condition     = resource.coder_env.copilot_model[0].value == "claude-sonnet-4"
    error_message = "copilot_model env var value should match input"
  }
}

run "copilot_model_not_created_for_default" {
  command = plan

  variables {
    agent_id      = "test-agent"
    workdir       = "/home/coder"
    copilot_model = "claude-sonnet-4.5"
  }

  assert {
    condition     = length(resource.coder_env.copilot_model) == 0
    error_message = "copilot_model env var should not be created for default model"
  }
}

run "model_validation_accepts_valid_models" {
  command = plan

  variables {
    agent_id      = "test-agent"
    workdir       = "/home/coder"
    copilot_model = "gpt-5"
  }

  assert {
    condition     = contains(["claude-sonnet-4", "claude-sonnet-4.5", "gpt-5"], var.copilot_model)
    error_message = "Model should be one of the valid options"
  }
}

run "copilot_config_merges_with_trusted_directories" {
  command = plan

  variables {
    agent_id            = "test-agent"
    workdir             = "/home/coder/project"
    trusted_directories = ["/workspace", "/data"]
  }

  assert {
    condition     = length(local.final_copilot_config) > 0
    error_message = "final_copilot_config should be computed"
  }

  # Verify workdir is trimmed of trailing slash
  assert {
    condition     = local.workdir == "/home/coder/project"
    error_message = "workdir should be trimmed of trailing slash"
  }
}

run "custom_copilot_config_overrides_default" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
    copilot_config = jsonencode({
      banner = "always"
      theme  = "dark"
    })
  }

  assert {
    condition     = var.copilot_config != ""
    error_message = "Custom copilot config should be set"
  }

  assert {
    condition     = jsondecode(local.final_copilot_config).banner == "always"
    error_message = "Custom banner setting should be applied"
  }

  assert {
    condition     = jsondecode(local.final_copilot_config).theme == "dark"
    error_message = "Custom theme setting should be applied"
  }
}

run "trusted_directories_merged_with_custom_config" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project"
    copilot_config = jsonencode({
      banner          = "always"
      theme           = "dark"
      trusted_folders = ["/custom"]
    })
    trusted_directories = ["/workspace", "/data"]
  }

  assert {
    condition     = contains(jsondecode(local.final_copilot_config).trusted_folders, "/custom")
    error_message = "Custom trusted folder should be included"
  }

  assert {
    condition     = contains(jsondecode(local.final_copilot_config).trusted_folders, "/home/coder/project")
    error_message = "Workdir should be included in trusted folders"
  }

  assert {
    condition     = contains(jsondecode(local.final_copilot_config).trusted_folders, "/workspace")
    error_message = "trusted_directories should be merged into config"
  }

  assert {
    condition     = contains(jsondecode(local.final_copilot_config).trusted_folders, "/data")
    error_message = "All trusted_directories should be merged into config"
  }
}

run "app_slug_is_consistent" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = local.app_slug == "copilot-cli"
    error_message = "app_slug should be 'copilot-cli'"
  }

  assert {
    condition     = local.module_dir_name == ".copilot-module"
    error_message = "module_dir_name should be '.copilot-module'"
  }
}
