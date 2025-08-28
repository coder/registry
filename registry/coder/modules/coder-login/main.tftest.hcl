# Test for coder-login module

run "test_coder_login_module" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  # Test that the coder_env resources are created with correct configuration
  assert {
    condition     = coder_env.coder_session_token.agent_id == "test-agent-id"
    error_message = "CODER_SESSION_TOKEN agent ID should match the input variable"
  }

  assert {
    condition     = coder_env.coder_session_token.name == "CODER_SESSION_TOKEN"
    error_message = "Environment variable name should be 'CODER_SESSION_TOKEN'"
  }

  assert {
    condition     = coder_env.coder_url.agent_id == "test-agent-id"
    error_message = "CODER_URL agent ID should match the input variable"
  }

  assert {
    condition     = coder_env.coder_url.name == "CODER_URL"
    error_message = "Environment variable name should be 'CODER_URL'"
  }
}

# Test with mock data sources
run "test_with_mock_data" {
  command = plan

  variables {
    agent_id = "mock-agent"
  }

  # Mock the data sources for testing
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

  # Verify environment variables get the mocked values
  assert {
    condition     = coder_env.coder_url.value == "https://coder.example.com"
    error_message = "CODER_URL should match workspace access_url"
  }

  assert {
    condition     = coder_env.coder_session_token.value == "mock-session-token"
    error_message = "CODER_SESSION_TOKEN should match workspace owner session_token"
  }
}