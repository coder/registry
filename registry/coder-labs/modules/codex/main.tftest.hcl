run "test_codex_basic" {
  command = plan

  variables {
    agent_id       = "test-agent"
    workdir        = "/home/coder"
    openai_api_key = "test-key"
  }

  assert {
    condition     = var.agent_id == "test-agent"
    error_message = "Agent ID should be set correctly"
  }

  assert {
    condition     = var.workdir == "/home/coder"
    error_message = "Workdir should be set correctly"
  }

  assert {
    condition     = var.install_codex == true
    error_message = "install_codex should default to true"
  }

  assert {
    condition     = var.install_agentapi == true
    error_message = "install_agentapi should default to true"
  }

  assert {
    condition     = var.report_tasks == true
    error_message = "report_tasks should default to true"
  }

  assert {
    condition     = var.continue == true
    error_message = "continue should default to true"
  }
}

run "test_enable_state_persistence_default" {
  command = plan

  variables {
    agent_id       = "test-agent"
    workdir        = "/home/coder"
    openai_api_key = "test-key"
  }

  assert {
    condition     = var.enable_state_persistence == true
    error_message = "enable_state_persistence should default to true"
  }
}

run "test_disable_state_persistence" {
  command = plan

  variables {
    agent_id                 = "test-agent"
    workdir                  = "/home/coder"
    openai_api_key           = "test-key"
    enable_state_persistence = false
  }

  assert {
    condition     = var.enable_state_persistence == false
    error_message = "enable_state_persistence should be false when explicitly disabled"
  }
}

run "test_codex_with_aibridge" {
  command = plan

  variables {
    agent_id        = "test-agent"
    workdir         = "/home/coder"
    enable_aibridge = true
  }

  assert {
    condition     = var.enable_aibridge == true
    error_message = "enable_aibridge should be set to true"
  }
}

run "test_aibridge_disabled_with_api_key" {
  command = plan

  variables {
    agent_id        = "test-agent"
    workdir         = "/home/coder"
    openai_api_key  = "test-key"
    enable_aibridge = false
  }

  assert {
    condition     = var.enable_aibridge == false
    error_message = "enable_aibridge should be false"
  }

  assert {
    condition     = coder_env.openai_api_key.value == "test-key"
    error_message = "OpenAI API key should be set correctly"
  }
}

run "test_custom_options" {
  command = plan

  variables {
    agent_id             = "test-agent"
    workdir              = "/home/coder/project"
    openai_api_key       = "test-key"
    order                = 5
    group                = "ai-tools"
    icon                 = "/icon/custom.svg"
    web_app_display_name = "Custom Codex"
    cli_app              = true
    cli_app_display_name = "Codex Terminal"
    subdomain            = true
    report_tasks         = false
    continue             = false
    codex_model          = "gpt-4o"
    codex_version        = "0.1.0"
    agentapi_version     = "v0.12.0"
  }

  assert {
    condition     = var.order == 5
    error_message = "Order should be set to 5"
  }

  assert {
    condition     = var.group == "ai-tools"
    error_message = "Group should be set to 'ai-tools'"
  }

  assert {
    condition     = var.icon == "/icon/custom.svg"
    error_message = "Icon should be set to custom icon"
  }

  assert {
    condition     = var.cli_app == true
    error_message = "cli_app should be enabled"
  }

  assert {
    condition     = var.subdomain == true
    error_message = "subdomain should be enabled"
  }

  assert {
    condition     = var.report_tasks == false
    error_message = "report_tasks should be disabled"
  }

  assert {
    condition     = var.continue == false
    error_message = "continue should be disabled"
  }

  assert {
    condition     = var.codex_model == "gpt-4o"
    error_message = "codex_model should be set to 'gpt-4o'"
  }
}

run "test_default_agentapi_port" {
  command = plan

  variables {
    agent_id       = "test-agent"
    workdir        = "/home/coder"
    openai_api_key = "test-key"
  }

  assert {
    condition     = var.agentapi_port == 3284
    error_message = "agentapi_port should default to 3284"
  }
}

run "test_custom_agentapi_port" {
  command = plan

  variables {
    agent_id       = "test-agent"
    workdir        = "/home/coder"
    openai_api_key = "test-key"
    agentapi_port  = 3285
  }

  assert {
    condition     = var.agentapi_port == 3285
    error_message = "agentapi_port should be configurable"
  }
}

run "test_no_api_key_no_aibridge" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = var.openai_api_key == ""
    error_message = "openai_api_key should be empty when not provided"
  }

  assert {
    condition     = var.enable_aibridge == false
    error_message = "enable_aibridge should default to false"
  }
}
