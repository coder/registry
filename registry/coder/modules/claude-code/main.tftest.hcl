run "test_claude_code_basic" {
  command = plan

  variables {
    agent_id = "test-agent-123"
    workdir  = "/home/coder/projects"
  }

  assert {
    condition     = var.workdir == "/home/coder/projects"
    error_message = "Workdir variable should be set correctly"
  }

  assert {
    condition     = var.agent_id == "test-agent-123"
    error_message = "Agent ID variable should be set correctly"
  }

  assert {
    condition     = var.install_claude_code == true
    error_message = "Install claude_code should default to true"
  }

  assert {
    condition     = var.install_agentapi == true
    error_message = "Install agentapi should default to true"
  }

  assert {
    condition     = var.report_tasks == true
    error_message = "report_tasks should default to true"
  }
}

run "test_claude_code_with_api_key" {
  command = plan

  variables {
    agent_id       = "test-agent-456"
    workdir        = "/home/coder/workspace"
    claude_api_key = "test-api-key-123"
  }

  assert {
    condition     = coder_env.claude_api_key[0].value == "test-api-key-123"
    error_message = "Claude API key value should match the input"
  }
}

run "test_claude_code_with_custom_options" {
  command = plan

  variables {
    agent_id                     = "test-agent-789"
    workdir                      = "/home/coder/custom"
    order                        = 5
    group                        = "development"
    icon                         = "/icon/custom.svg"
    model                        = "opus"
    ai_prompt                    = "Help me write better code"
    permission_mode              = "plan"
    continue                     = true
    install_claude_code          = false
    install_agentapi             = false
    claude_code_version          = "1.0.0"
    agentapi_version             = "v0.6.0"
    dangerously_skip_permissions = true
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
    condition     = var.model == "opus"
    error_message = "Claude model variable should be set to 'opus'"
  }

  assert {
    condition     = var.ai_prompt == "Help me write better code"
    error_message = "AI prompt variable should be set correctly"
  }

  assert {
    condition     = var.permission_mode == "plan"
    error_message = "Permission mode should be set to 'plan'"
  }

  assert {
    condition     = var.continue == true
    error_message = "Continue should be set to true"
  }

  assert {
    condition     = var.claude_code_version == "1.0.0"
    error_message = "Claude Code version should be set to '1.0.0'"
  }

  assert {
    condition     = var.agentapi_version == "v0.6.0"
    error_message = "AgentAPI version should be set to 'v0.6.0'"
  }

  assert {
    condition     = var.dangerously_skip_permissions == true
    error_message = "dangerously_skip_permissions should be set to true"
  }
}

run "test_claude_code_with_mcp_and_tools" {
  command = plan

  variables {
    agent_id = "test-agent-mcp"
    workdir  = "/home/coder/mcp-test"
    mcp = jsonencode({
      mcpServers = {
        test = {
          command = "test-server"
          args    = ["--config", "test.json"]
        }
      }
    })
    allowed_tools    = "bash,python"
    disallowed_tools = "rm"
  }

  assert {
    condition     = var.mcp != ""
    error_message = "MCP configuration should be provided"
  }

  assert {
    condition     = var.allowed_tools == "bash,python"
    error_message = "Allowed tools should be set"
  }

  assert {
    condition     = var.disallowed_tools == "rm"
    error_message = "Disallowed tools should be set"
  }
}

run "test_claude_code_with_scripts" {
  command = plan

  variables {
    agent_id            = "test-agent-scripts"
    workdir             = "/home/coder/scripts"
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

run "test_claude_code_permission_mode_validation" {
  command = plan

  variables {
    agent_id        = "test-agent-validation"
    workdir         = "/home/coder/test"
    permission_mode = "acceptEdits"
  }

  assert {
    condition     = contains(["", "default", "acceptEdits", "plan", "bypassPermissions"], var.permission_mode)
    error_message = "Permission mode should be one of the valid options"
  }
}

run "test_claude_code_with_boundary" {
  command = plan

  variables {
    agent_id        = "test-agent-boundary"
    workdir         = "/home/coder/boundary-test"
    enable_boundary = true
  }

  assert {
    condition     = var.enable_boundary == true
    error_message = "Boundary should be enabled"
  }

  assert {
    condition     = local.coder_host != ""
    error_message = "Coder host should be extracted from access URL"
  }
}

run "test_claude_code_system_prompt" {
  command = plan

  variables {
    agent_id      = "test-agent-system-prompt"
    workdir       = "/home/coder/test"
    system_prompt = "Custom addition"
  }

  assert {
    condition     = trimspace(coder_env.claude_code_system_prompt.value) != ""
    error_message = "System prompt should not be empty"
  }

  assert {
    condition     = length(regexall("Custom addition", coder_env.claude_code_system_prompt.value)) > 0
    error_message = "System prompt should have system_prompt variable value"
  }
}

run "test_claude_report_tasks_default" {
  command = plan

  variables {
    agent_id = "test-agent-report-tasks"
    workdir  = "/home/coder/test"
    # report_tasks: default is true
  }

  assert {
    condition     = trimspace(coder_env.claude_code_system_prompt.value) != ""
    error_message = "System prompt should not be empty"
  }

  # Ensure system prompt is wrapped by <system>
  assert {
    condition     = startswith(trimspace(coder_env.claude_code_system_prompt.value), "<system>")
    error_message = "System prompt should start with <system>"
  }
  assert {
    condition     = endswith(trimspace(coder_env.claude_code_system_prompt.value), "</system>")
    error_message = "System prompt should end with </system>"
  }

  # Ensure Coder sections are injected when report_tasks=true (default)
  assert {
    condition     = length(regexall("-- Tool Selection --", coder_env.claude_code_system_prompt.value)) > 0
    error_message = "System prompt should have Tool Selection section"
  }

  assert {
    condition     = length(regexall("-- Task Reporting --", coder_env.claude_code_system_prompt.value)) > 0
    error_message = "System prompt should have Task Reporting section"
  }
}

run "test_claude_report_tasks_disabled" {
  command = plan

  variables {
    agent_id     = "test-agent-report-tasks"
    workdir      = "/home/coder/test"
    report_tasks = false
  }

  assert {
    condition     = trimspace(coder_env.claude_code_system_prompt.value) != ""
    error_message = "System prompt should not be empty"
  }

  # Ensure system prompt is wrapped by <system>
  assert {
    condition     = startswith(trimspace(coder_env.claude_code_system_prompt.value), "<system>")
    error_message = "System prompt should start with <system>"
  }
  assert {
    condition     = endswith(trimspace(coder_env.claude_code_system_prompt.value), "</system>")
    error_message = "System prompt should end with </system>"
  }
}

run "test_aibridge_enabled" {
  command = plan

  variables {
    agent_id        = "test-agent-aibridge"
    workdir         = "/home/coder/aibridge"
    enable_aibridge = true
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      session_token = "mock-session-token"
    }
  }

  assert {
    condition     = var.enable_aibridge == true
    error_message = "AI Bridge should be enabled"
  }

  assert {
    condition     = coder_env.anthropic_base_url[0].name == "ANTHROPIC_BASE_URL"
    error_message = "ANTHROPIC_BASE_URL environment variable should be set"
  }

  assert {
    condition     = length(regexall("/api/v2/aibridge/anthropic", coder_env.anthropic_base_url[0].value)) > 0
    error_message = "ANTHROPIC_BASE_URL should point to AI Bridge endpoint"
  }

  assert {
    condition     = coder_env.claude_api_key[0].name == "CLAUDE_API_KEY"
    error_message = "CLAUDE_API_KEY environment variable should be set"
  }

  assert {
    condition     = coder_env.claude_api_key[0].value == data.coder_workspace_owner.me.session_token
    error_message = "CLAUDE_API_KEY should use workspace owner's session token when aibridge is enabled"
  }
}

run "test_aibridge_validation_with_api_key" {
  command = plan

  variables {
    agent_id        = "test-agent-validation"
    workdir         = "/home/coder/test"
    enable_aibridge = true
    claude_api_key  = "test-api-key"
  }

  expect_failures = [
    var.enable_aibridge,
  ]
}

run "test_aibridge_validation_with_oauth_token" {
  command = plan

  variables {
    agent_id                = "test-agent-validation"
    workdir                 = "/home/coder/test"
    enable_aibridge         = true
    claude_code_oauth_token = "test-oauth-token"
  }

  expect_failures = [
    var.enable_aibridge,
  ]
}

run "test_aibridge_disabled_with_api_key" {
  command = plan

  variables {
    agent_id        = "test-agent-no-aibridge"
    workdir         = "/home/coder/test"
    enable_aibridge = false
    claude_api_key  = "test-api-key-xyz"
  }

  assert {
    condition     = var.enable_aibridge == false
    error_message = "AI Bridge should be disabled"
  }

  assert {
    condition     = coder_env.claude_api_key[0].value == "test-api-key-xyz"
    error_message = "CLAUDE_API_KEY should use the provided API key when aibridge is disabled"
  }

  assert {
    condition     = length(coder_env.anthropic_base_url) == 0
    error_message = "ANTHROPIC_BASE_URL should not be set when aibridge is disabled"
  }
}

run "test_enable_state_persistence_default" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
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
    enable_state_persistence = false
  }

  assert {
    condition     = var.enable_state_persistence == false
    error_message = "enable_state_persistence should be false when explicitly disabled"
  }
}


run "test_no_api_key_no_env" {
  command = plan

  variables {
    agent_id        = "test-agent-no-key"
    workdir         = "/home/coder/test"
    enable_aibridge = false
  }

  assert {
    condition     = length(coder_env.claude_api_key) == 0
    error_message = "CLAUDE_API_KEY should not be created when no API key is provided and aibridge is disabled"
  }
}
