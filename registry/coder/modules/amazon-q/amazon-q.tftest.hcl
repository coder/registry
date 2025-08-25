run "required_variables" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }
}

run "minimal_config" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    auth_tarball = "dGVzdA==" # base64 "test"
  }

  assert {
    condition     = resource.coder_env.status_slug.name == "CODER_MCP_APP_STATUS_SLUG"
    error_message = "Status slug environment variable not configured correctly"
  }

  assert {
    condition     = resource.coder_env.status_slug.value == "amazonq"
    error_message = "Status slug value should be 'amazonq'"
  }
}

run "full_config" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    folder              = "/home/coder/project"
    install_amazon_q    = true
    install_agentapi    = true
    agentapi_version    = "v0.5.0"
    amazon_q_version    = "latest"
    trust_all_tools     = true
    ai_prompt           = "Build a web application"
    auth_tarball        = "dGVzdA=="
    order               = 1
    group               = "AI Tools"
    icon                = "/icon/custom-amazon-q.svg"
    pre_install_script  = "echo 'pre-install'"
    post_install_script = "echo 'post-install'"
    agent_config = jsonencode({
      name        = "test-agent"
      description = "Test agent configuration"
    })
  }

  assert {
    condition     = resource.coder_env.status_slug.name == "CODER_MCP_APP_STATUS_SLUG"
    error_message = "Status slug environment variable not configured correctly"
  }

  assert {
    condition     = resource.coder_env.status_slug.value == "amazonq"
    error_message = "Status slug value should be 'amazonq'"
  }

  assert {
    condition     = length(resource.coder_env.auth_tarball) == 1
    error_message = "Auth tarball environment variable should be created when provided"
  }
}

run "auth_tarball_environment" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    auth_tarball = "dGVzdEF1dGhUYXJiYWxs" # base64 "testAuthTarball"
  }

  assert {
    condition     = resource.coder_env.auth_tarball[0].name == "AMAZON_Q_AUTH_TARBALL"
    error_message = "Auth tarball environment variable name should be 'AMAZON_Q_AUTH_TARBALL'"
  }

  assert {
    condition     = resource.coder_env.auth_tarball[0].value == "dGVzdEF1dGhUYXJiYWxs"
    error_message = "Auth tarball environment variable value should match input"
  }
}

run "empty_auth_tarball" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    auth_tarball = ""
  }

  assert {
    condition     = length(resource.coder_env.auth_tarball) == 0
    error_message = "Auth tarball environment variable should not be created when empty"
  }
}

run "custom_system_prompt" {
  command = plan

  variables {
    agent_id      = "test-agent-id"
    system_prompt = "Custom system prompt for testing"
  }

  # Test that the system prompt is used in the agent config template
  assert {
    condition     = length(local.agent_config) > 0
    error_message = "Agent config should be generated with custom system prompt"
  }
}

run "install_options" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    install_amazon_q = false
    install_agentapi = false
  }

  assert {
    condition     = resource.coder_env.status_slug.name == "CODER_MCP_APP_STATUS_SLUG"
    error_message = "Status slug should still be configured even when install options are disabled"
  }
}

run "version_configuration" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    amazon_q_version = "2.15.0"
    agentapi_version = "v0.4.0"
  }

  assert {
    condition     = resource.coder_env.status_slug.value == "amazonq"
    error_message = "Status slug value should remain 'amazonq' regardless of version"
  }
}
