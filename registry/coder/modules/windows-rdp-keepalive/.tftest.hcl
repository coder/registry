variables {
  agent_id = "test-agent-id"
}

run "test_default_values" {
  command = plan

  assert {
    condition     = var.check_interval == 30
    error_message = "Default check_interval should be 30"
  }

  assert {
    condition     = var.enabled == true
    error_message = "Default enabled should be true"
  }
}

run "test_custom_interval" {
  command = plan

  variables {
    check_interval = 60
  }

  assert {
    condition     = var.check_interval == 60
    error_message = "check_interval should be customizable"
  }
}

run "test_disabled" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(coder_script.rdp-keepalive) == 0
    error_message = "Script should not be created when disabled"
  }
}

run "test_enabled" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = length(coder_script.rdp-keepalive) == 1
    error_message = "Script should be created when enabled"
  }
}
