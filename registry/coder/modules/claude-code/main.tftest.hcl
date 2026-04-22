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

  # coder-utils exposes `script_names` with empty strings for scripts it did
  # not create; a non-empty name confirms the downstream resource was emitted.
  assert {
    condition     = module.coder-utils.script_names.pre_install != ""
    error_message = "Pre-install script name should be populated when pre_install_script is set"
  }

  assert {
    condition     = module.coder-utils.script_names.post_install != ""
    error_message = "Post-install script name should be populated when post_install_script is set"
  }

  assert {
    condition     = module.coder-utils.script_names.install != ""
    error_message = "Install script name should always be populated"
  }

  # `scripts` output is a filtered, run-order list. All three expected.
  assert {
    condition     = length(output.scripts) == 3
    error_message = "scripts output should have exactly 3 entries when pre/post are set"
  }

  assert {
    condition     = output.scripts[0] == module.coder-utils.script_names.pre_install
    error_message = "scripts[0] must be the pre-install name (run-order)"
  }

  assert {
    condition     = output.scripts[1] == module.coder-utils.script_names.install
    error_message = "scripts[1] must be the install name (run-order)"
  }

  assert {
    condition     = output.scripts[2] == module.coder-utils.script_names.post_install
    error_message = "scripts[2] must be the post-install name (run-order)"
  }
}

run "test_defaults_produce_only_install_script" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = module.coder-utils.script_names.pre_install == ""
    error_message = "Pre-install script should be absent by default"
  }

  assert {
    condition     = module.coder-utils.script_names.post_install == ""
    error_message = "Post-install script should be absent by default"
  }

  assert {
    condition     = module.coder-utils.script_names.start == ""
    error_message = "Start script should never be created by claude-code"
  }

  assert {
    condition     = module.coder-utils.script_names.install != ""
    error_message = "Install script must always be created"
  }

  # Defaults: `scripts` output holds exactly one entry (install).
  assert {
    condition     = length(output.scripts) == 1
    error_message = "scripts output should contain exactly 1 entry by default"
  }

  assert {
    condition     = output.scripts[0] == module.coder-utils.script_names.install
    error_message = "scripts[0] must be the install script name"
  }
}

run "test_scripts_output_excludes_post_when_only_pre_set" {
  command = plan

  variables {
    agent_id           = "test-agent"
    pre_install_script = "echo only-pre"
  }

  # With only pre_install set, `scripts` holds 2 entries: pre, install.
  assert {
    condition     = length(output.scripts) == 2
    error_message = "scripts output should contain exactly 2 entries when only pre is set"
  }

  assert {
    condition     = output.scripts[0] == module.coder-utils.script_names.pre_install
    error_message = "scripts[0] must be pre-install when it is set"
  }

  assert {
    condition     = output.scripts[1] == module.coder-utils.script_names.install
    error_message = "scripts[1] must be install when post is unset"
  }
}

run "test_mcp_remote_rejects_http" {
  command = plan

  variables {
    agent_id               = "test-agent"
    mcp_config_remote_path = ["http://example.com/mcp.json"]
  }

  expect_failures = [var.mcp_config_remote_path]
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

run "test_model_convenience" {
  command = plan

  variables {
    agent_id = "test-agent"
    model    = "opus"
  }

  assert {
    condition     = coder_env.env["ANTHROPIC_MODEL"].value == "opus"
    error_message = "model input must set ANTHROPIC_MODEL"
  }

  assert {
    condition     = length(coder_env.env) == 1
    error_message = "only ANTHROPIC_MODEL should be set"
  }
}

run "test_claude_code_oauth_token_convenience" {
  command = plan

  variables {
    agent_id                = "test-agent"
    claude_code_oauth_token = "oauth-live"
  }

  assert {
    condition     = coder_env.env["CLAUDE_CODE_OAUTH_TOKEN"].value == "oauth-live"
    error_message = "claude_code_oauth_token must set CLAUDE_CODE_OAUTH_TOKEN"
  }
}

run "test_disable_autoupdater_convenience" {
  command = plan

  variables {
    agent_id            = "test-agent"
    disable_autoupdater = true
  }

  assert {
    condition     = coder_env.env["DISABLE_AUTOUPDATER"].value == "1"
    error_message = "disable_autoupdater must set DISABLE_AUTOUPDATER=1"
  }
}

run "test_enable_ai_gateway_convenience" {
  command = plan

  variables {
    agent_id          = "test-agent"
    enable_ai_gateway = true
  }

  override_data {
    target = data.coder_workspace.me
    values = {
      access_url = "https://coder.example.com"
    }
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      session_token = "mock-session-token"
    }
  }

  assert {
    condition     = coder_env.env["ANTHROPIC_BASE_URL"].value == "https://coder.example.com/api/v2/aibridge/anthropic"
    error_message = "enable_ai_gateway must wire ANTHROPIC_BASE_URL to the aibridge endpoint"
  }

  assert {
    condition     = coder_env.env["ANTHROPIC_AUTH_TOKEN"].value == "mock-session-token"
    error_message = "enable_ai_gateway must wire ANTHROPIC_AUTH_TOKEN to the workspace owner session token"
  }
}

run "test_convenience_and_env_merge" {
  command = plan

  variables {
    agent_id = "test-agent"
    model    = "opus"
    env = {
      ANTHROPIC_API_KEY = "sk-live"
    }
  }

  assert {
    condition     = coder_env.env["ANTHROPIC_MODEL"].value == "opus"
    error_message = "convenience input must still apply when env is set"
  }

  assert {
    condition     = coder_env.env["ANTHROPIC_API_KEY"].value == "sk-live"
    error_message = "env entries must still apply when a convenience input is set"
  }

  assert {
    condition     = length(coder_env.env) == 2
    error_message = "merged env must have exactly 2 entries"
  }
}

run "test_model_conflicts_with_env" {
  command = plan

  variables {
    agent_id = "test-agent"
    model    = "opus"
    env = {
      ANTHROPIC_MODEL = "sonnet"
    }
  }

  expect_failures = [var.env]
}

run "test_oauth_token_conflicts_with_env" {
  command = plan

  variables {
    agent_id                = "test-agent"
    claude_code_oauth_token = "oauth-live"
    env = {
      CLAUDE_CODE_OAUTH_TOKEN = "oauth-from-env"
    }
  }

  expect_failures = [var.env]
}

run "test_ai_gateway_conflicts_with_env_base_url" {
  command = plan

  variables {
    agent_id          = "test-agent"
    enable_ai_gateway = true
    env = {
      ANTHROPIC_BASE_URL = "https://custom.example.com"
    }
  }

  expect_failures = [var.env]
}

run "test_ai_gateway_conflicts_with_env_auth_token" {
  command = plan

  variables {
    agent_id          = "test-agent"
    enable_ai_gateway = true
    env = {
      ANTHROPIC_AUTH_TOKEN = "custom-token"
    }
  }

  expect_failures = [var.env]
}

run "test_autoupdater_conflicts_with_env" {
  command = plan

  variables {
    agent_id            = "test-agent"
    disable_autoupdater = true
    env = {
      DISABLE_AUTOUPDATER = "0"
    }
  }

  expect_failures = [var.env]
}
