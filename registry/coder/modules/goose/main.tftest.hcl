run "test_goose_basic" {
  command = plan

  variables {
    agent_id       = "test-agent-123"
    goose_provider = "anthropic"
    goose_model    = "claude-3-5-sonnet-latest"
  }

  assert {
    condition     = var.goose_provider == "anthropic"
    error_message = "Goose provider variable should be set correctly"
  }

  assert {
    condition     = var.goose_model == "claude-3-5-sonnet-latest"
    error_message = "Goose model variable should be set correctly"
  }

  assert {
    condition     = var.install_goose == true
    error_message = "Install goose should default to true"
  }

  assert {
    condition     = var.install_agentapi == true
    error_message = "Install agentapi should default to true"
  }

  assert {
    condition     = var.continue == true
    error_message = "Continue should default to true"
  }

}

run "test_goose_with_session_name" {
  command = plan

  variables {
    agent_id       = "test-agent-456"
    goose_provider = "anthropic"
    goose_model    = "claude-3-5-sonnet-latest"
    session_name   = "my-custom-session"
  }

  assert {
    condition     = var.session_name == "my-custom-session"
    error_message = "Session name should be set to my-custom-session"
  }
}

run "test_goose_continue_disabled" {
  command = plan

  variables {
    agent_id       = "test-agent-789"
    goose_provider = "anthropic"
    goose_model    = "claude-3-5-sonnet-latest"
    continue       = false
  }

  assert {
    condition     = var.continue == false
    error_message = "Continue should be set to false"
  }
}

run "test_goose_default_session_name" {
  command = plan

  variables {
    agent_id       = "test-agent-101"
    goose_provider = "anthropic"
    goose_model    = "claude-3-5-sonnet-latest"
  }

  assert {
    condition     = length(regexall("task-", local.default_session_name)) > 0
    error_message = "Default session name should contain task- prefix"
  }
}

run "test_goose_with_additional_extensions" {
  command = plan

  variables {
    agent_id              = "test-agent-202"
    goose_provider        = "anthropic"
    goose_model           = "claude-3-5-sonnet-latest"
    additional_extensions = <<-EOT
custom-extension:
  enabled: true
  name: custom
  timeout: 300
  type: builtin
EOT
  }

  assert {
    condition     = var.additional_extensions != null
    error_message = "Additional extensions should be set"
  }
}

