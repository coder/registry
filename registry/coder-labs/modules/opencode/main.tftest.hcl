run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project"
  }

  assert {
    condition     = var.install_opencode == true
    error_message = "OpenCode installation should be enabled by default"
  }

  assert {
    condition     = var.install_agentapi == true
    error_message = "AgentAPI installation should be enabled by default"
  }

  assert {
    condition     = var.agentapi_version == "v0.10.0"
    error_message = "Default AgentAPI version should be 'v0.10.0'"
  }

  assert {
    condition     = var.opencode_version == "latest"
    error_message = "Default OpenCode version should be 'latest'"
  }

  assert {
    condition     = var.report_tasks == true
    error_message = "Task reporting should be enabled by default"
  }

  assert {
    condition     = var.cli_app == false
    error_message = "CLI app should be disabled by default"
  }

  assert {
    condition     = var.subdomain == false
    error_message = "Subdomain should be disabled by default"
  }

  assert {
    condition     = var.web_app_display_name == "OpenCode"
    error_message = "Default web app display name should be 'OpenCode'"
  }

  assert {
    condition     = var.cli_app_display_name == "OpenCode CLI"
    error_message = "Default CLI app display name should be 'OpenCode CLI'"
  }

  assert {
    condition     = local.app_slug == "opencode"
    error_message = "App slug should be 'opencode'"
  }

  assert {
    condition     = local.module_dir_name == ".opencode-module"
    error_message = "Module dir name should be '.opencode-module'"
  }

  assert {
    condition     = local.workdir == "/home/coder/project"
    error_message = "Workdir should be trimmed of trailing slash"
  }
}

run "workdir_trailing_slash_trimmed" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project/"
  }

  assert {
    condition     = local.workdir == "/home/coder/project"
    error_message = "Workdir should be trimmed of trailing slash"
  }
}

run "opencode_version_configuration" {
  command = plan

  variables {
    agent_id         = "test-agent"
    workdir          = "/home/coder/project"
    opencode_version = "v1.0.0"
  }

  assert {
    condition     = var.opencode_version == "v1.0.0"
    error_message = "OpenCode version should be set correctly"
  }
}

run "agentapi_version_configuration" {
  command = plan

  variables {
    agent_id         = "test-agent"
    workdir          = "/home/coder/project"
    agentapi_version = "v0.9.0"
  }

  assert {
    condition     = var.agentapi_version == "v0.9.0"
    error_message = "AgentAPI version should be set correctly"
  }
}

run "cli_app_configuration" {
  command = plan

  variables {
    agent_id             = "test-agent"
    workdir              = "/home/coder/project"
    cli_app              = true
    cli_app_display_name = "Custom OpenCode CLI"
  }

  assert {
    condition     = var.cli_app == true
    error_message = "CLI app should be enabled when specified"
  }

  assert {
    condition     = var.cli_app_display_name == "Custom OpenCode CLI"
    error_message = "Custom CLI app display name should be set"
  }
}

run "web_app_configuration" {
  command = plan

  variables {
    agent_id             = "test-agent"
    workdir              = "/home/coder/project"
    web_app_display_name = "Custom OpenCode Web"
    order                = 5
    group                = "AI Tools"
    icon                 = "/custom/icon.svg"
  }

  assert {
    condition     = var.web_app_display_name == "Custom OpenCode Web"
    error_message = "Custom web app display name should be set"
  }

  assert {
    condition     = var.order == 5
    error_message = "Custom order should be set"
  }

  assert {
    condition     = var.group == "AI Tools"
    error_message = "Custom group should be set"
  }

  assert {
    condition     = var.icon == "/custom/icon.svg"
    error_message = "Custom icon should be set"
  }
}

run "ai_configuration_variables" {
  command = plan

  variables {
    agent_id   = "test-agent"
    workdir    = "/home/coder/project"
    ai_prompt  = "This is a test prompt"
    model      = "gpt-4"
    agent      = "test-agent-name"
    session_id = "session-123"
  }

  assert {
    condition     = var.ai_prompt == "This is a test prompt"
    error_message = "AI prompt should be set correctly"
  }

  assert {
    condition     = var.model == "gpt-4"
    error_message = "Model should be set correctly"
  }

  assert {
    condition     = var.agent == "test-agent-name"
    error_message = "Agent should be set correctly"
  }

  assert {
    condition     = var.session_id == "session-123"
    error_message = "Session ID should be set correctly"
  }
}

run "auth_json_configuration" {
  command = plan

  variables {
    agent_id  = "test-agent"
    workdir   = "/home/coder/project"
    auth_json = "{\"token\": \"test-token\", \"user\": \"test-user\"}"
  }

  assert {
    condition     = var.auth_json != ""
    error_message = "Auth JSON should be set"
  }

  assert {
    condition     = can(jsondecode(var.auth_json))
    error_message = "Auth JSON should be valid JSON"
  }
}

run "mcp_configuration" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project"
    mcp      = "{\"mcp\": {\"test\": {\"command\": \"test-cmd\", \"type\": \"local\"}}}"
  }

  assert {
    condition     = var.mcp != ""
    error_message = "MCP configuration should be set"
  }

  assert {
    condition     = can(jsondecode(var.mcp))
    error_message = "MCP configuration should be valid JSON"
  }
}

run "task_reporting_configuration" {
  command = plan

  variables {
    agent_id     = "test-agent"
    workdir      = "/home/coder/project"
    report_tasks = false
  }

  assert {
    condition     = var.report_tasks == false
    error_message = "Task reporting should be disabled when specified"
  }
}

run "subdomain_configuration" {
  command = plan

  variables {
    agent_id  = "test-agent"
    workdir   = "/home/coder/project"
    subdomain = true
  }

  assert {
    condition     = var.subdomain == true
    error_message = "Subdomain should be enabled when specified"
  }
}

run "install_flags_configuration" {
  command = plan

  variables {
    agent_id         = "test-agent"
    workdir          = "/home/coder/project"
    install_opencode = false
    install_agentapi = false
  }

  assert {
    condition     = var.install_opencode == false
    error_message = "OpenCode installation should be disabled when specified"
  }

  assert {
    condition     = var.install_agentapi == false
    error_message = "AgentAPI installation should be disabled when specified"
  }
}

run "custom_scripts_configuration" {
  command = plan

  variables {
    agent_id            = "test-agent"
    workdir             = "/home/coder/project"
    pre_install_script  = "#!/bin/bash\necho 'pre-install'"
    post_install_script = "#!/bin/bash\necho 'post-install'"
  }

  assert {
    condition     = var.pre_install_script != null
    error_message = "Pre-install script should be set"
  }

  assert {
    condition     = var.post_install_script != null
    error_message = "Post-install script should be set"
  }

  assert {
    condition     = can(regex("pre-install", var.pre_install_script))
    error_message = "Pre-install script should contain expected content"
  }

  assert {
    condition     = can(regex("post-install", var.post_install_script))
    error_message = "Post-install script should contain expected content"
  }
}

run "empty_variables_handled_correctly" {
  command = plan

  variables {
    agent_id   = "test-agent"
    workdir    = "/home/coder/project"
    ai_prompt  = ""
    model      = ""
    agent      = ""
    session_id = ""
    auth_json  = ""
    mcp        = ""
  }

  assert {
    condition     = var.ai_prompt == ""
    error_message = "Empty AI prompt should be handled correctly"
  }

  assert {
    condition     = var.model == ""
    error_message = "Empty model should be handled correctly"
  }

  assert {
    condition     = var.agent == ""
    error_message = "Empty agent should be handled correctly"
  }

  assert {
    condition     = var.session_id == ""
    error_message = "Empty session ID should be handled correctly"
  }

  assert {
    condition     = var.auth_json == ""
    error_message = "Empty auth JSON should be handled correctly"
  }

  assert {
    condition     = var.mcp == ""
    error_message = "Empty MCP config should be handled correctly"
  }
}