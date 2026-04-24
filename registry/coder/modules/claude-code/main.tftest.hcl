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
}

run "test_claude_code_with_api_key" {
  command = plan

  variables {
    agent_id          = "test-agent-456"
    workdir           = "/home/coder/workspace"
    anthropic_api_key = "test-api-key-123"
  }

  assert {
    condition     = coder_env.anthropic_api_key[0].value == "test-api-key-123"
    error_message = "Anthropic API key value should match the input"
  }
}

run "test_claude_code_with_custom_options" {
  command = plan

  variables {
    agent_id            = "test-agent-789"
    workdir             = "/home/coder/custom"
    icon                = "/icon/custom.svg"
    model               = "opus"
    install_claude_code = false
    claude_code_version = "1.0.0"
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
    condition     = var.claude_code_version == "1.0.0"
    error_message = "Claude Code version should be set to '1.0.0'"
  }
}

run "test_claude_code_with_mcp" {
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
  }

  assert {
    condition     = var.mcp != ""
    error_message = "MCP configuration should be provided"
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

run "test_ai_gateway_enabled" {
  command = plan

  variables {
    agent_id          = "test-agent-ai-gateway"
    workdir           = "/home/coder/ai-gateway"
    enable_ai_gateway = true
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      session_token = "mock-session-token"
    }
  }

  assert {
    condition     = var.enable_ai_gateway == true
    error_message = "AI Gateway should be enabled"
  }

  assert {
    condition     = coder_env.anthropic_base_url[0].name == "ANTHROPIC_BASE_URL"
    error_message = "ANTHROPIC_BASE_URL environment variable should be set"
  }

  assert {
    condition     = length(regexall("/api/v2/aibridge/anthropic", coder_env.anthropic_base_url[0].value)) > 0
    error_message = "ANTHROPIC_BASE_URL should point to AI Gateway endpoint"
  }

  assert {
    condition     = coder_env.anthropic_auth_token[0].name == "ANTHROPIC_AUTH_TOKEN"
    error_message = "ANTHROPIC_AUTH_TOKEN environment variable should be set"
  }

  assert {
    condition     = coder_env.anthropic_auth_token[0].value == data.coder_workspace_owner.me.session_token
    error_message = "ANTHROPIC_AUTH_TOKEN should use workspace owner's session token when ai_gateway is enabled"
  }

  assert {
    condition     = length(coder_env.anthropic_api_key) == 0
    error_message = "ANTHROPIC_API_KEY env should not be created when ai_gateway is enabled and no anthropic_api_key is provided"
  }
}

run "test_ai_gateway_validation_with_api_key" {
  command = plan

  variables {
    agent_id          = "test-agent-validation"
    workdir           = "/home/coder/test"
    enable_ai_gateway = true
    anthropic_api_key = "test-api-key"
  }

  expect_failures = [
    var.enable_ai_gateway,
  ]
}

run "test_ai_gateway_validation_with_oauth_token" {
  command = plan

  variables {
    agent_id                = "test-agent-validation"
    workdir                 = "/home/coder/test"
    enable_ai_gateway       = true
    claude_code_oauth_token = "test-auth-token"
  }

  expect_failures = [
    var.enable_ai_gateway,
  ]
}

run "test_ai_gateway_disabled_with_api_key" {
  command = plan

  variables {
    agent_id          = "test-agent-no-ai-gateway"
    workdir           = "/home/coder/test"
    enable_ai_gateway = false
    anthropic_api_key = "test-api-key-xyz"
  }

  assert {
    condition     = var.enable_ai_gateway == false
    error_message = "AI Gateway should be disabled"
  }

  assert {
    condition     = coder_env.anthropic_api_key[0].value == "test-api-key-xyz"
    error_message = "ANTHROPIC_API_KEY should use the provided API key when ai_gateway is disabled"
  }

  assert {
    condition     = length(coder_env.anthropic_base_url) == 0
    error_message = "ANTHROPIC_BASE_URL should not be set when ai_gateway is disabled"
  }
}

run "test_no_api_key_no_env" {
  command = plan

  variables {
    agent_id          = "test-agent-no-key"
    workdir           = "/home/coder/test"
    enable_ai_gateway = false
  }

  assert {
    condition     = length(coder_env.anthropic_api_key) == 0
    error_message = "ANTHROPIC_API_KEY should not be created when no API key is provided and ai_gateway is disabled"
  }
}

run "test_api_key_count_with_ai_gateway_no_override" {
  command = plan

  variables {
    agent_id          = "test-agent-count"
    workdir           = "/home/coder/test"
    enable_ai_gateway = true
  }

  assert {
    condition     = length(coder_env.anthropic_auth_token) == 1
    error_message = "ANTHROPIC_AUTH_TOKEN env should be created when ai_gateway is enabled"
  }
}

run "test_script_outputs_install_only" {
  command = plan

  variables {
    agent_id = "test-agent-outputs"
    workdir  = "/home/coder/test"
  }

  assert {
    condition     = length(output.scripts) == 1 && output.scripts[0] == "coder-claude-code-install_script"
    error_message = "scripts output should list only the install script when pre/post are not configured"
  }
}

run "test_script_outputs_with_pre_and_post" {
  command = plan

  variables {
    agent_id            = "test-agent-outputs-all"
    workdir             = "/home/coder/test"
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = output.scripts == ["coder-claude-code-pre_install_script", "coder-claude-code-install_script", "coder-claude-code-post_install_script"]
    error_message = "scripts output should list pre_install, install, post_install in run order"
  }
}

run "test_workdir_optional" {
  command = plan

  variables {
    agent_id = "test-agent-no-workdir"
  }

  assert {
    condition     = var.workdir == null
    error_message = "workdir should default to null when omitted"
  }
}
