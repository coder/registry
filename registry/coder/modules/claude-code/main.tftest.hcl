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

  assert {
    condition     = length(coder_env.anthropic_api_key) == 0
    error_message = "ANTHROPIC_API_KEY should not be set by default"
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
    error_message = "Shortcut must create a coder_env named ANTHROPIC_API_KEY"
  }

  assert {
    condition     = coder_env.anthropic_api_key[0].value == "sk-live-test"
    error_message = "anthropic_api_key value must round-trip"
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
    error_message = "Shortcut must create a coder_env named CLAUDE_CODE_OAUTH_TOKEN"
  }

  assert {
    condition     = coder_env.claude_code_oauth_token[0].value == "oauth-test-token"
    error_message = "claude_code_oauth_token value must round-trip"
  }
}

run "test_with_env_map" {
  command = plan

  variables {
    agent_id = "test-agent"
    env = {
      ANTHROPIC_MODEL     = "opus"
      ANTHROPIC_BASE_URL  = "https://proxy.example.com"
      DISABLE_AUTOUPDATER = "1"
      CUSTOM_VAR          = "hello"
    }
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
    condition     = length(coder_env.env) == 4
    error_message = "should create exactly 4 coder_env resources from env"
  }
}

run "test_env_and_shortcut_coexist" {
  command = plan

  variables {
    agent_id          = "test-agent"
    anthropic_api_key = "sk-live"
    env = {
      ANTHROPIC_MODEL = "sonnet"
    }
  }

  assert {
    condition     = coder_env.anthropic_api_key[0].value == "sk-live"
    error_message = "shortcut should set ANTHROPIC_API_KEY"
  }

  assert {
    condition     = coder_env.env["ANTHROPIC_MODEL"].value == "sonnet"
    error_message = "env map should set ANTHROPIC_MODEL"
  }

  assert {
    condition     = length(coder_env.env) == 1
    error_message = "env resource should have one entry"
  }

  assert {
    condition     = length(coder_env.anthropic_api_key) == 1
    error_message = "anthropic_api_key resource should have one entry"
  }
}

run "test_env_map_api_key_conflict" {
  command = plan

  variables {
    agent_id = "test-agent"
    env = {
      ANTHROPIC_API_KEY = "sk-wrong-channel"
    }
  }

  expect_failures = [var.env]
}

run "test_env_map_oauth_token_conflict" {
  command = plan

  variables {
    agent_id = "test-agent"
    env = {
      CLAUDE_CODE_OAUTH_TOKEN = "oauth-wrong-channel"
    }
  }

  expect_failures = [var.env]
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
