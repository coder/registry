run "test_cursor_cli_basic" {
  command = plan

  variables {
    agent_id = "test-agent-123"
    folder   = "/home/coder/projects"
  }

  assert {
    condition     = coder_env.status_slug.name == "CODER_MCP_APP_STATUS_SLUG"
    error_message = "Status slug environment variable should be set correctly"
  }

  assert {
    condition     = coder_env.status_slug.value == "cursorcli"
    error_message = "Status slug value should be 'cursorcli'"
  }

  assert {
    condition     = var.folder == "/home/coder/projects"
    error_message = "Folder variable should be set correctly"
  }

  assert {
    condition     = var.agent_id == "test-agent-123"
    error_message = "Agent ID variable should be set correctly"
  }
}

run "test_cursor_cli_with_api_key" {
  command = plan

  variables {
    agent_id = "test-agent-456"
    folder   = "/home/coder/workspace"
    api_key  = "test-api-key-123"
  }

  assert {
    condition     = coder_env.cursor_api_key[0].name == "CURSOR_API_KEY"
    error_message = "Cursor API key environment variable should be set correctly"
  }

  assert {
    condition     = coder_env.cursor_api_key[0].value == "test-api-key-123"
    error_message = "Cursor API key value should match the input"
  }
}

run "test_cursor_cli_with_custom_options" {
  command = plan

  variables {
    agent_id           = "test-agent-789"
    folder             = "/home/coder/custom"
    order              = 5
    group              = "development"
    icon               = "/icon/custom.svg"
    model              = "sonnet-4"
    ai_prompt          = "Help me write better code"
    force              = false
    install_cursor_cli = false
    install_agentapi   = false
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
    condition     = var.model == "sonnet-4"
    error_message = "Model variable should be set to 'sonnet-4'"
  }

  assert {
    condition     = var.ai_prompt == "Help me write better code"
    error_message = "AI prompt variable should be set correctly"
  }

  assert {
    condition     = var.force == false
    error_message = "Force variable should be set to false"
  }
}

run "test_cursor_cli_with_mcp_and_rules" {
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
    rules_files = {
      "general.md"  = "# General coding rules\n- Write clean code\n- Add comments"
      "security.md" = "# Security rules\n- Never commit secrets\n- Validate inputs"
    }
  }

  assert {
    condition     = var.mcp != null
    error_message = "MCP configuration should be provided"
  }

  assert {
    condition     = var.rules_files != null
    error_message = "Rules files should be provided"
  }

  assert {
    condition     = length(var.rules_files) == 2
    error_message = "Should have 2 rules files"
  }
}

run "test_cursor_cli_with_scripts" {
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
