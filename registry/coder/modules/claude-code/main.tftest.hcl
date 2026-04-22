mock_provider "coder" {}

run "test_defaults" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.install_claude_code == true
    error_message = "install_claude_code should default to true"
  }

  assert {
    condition     = var.disable_autoupdater == false
    error_message = "disable_autoupdater should default to false"
  }

  assert {
    condition     = length(coder_env.anthropic_api_key) == 0
    error_message = "ANTHROPIC_API_KEY should not be set by default"
  }

  assert {
    condition     = length(coder_env.anthropic_model) == 0
    error_message = "ANTHROPIC_MODEL should not be set by default"
  }

  assert {
    condition     = length(coder_env.disable_autoupdater) == 0
    error_message = "DISABLE_AUTOUPDATER should not be set by default"
  }

  assert {
    condition     = length(coder_env.claude_code_oauth_token) == 0
    error_message = "CLAUDE_CODE_OAUTH_TOKEN should not be set by default"
  }
}

run "test_with_anthropic_api_key" {
  command = plan

  variables {
    agent_id          = "test-agent"
    anthropic_api_key = "sk-live-test"
  }

  assert {
    condition     = coder_env.anthropic_api_key[0].name == "ANTHROPIC_API_KEY"
    error_message = "Env var name must be ANTHROPIC_API_KEY"
  }

  assert {
    condition     = coder_env.anthropic_api_key[0].value == "sk-live-test"
    error_message = "ANTHROPIC_API_KEY value should match input"
  }
}

run "test_with_oauth_token" {
  command = plan

  variables {
    agent_id                = "test-agent"
    claude_code_oauth_token = "oauth-test-token"
  }

  assert {
    condition     = coder_env.claude_code_oauth_token[0].name == "CLAUDE_CODE_OAUTH_TOKEN"
    error_message = "Env var name must be CLAUDE_CODE_OAUTH_TOKEN"
  }

  assert {
    condition     = coder_env.claude_code_oauth_token[0].value == "oauth-test-token"
    error_message = "CLAUDE_CODE_OAUTH_TOKEN value should match input"
  }
}

run "test_with_model" {
  command = plan

  variables {
    agent_id = "test-agent"
    model    = "opus"
  }

  assert {
    condition     = coder_env.anthropic_model[0].value == "opus"
    error_message = "ANTHROPIC_MODEL should be set to 'opus'"
  }
}

run "test_with_disable_autoupdater" {
  command = plan

  variables {
    agent_id            = "test-agent"
    disable_autoupdater = true
  }

  assert {
    condition     = coder_env.disable_autoupdater[0].value == "1"
    error_message = "DISABLE_AUTOUPDATER should be '1' when disable_autoupdater is true"
  }
}

run "test_with_mcp_inline" {
  command = plan

  variables {
    agent_id = "test-agent"
    mcp = jsonencode({
      mcpServers = {
        test-server = {
          command = "test-cmd"
          args    = []
        }
      }
    })
  }

  assert {
    condition     = var.mcp != ""
    error_message = "mcp should be passed through"
  }
}

run "test_with_mcp_remote" {
  command = plan

  variables {
    agent_id               = "test-agent"
    mcp_config_remote_path = ["https://example.com/mcp.json"]
  }

  assert {
    condition     = length(var.mcp_config_remote_path) == 1
    error_message = "mcp_config_remote_path should carry one URL"
  }
}

run "test_with_pre_post_install" {
  command = plan

  variables {
    agent_id            = "test-agent"
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = var.pre_install_script == "echo pre"
    error_message = "pre_install_script should be forwarded"
  }

  assert {
    condition     = var.post_install_script == "echo post"
    error_message = "post_install_script should be forwarded"
  }
}

run "test_claude_binary_path_validation" {
  command = plan

  variables {
    agent_id            = "test-agent"
    install_claude_code = true
    claude_binary_path  = "/opt/custom"
  }

  expect_failures = [var.claude_binary_path]
}
