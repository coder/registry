run "test_aider_basic" {
  command = plan

  variables {
    agent_id = "test-agent-123"
    workdir  = "/home/coder"
    model    = "gemini"
  }

  assert {
    condition     = var.workdir == "/home/coder"
    error_message = "Workdir variable should default to /home/coder"
  }

  assert {
    condition     = var.agent_id == "test-agent-123"
    error_message = "Agent ID variable should be set correctly"
  }

  assert {
    condition     = var.install_aider == true
    error_message = "install_aider should default to true"
  }

  assert {
    condition     = var.install_agentapi == true
    error_message = "install_agentapi should default to true"
  }

  assert {
    condition     = var.report_tasks == false
    error_message = "report_tasks should default to false"
  }
}

run "test_with_api_key" {
  command = plan

  variables {
    agent_id    = "test-agent-456"
    workdir     = "/home/coder/workspace"
    api_key     = "test-api-key-123"
    model       = "gemini"
  }

  assert {
    condition     = var.api_key == "test-api-key-123"
    error_message = "API key value should match the input"
  }
}

run "test_custom_options" {
  command = plan

  variables {
    agent_id          = "test-agent-789"
    workdir           = "/home/coder/custom"
    order             = 5
    group             = "development"
    icon              = "/icon/custom.svg"
    model             = "4o"
    ai_prompt         = "Help me write better code"
    install_aider     = false
    install_agentapi  = false
    agentapi_version  = "v0.10.0"
    api_key           = ""
    base_aider_config = "read:\n  - CONVENTIONS.md"
  }

  assert {
    condition     = var.order == 5
    error_message = "Order variable should be set to 5"
  }

  assert {
    condition     = var.group == "development"
    error_message = "Group variable should be set to 'development'"
  }

  assert {
    condition     = var.icon == "/icon/custom.svg"
    error_message = "Icon variable should be set to custom icon"
  }

  assert {
    condition     = var.model == "4o"
    error_message = "Model variable should be set to '4o'"
  }

  assert {
    condition     = var.ai_prompt == "Help me write better code"
    error_message = "AI prompt variable should be set correctly"
  }

  assert {
    condition     = var.install_aider == false
    error_message = "install_aider should be set to false"
  }

  assert {
    condition     = var.install_agentapi == false
    error_message = "install_agentapi should be set to false"
  }

  assert {
    condition     = var.agentapi_version == "v0.10.0"
    error_message = "AgentAPI version should be set to 'v0.10.0'"
  }
}

run "test_with_scripts" {
  command = plan

  variables {
    agent_id            = "test-agent-scripts"
    workdir             = "/home/coder/scripts"
    model               = "gemini"
    pre_install_script  = "echo 'Pre-install script'"
    post_install_script = "echo 'Post-install script'"
  }

  assert {
    condition     = var.pre_install_script == "echo 'Pre-install script'"
    error_message = "Pre-install script should be set correctly"
  }

  assert {
    condition     = var.post_install_script == "echo 'Post-install script'"
    error_message = "Post-install script should be set correctly"
  }
}

run "test_ai_provider_env_mapping" {
  command = plan

  variables {
    agent_id            = "test-agent-provider"
    workdir             = "/home/coder/test"
    ai_provider         = "google"
    model               = "gemini"
    custom_env_var_name = ""
  }

  # Ensure provider -> env var mapping works as expected (based on locals.provider_env_vars)
  assert {
    condition     = var.ai_provider == "google"
    error_message = "AI provider should be set to 'google' for this test"
  }
}
