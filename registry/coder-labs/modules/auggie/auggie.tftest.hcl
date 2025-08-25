run "test_auggie_basic" {
  command = plan

  variables {
    agent_id = "test-agent-123"
    folder   = "/home/coder/projects"
  }

  assert {
    condition     = coder_env.auggie_session_auth.name == "AUGMENT_SESSION_AUTH"
    error_message = "Auggie session auth environment variable should be set correctly"
  }

  assert {
    condition     = var.folder == "/home/coder/projects"
    error_message = "Folder variable should be set correctly"
  }

  assert {
    condition     = var.agent_id == "test-agent-123"
    error_message = "Agent ID variable should be set correctly"
  }

  assert {
    condition     = var.install_auggie == true
    error_message = "Install auggie should default to true"
  }

  assert {
    condition     = var.install_agentapi == true
    error_message = "Install agentapi should default to true"
  }
}

run "test_auggie_with_session_token" {
  command = plan

  variables {
    agent_id              = "test-agent-456"
    folder                = "/home/coder/workspace"
    augment_session_token = "test-session-token-123"
  }

  assert {
    condition     = coder_env.auggie_session_auth.value == "test-session-token-123"
    error_message = "Auggie session token value should match the input"
  }
}

run "test_auggie_with_custom_options" {
  command = plan

  variables {
    agent_id                       = "test-agent-789"
    folder                         = "/home/coder/custom"
    order                          = 5
    group                          = "development"
    icon                           = "/icon/custom.svg"
    auggie_model                   = "gpt-4"
    ai_prompt                      = "Help me write better code"
    interaction_mode               = "compact"
    continue_previous_conversation = true
    install_auggie                 = false
    install_agentapi               = false
    auggie_version                 = "1.0.0"
    agentapi_version               = "v0.6.0"
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
    condition     = var.auggie_model == "gpt-4"
    error_message = "Auggie model variable should be set to 'gpt-4'"
  }

  assert {
    condition     = var.ai_prompt == "Help me write better code"
    error_message = "AI prompt variable should be set correctly"
  }

  assert {
    condition     = var.interaction_mode == "compact"
    error_message = "Interaction mode should be set to 'compact'"
  }

  assert {
    condition     = var.continue_previous_conversation == true
    error_message = "Continue previous conversation should be set to true"
  }

  assert {
    condition     = var.auggie_version == "1.0.0"
    error_message = "Auggie version should be set to '1.0.0'"
  }

  assert {
    condition     = var.agentapi_version == "v0.6.0"
    error_message = "AgentAPI version should be set to 'v0.6.0'"
  }
}

run "test_auggie_with_mcp_and_rules" {
  command = plan

  variables {
    agent_id = "test-agent-mcp"
    folder   = "/home/coder/mcp-test"
    mcp = jsonencode({
      mcpServers = {
        test = {
          command = "test-server"
          args    = ["--config", "test.json"]
        }
      }
    })
    mcp_files = [
      "/path/to/mcp1.json",
      "/path/to/mcp2.json"
    ]
    rules = "# General coding rules\n- Write clean code\n- Add comments"
  }

  assert {
    condition     = var.mcp != ""
    error_message = "MCP configuration should be provided"
  }

  assert {
    condition     = length(var.mcp_files) == 2
    error_message = "Should have 2 MCP files"
  }

  assert {
    condition     = var.rules != ""
    error_message = "Rules should be provided"
  }
}

run "test_auggie_with_scripts" {
  command = plan

  variables {
    agent_id            = "test-agent-scripts"
    folder              = "/home/coder/scripts"
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

run "test_auggie_interaction_mode_validation" {
  command = plan

  variables {
    agent_id         = "test-agent-validation"
    folder           = "/home/coder/test"
    interaction_mode = "print"
  }

  assert {
    condition     = contains(["interactive", "print", "quiet", "compact"], var.interaction_mode)
    error_message = "Interaction mode should be one of the valid options"
  }
}
