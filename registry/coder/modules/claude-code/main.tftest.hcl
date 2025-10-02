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
    task_prompt                  = "Help me write better code"
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
    condition     = var.task_prompt == "Help me write better code"
    error_message = "Task prompt variable should be set correctly"
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
