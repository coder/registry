# Test for agent-helper module

# Test with all scripts provided
run "test_with_all_scripts" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    agent_name          = "test-agent"
    module_dir_name     = ".test-module"
    pre_install_script  = "echo 'pre-install'"
    install_script      = "echo 'install'"
    post_install_script = "echo 'post-install'"
    start_script        = "echo 'start'"
  }

  # Verify log file creation script is created
  assert {
    condition     = coder_script.log_file_creation_script.agent_id == "test-agent-id"
    error_message = "Log file creation script agent ID should match input"
  }

  assert {
    condition     = coder_script.log_file_creation_script.display_name == "Log File Creation Script"
    error_message = "Log file creation script should have correct display name"
  }

  assert {
    condition     = coder_script.log_file_creation_script.run_on_start == true
    error_message = "Log file creation script should run on start"
  }

  # Verify pre_install_script is created when provided
  assert {
    condition     = length(coder_script.pre_install_script) == 1
    error_message = "Pre-install script should be created when pre_install_script is provided"
  }

  assert {
    condition     = coder_script.pre_install_script[0].agent_id == "test-agent-id"
    error_message = "Pre-install script agent ID should match input"
  }

  assert {
    condition     = coder_script.pre_install_script[0].display_name == "Pre-Install Script"
    error_message = "Pre-install script should have correct display name"
  }

  # Verify install_script is created
  assert {
    condition     = coder_script.install_script.agent_id == "test-agent-id"
    error_message = "Install script agent ID should match input"
  }

  assert {
    condition     = coder_script.install_script.display_name == "Install Script"
    error_message = "Install script should have correct display name"
  }

  assert {
    condition     = coder_script.install_script.run_on_start == true
    error_message = "Install script should run on start"
  }

  # Verify post_install_script is created when provided
  assert {
    condition     = length(coder_script.post_install_script) == 1
    error_message = "Post-install script should be created when post_install_script is provided"
  }

  assert {
    condition     = coder_script.post_install_script[0].agent_id == "test-agent-id"
    error_message = "Post-install script agent ID should match input"
  }

  assert {
    condition     = coder_script.post_install_script[0].display_name == "Post-Install Script"
    error_message = "Post-install script should have correct display name"
  }

  # Verify start_script is created
  assert {
    condition     = coder_script.start_script.agent_id == "test-agent-id"
    error_message = "Start script agent ID should match input"
  }

  assert {
    condition     = coder_script.start_script.display_name == "Start Script"
    error_message = "Start script should have correct display name"
  }

  assert {
    condition     = coder_script.start_script.run_on_start == true
    error_message = "Start script should run on start"
  }
}

# Test with only required scripts (no pre/post install)
run "test_without_optional_scripts" {
  command = plan

  variables {
    agent_id        = "test-agent-id"
    agent_name      = "test-agent"
    module_dir_name = ".test-module"
    install_script  = "echo 'install'"
    start_script    = "echo 'start'"
  }

  # Verify pre_install_script is NOT created when not provided
  assert {
    condition     = length(coder_script.pre_install_script) == 0
    error_message = "Pre-install script should not be created when pre_install_script is null"
  }

  # Verify post_install_script is NOT created when not provided
  assert {
    condition     = length(coder_script.post_install_script) == 0
    error_message = "Post-install script should not be created when post_install_script is null"
  }

  # Verify required scripts are still created
  assert {
    condition     = coder_script.log_file_creation_script.agent_id == "test-agent-id"
    error_message = "Log file creation script should be created"
  }

  assert {
    condition     = coder_script.install_script.agent_id == "test-agent-id"
    error_message = "Install script should be created"
  }

  assert {
    condition     = coder_script.start_script.agent_id == "test-agent-id"
    error_message = "Start script should be created"
  }
}

# Test with mock data sources
run "test_with_mock_data" {
  command = plan

  variables {
    agent_id        = "mock-agent"
    agent_name      = "mock-agent"
    module_dir_name = ".mock-module"
    install_script  = "echo 'install'"
    start_script    = "echo 'start'"
  }

  # Mock the data sources for testing
  override_data {
    target = data.coder_workspace.me
    values = {
      id            = "test-workspace-id"
      name          = "test-workspace"
      owner         = "test-owner"
      owner_id      = "test-owner-id"
      template_id   = "test-template-id"
      template_name = "test-template"
      access_url    = "https://coder.example.com"
      start_count   = 1
      transition    = "start"
    }
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      id            = "test-owner-id"
      email         = "test@example.com"
      name          = "Test User"
      session_token = "mock-token"
    }
  }

  override_data {
    target = data.coder_task.me
    values = {
      id = "test-task-id"
    }
  }

  # Verify scripts are created with mocked data
  assert {
    condition     = coder_script.install_script.agent_id == "mock-agent"
    error_message = "Install script should use the mocked agent ID"
  }

  assert {
    condition     = coder_script.start_script.agent_id == "mock-agent"
    error_message = "Start script should use the mocked agent ID"
  }
}

# Test script naming with custom agent_name
run "test_script_naming" {
  command = plan

  variables {
    agent_id        = "test-agent"
    agent_name      = "custom-name"
    module_dir_name = ".test-module"
    install_script  = "echo 'install'"
    start_script    = "echo 'start'"
  }

  # Verify script names are constructed correctly
  # The script should contain references to custom-name-* in the sync commands
  assert {
    condition     = can(regex("custom-name-log_file_creation_script", coder_script.log_file_creation_script.script))
    error_message = "Log file creation script should use custom agent_name in sync commands"
  }

  assert {
    condition     = can(regex("custom-name-install_script", coder_script.install_script.script))
    error_message = "Install script should use custom agent_name in sync commands"
  }

  assert {
    condition     = can(regex("custom-name-start_script", coder_script.start_script.script))
    error_message = "Start script should use custom agent_name in sync commands"
  }
}
