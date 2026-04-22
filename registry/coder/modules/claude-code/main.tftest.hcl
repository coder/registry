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
    condition     = length(coder_env.env) == 0
    error_message = "No env vars should be set by default"
  }
}

run "test_with_env_map" {
  command = plan

  variables {
    agent_id = "test-agent"
    env = {
      ANTHROPIC_API_KEY       = "sk-live"
      CLAUDE_CODE_OAUTH_TOKEN = "oauth-live"
      ANTHROPIC_MODEL         = "opus"
      ANTHROPIC_BASE_URL      = "https://proxy.example.com"
      DISABLE_AUTOUPDATER     = "1"
      CUSTOM_VAR              = "hello"
    }
  }

  assert {
    condition     = coder_env.env["ANTHROPIC_API_KEY"].value == "sk-live"
    error_message = "env[ANTHROPIC_API_KEY] should be set"
  }

  assert {
    condition     = coder_env.env["CLAUDE_CODE_OAUTH_TOKEN"].value == "oauth-live"
    error_message = "env[CLAUDE_CODE_OAUTH_TOKEN] should be set"
  }

  assert {
    condition     = coder_env.env["ANTHROPIC_MODEL"].value == "opus"
    error_message = "env[ANTHROPIC_MODEL] should be set"
  }

  assert {
    condition     = coder_env.env["ANTHROPIC_BASE_URL"].value == "https://proxy.example.com"
    error_message = "env[ANTHROPIC_BASE_URL] should be set"
  }

  assert {
    condition     = coder_env.env["DISABLE_AUTOUPDATER"].value == "1"
    error_message = "env[DISABLE_AUTOUPDATER] should be set"
  }

  assert {
    condition     = coder_env.env["CUSTOM_VAR"].value == "hello"
    error_message = "arbitrary env keys should pass through"
  }

  assert {
    condition     = length(coder_env.env) == 6
    error_message = "should create exactly 6 coder_env resources"
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
