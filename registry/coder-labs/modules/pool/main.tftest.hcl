run "test_pool_defaults" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.install_pool == true
    error_message = "install_pool should default to true"
  }

  assert {
    condition     = var.pool_binary_path == "$HOME/.local/bin"
    error_message = "pool_binary_path should default to $HOME/.local/bin"
  }
}

run "test_pool_with_api_key" {
  command = plan

  variables {
    agent_id         = "test-agent"
    poolside_api_key = "test-key"
  }

  assert {
    condition     = coder_env.poolside_api_key[0].value == "test-key"
    error_message = "POOLSIDE_API_KEY should use the supplied key"
  }
}

run "test_standalone_endpoint" {
  command = plan

  variables {
    agent_id            = "test-agent"
    standalone_base_url = "https://gateway.example.com/v1"
    model               = "test-model"
  }

  assert {
    condition     = coder_env.standalone_base_url[0].value == "https://gateway.example.com/v1"
    error_message = "POOLSIDE_STANDALONE_BASE_URL should use the supplied endpoint"
  }

  assert {
    condition     = coder_env.model[0].value == "test-model"
    error_message = "POOLSIDE_STANDALONE_MODEL should use the supplied model"
  }
}

run "test_ai_gateway_enabled" {
  command = plan

  variables {
    agent_id          = "test-agent"
    enable_ai_gateway = true
    model             = "gpt-5"
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      session_token = "mock-session-token"
    }
  }

  assert {
    condition     = coder_env.ai_gateway_session_token[0].value == data.coder_workspace_owner.me.session_token
    error_message = "AI Gateway should use the workspace owner's session token"
  }

  assert {
    condition     = coder_env.ai_gateway_base_url[0].name == "POOLSIDE_STANDALONE_BASE_URL"
    error_message = "AI Gateway should configure Pool's OpenAI-compatible endpoint"
  }

  assert {
    condition     = length(coder_env.poolside_api_key) == 0
    error_message = "A direct Poolside API key should not be set when AI Gateway is enabled"
  }
}

run "test_ai_gateway_rejects_api_key" {
  command = plan

  variables {
    agent_id          = "test-agent"
    enable_ai_gateway = true
    poolside_api_key  = "test-key"
  }

  expect_failures = [var.enable_ai_gateway]
}

run "test_ai_gateway_rejects_standalone_endpoint" {
  command = plan

  variables {
    agent_id            = "test-agent"
    enable_ai_gateway   = true
    standalone_base_url = "https://gateway.example.com/v1"
  }

  expect_failures = [var.standalone_base_url]
}

run "test_scripts_output" {
  command = plan

  variables {
    agent_id            = "test-agent"
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = length(output.scripts) == 3
    error_message = "scripts should include pre-install, install, and post-install scripts"
  }
}
