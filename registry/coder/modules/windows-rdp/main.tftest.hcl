run "basic_defaults" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = coder_script.windows-rdp.agent_id == "test-agent-id"
    error_message = "Windows RDP script should use the provided agent_id"
  }

  assert {
    condition     = coder_app.windows-rdp.agent_id == "test-agent-id"
    error_message = "Windows RDP app should use the provided agent_id"
  }

  assert {
    condition     = length(coder_script.windows-rdp-keepalive) == 0
    error_message = "Keepalive script should not be created when keepalive is disabled (default)"
  }
}

run "keepalive_disabled_by_default" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = var.keepalive == false
    error_message = "keepalive should default to false"
  }
}

run "keepalive_enabled" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    keepalive = true
  }

  assert {
    condition     = length(coder_script.windows-rdp-keepalive) == 1
    error_message = "Keepalive script should be created when keepalive is enabled"
  }

  assert {
    condition     = coder_script.windows-rdp-keepalive[0].display_name == "windows-rdp-keepalive"
    error_message = "Keepalive script should have correct display name"
  }

  assert {
    condition     = coder_script.windows-rdp-keepalive[0].run_on_start == true
    error_message = "Keepalive script should run on start"
  }

  assert {
    condition     = coder_script.windows-rdp-keepalive[0].start_blocks_login == false
    error_message = "Keepalive script should not block login"
  }
}

run "keepalive_default_interval" {
  command = plan

  variables {
    agent_id  = "test-agent-id"
    keepalive = true
  }

  assert {
    condition     = var.keepalive_interval == 30
    error_message = "Default keepalive interval should be 30 seconds"
  }
}

run "keepalive_custom_interval" {
  command = plan

  variables {
    agent_id           = "test-agent-id"
    keepalive          = true
    keepalive_interval = 120
  }

  assert {
    condition     = var.keepalive_interval == 120
    error_message = "Custom keepalive interval should be accepted"
  }
}

run "custom_devolutions_version" {
  command = plan

  variables {
    agent_id                    = "test-agent-id"
    devolutions_gateway_version = "2025.2.2"
  }

  assert {
    condition     = var.devolutions_gateway_version == "2025.2.2"
    error_message = "Custom Devolutions Gateway version should be accepted"
  }
}
