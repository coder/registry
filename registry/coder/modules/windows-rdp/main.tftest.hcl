run "basic_module_test" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = coder_script.windows-rdp.agent_id == "test-agent-id"
    error_message = "Windows RDP script should be created with correct agent_id"
  }

  assert {
    condition     = coder_app.windows-rdp.agent_id == "test-agent-id"
    error_message = "Windows RDP app should be created with correct agent_id"
  }

  assert {
    condition     = length(coder_script.windows-rdp-keepalive) == 0
    error_message = "Keepalive script should NOT be created when keepalive is disabled (default)"
  }
}

run "keepalive_enabled_test" {
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
    condition     = coder_script.windows-rdp-keepalive[0].start_blocks_login == false
    error_message = "Keepalive script should not block login"
  }
}

run "custom_keepalive_interval_test" {
  command = plan

  variables {
    agent_id           = "test-agent-id"
    keepalive          = true
    keepalive_interval = 600
  }

  assert {
    condition     = length(coder_script.windows-rdp-keepalive) == 1
    error_message = "Keepalive script should be created with custom interval"
  }
}
