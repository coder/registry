# Test for coder-utils module

# Test with all scripts provided
run "test_with_all_scripts" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    agent_name          = "test-agent"
    module_directory    = ".test-module"
    pre_install_script  = "echo 'pre-install'"
    install_script      = "echo 'install'"
    post_install_script = "echo 'post-install'"
    start_script        = "echo 'start'"
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

  assert {
    condition     = coder_script.pre_install_script[0].run_on_start == true
    error_message = "Pre-install script should run on start"
  }

  # Verify install_script is always created
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

  # install should sync-want pre_install
  assert {
    condition     = can(regex("sync want test-agent-install_script test-agent-pre_install_script", coder_script.install_script.script))
    error_message = "Install script should sync-want pre_install_script when pre_install is provided"
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

  assert {
    condition     = coder_script.post_install_script[0].run_on_start == true
    error_message = "Post-install script should run on start"
  }

  # Verify start_script is created when provided
  assert {
    condition     = length(coder_script.start_script) == 1
    error_message = "Start script should be created when start_script is provided"
  }

  assert {
    condition     = coder_script.start_script[0].agent_id == "test-agent-id"
    error_message = "Start script agent ID should match input"
  }

  assert {
    condition     = coder_script.start_script[0].display_name == "Start Script"
    error_message = "Start script should have correct display name"
  }

  assert {
    condition     = coder_script.start_script[0].run_on_start == true
    error_message = "Start script should run on start"
  }

  # Verify outputs for script names
  assert {
    condition     = output.script_names.pre_install == "test-agent-pre_install_script"
    error_message = "Pre-install script name output should be correctly formatted"
  }

  assert {
    condition     = output.script_names.install == "test-agent-install_script"
    error_message = "Install script name output should be correctly formatted"
  }

  assert {
    condition     = output.script_names.post_install == "test-agent-post_install_script"
    error_message = "Post-install script name output should be correctly formatted"
  }

  assert {
    condition     = output.script_names.start == "test-agent-start_script"
    error_message = "Start script name output should be correctly formatted"
  }
}

# Test with only install_script (minimum required input)
run "test_install_only" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    agent_name       = "test-agent"
    module_directory = ".test-module"
    install_script   = "echo 'install'"
  }

  # Verify optional scripts are NOT created
  assert {
    condition     = length(coder_script.pre_install_script) == 0
    error_message = "Pre-install script should not be created when not provided"
  }

  assert {
    condition     = length(coder_script.post_install_script) == 0
    error_message = "Post-install script should not be created when not provided"
  }

  assert {
    condition     = length(coder_script.start_script) == 0
    error_message = "Start script should not be created when not provided"
  }

  # Verify install_script is created
  assert {
    condition     = coder_script.install_script.agent_id == "test-agent-id"
    error_message = "Install script should be created"
  }

  # Verify outputs
  assert {
    condition     = output.script_names.pre_install == ""
    error_message = "Pre-install script name output should be empty"
  }

  assert {
    condition     = output.script_names.install == "test-agent-install_script"
    error_message = "Install script name output should be correctly formatted"
  }

  assert {
    condition     = output.script_names.post_install == ""
    error_message = "Post-install script name output should be empty"
  }

  assert {
    condition     = output.script_names.start == ""
    error_message = "Start script name output should be empty"
  }
}

# Test with install and start scripts (no pre/post install)
run "test_install_and_start" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    agent_name       = "test-agent"
    module_directory = ".test-module"
    install_script   = "echo 'install'"
    start_script     = "echo 'start'"
  }

  assert {
    condition     = length(coder_script.pre_install_script) == 0
    error_message = "Pre-install script should not be created when not provided"
  }

  assert {
    condition     = length(coder_script.post_install_script) == 0
    error_message = "Post-install script should not be created when not provided"
  }

  assert {
    condition     = coder_script.install_script.agent_id == "test-agent-id"
    error_message = "Install script should be created"
  }

  assert {
    condition     = length(coder_script.start_script) == 1
    error_message = "Start script should be created"
  }

  assert {
    condition     = coder_script.start_script[0].agent_id == "test-agent-id"
    error_message = "Start script agent ID should match input"
  }

  # start should sync-want install (no post_install)
  assert {
    condition     = can(regex("sync want test-agent-start_script test-agent-install_script", coder_script.start_script[0].script))
    error_message = "Start script should sync-want install_script"
  }

  assert {
    condition     = output.script_names.pre_install == ""
    error_message = "Pre-install script name output should be empty"
  }

  assert {
    condition     = output.script_names.install == "test-agent-install_script"
    error_message = "Install script name output should be correctly formatted"
  }

  assert {
    condition     = output.script_names.post_install == ""
    error_message = "Post-install script name output should be empty"
  }

  assert {
    condition     = output.script_names.start == "test-agent-start_script"
    error_message = "Start script name output should be correctly formatted"
  }
}

# Test with mock data sources
run "test_with_mock_data" {
  command = plan

  variables {
    agent_id         = "mock-agent"
    agent_name       = "mock-agent"
    module_directory = ".mock-module"
    install_script   = "echo 'install'"
    start_script     = "echo 'start'"
  }

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

  assert {
    condition     = coder_script.install_script.agent_id == "mock-agent"
    error_message = "Install script should use the mocked agent ID"
  }

  assert {
    condition     = coder_script.start_script[0].agent_id == "mock-agent"
    error_message = "Start script should use the mocked agent ID"
  }
}

# Test script naming with custom agent_name
run "test_script_naming" {
  command = plan

  variables {
    agent_id         = "test-agent"
    agent_name       = "custom-name"
    module_directory = ".test-module"
    install_script   = "echo 'install'"
    start_script     = "echo 'start'"
  }

  assert {
    condition     = can(regex("custom-name-install_script", coder_script.install_script.script))
    error_message = "Install script should use custom agent_name in sync commands"
  }

  assert {
    condition     = can(regex("custom-name-start_script", coder_script.start_script[0].script))
    error_message = "Start script should use custom agent_name in sync commands"
  }

  assert {
    condition     = output.script_names.pre_install == ""
    error_message = "Pre-install script name output should be empty when not provided"
  }

  assert {
    condition     = output.script_names.install == "custom-name-install_script"
    error_message = "Install script name output should use custom agent_name"
  }

  assert {
    condition     = output.script_names.post_install == ""
    error_message = "Post-install script name output should be empty when not provided"
  }

  assert {
    condition     = output.script_names.start == "custom-name-start_script"
    error_message = "Start script name output should use custom agent_name"
  }
}

# Test install syncs with pre_install when provided
run "test_install_syncs_with_pre_install" {
  command = plan

  variables {
    agent_id           = "test-agent-id"
    agent_name         = "test-agent"
    module_directory   = ".test-module"
    pre_install_script = "echo 'pre-install'"
    install_script     = "echo 'install'"
  }

  assert {
    condition     = length(coder_script.pre_install_script) == 1
    error_message = "Pre-install script should be created"
  }

  assert {
    condition     = can(regex("sync want test-agent-install_script test-agent-pre_install_script", coder_script.install_script.script))
    error_message = "Install script should sync-want pre_install_script"
  }

  assert {
    condition     = output.script_names.pre_install == "test-agent-pre_install_script"
    error_message = "Pre-install script name output should be set"
  }
}

# Test start script sync deps with post_install present
run "test_start_syncs_with_post_install" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    agent_name          = "test-agent"
    module_directory    = ".test-module"
    install_script      = "echo 'install'"
    post_install_script = "echo 'post-install'"
    start_script        = "echo 'start'"
  }

  # start should sync-want both install and post_install
  assert {
    condition     = can(regex("sync want test-agent-start_script test-agent-install_script test-agent-post_install_script", coder_script.start_script[0].script))
    error_message = "Start script should sync-want both install_script and post_install_script"
  }

  # post_install should sync-want install
  assert {
    condition     = can(regex("sync want test-agent-post_install_script test-agent-install_script", coder_script.post_install_script[0].script))
    error_message = "Post-install script should sync-want install_script"
  }
}

# Verify display_name_prefix is prepended to every script's display_name
run "test_display_name_prefix_applied" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    agent_name          = "test-agent"
    module_directory    = ".test-module"
    display_name_prefix = "Claude Code"
    pre_install_script  = "echo 'pre-install'"
    install_script      = "echo 'install'"
    post_install_script = "echo 'post-install'"
    start_script        = "echo 'start'"
  }

  assert {
    condition     = coder_script.pre_install_script[0].display_name == "Claude Code: Pre-Install Script"
    error_message = "Pre-install script display_name should be prefixed"
  }

  assert {
    condition     = coder_script.install_script.display_name == "Claude Code: Install Script"
    error_message = "Install script display_name should be prefixed"
  }

  assert {
    condition     = coder_script.post_install_script[0].display_name == "Claude Code: Post-Install Script"
    error_message = "Post-install script display_name should be prefixed"
  }

  assert {
    condition     = coder_script.start_script[0].display_name == "Claude Code: Start Script"
    error_message = "Start script display_name should be prefixed"
  }
}

# Verify icon is propagated to every coder_script
run "test_icon_applied" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    agent_name          = "test-agent"
    module_directory    = ".test-module"
    icon                = "/icon/claude.svg"
    pre_install_script  = "echo 'pre-install'"
    install_script      = "echo 'install'"
    post_install_script = "echo 'post-install'"
    start_script        = "echo 'start'"
  }

  assert {
    condition     = coder_script.pre_install_script[0].icon == "/icon/claude.svg"
    error_message = "Pre-install script icon should match input"
  }

  assert {
    condition     = coder_script.install_script.icon == "/icon/claude.svg"
    error_message = "Install script icon should match input"
  }

  assert {
    condition     = coder_script.post_install_script[0].icon == "/icon/claude.svg"
    error_message = "Post-install script icon should match input"
  }

  assert {
    condition     = coder_script.start_script[0].icon == "/icon/claude.svg"
    error_message = "Start script icon should match input"
  }
}

# Verify optional scripts are not created when their variables are unset
run "test_optional_scripts_absent_by_default" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    agent_name       = "test-agent"
    module_directory = ".test-module"
    install_script   = "echo install"
  }

  assert {
    condition     = length(coder_script.pre_install_script) == 0
    error_message = "Pre-install coder_script should not be created when pre_install_script is unset"
  }

  assert {
    condition     = length(coder_script.post_install_script) == 0
    error_message = "Post-install coder_script should not be created when post_install_script is unset"
  }

  assert {
    condition     = length(coder_script.start_script) == 0
    error_message = "Start coder_script should not be created when start_script is unset"
  }
}

# Verify `scripts` output is a filtered, run-order list
run "test_scripts_output_with_all" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    agent_name          = "test-agent"
    module_directory    = ".test-module"
    pre_install_script  = "echo pre"
    install_script      = "echo install"
    post_install_script = "echo post"
    start_script        = "echo start"
  }

  assert {
    condition     = length(output.scripts) == 4
    error_message = "scripts should have 4 entries when every script is set"
  }

  assert {
    condition     = output.scripts[0] == "test-agent-pre_install_script"
    error_message = "scripts[0] must be the pre-install name"
  }

  assert {
    condition     = output.scripts[1] == "test-agent-install_script"
    error_message = "scripts[1] must be the install name"
  }

  assert {
    condition     = output.scripts[2] == "test-agent-post_install_script"
    error_message = "scripts[2] must be the post-install name"
  }

  assert {
    condition     = output.scripts[3] == "test-agent-start_script"
    error_message = "scripts[3] must be the start name"
  }
}

run "test_scripts_output_with_install_only" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    agent_name       = "test-agent"
    module_directory = ".test-module"
    install_script   = "echo install"
  }

  assert {
    condition     = length(output.scripts) == 1
    error_message = "scripts should have exactly 1 entry (install) when pre/post/start are unset"
  }

  assert {
    condition     = output.scripts[0] == "test-agent-install_script"
    error_message = "scripts[0] must be the install name"
  }
}

run "test_scripts_output_with_install_and_post" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    agent_name          = "test-agent"
    module_directory    = ".test-module"
    install_script      = "echo install"
    post_install_script = "echo post"
  }

  assert {
    condition     = length(output.scripts) == 2
    error_message = "scripts should have 2 entries (install, post)"
  }

  assert {
    condition     = output.scripts[0] == "test-agent-install_script"
    error_message = "scripts[0] must be the install name"
  }

  assert {
    condition     = output.scripts[1] == "test-agent-post_install_script"
    error_message = "scripts[1] must be the post-install name"
  }
}

# Every script must stream combined stdout+stderr to both the agent log
# (via stdout) and the on-disk log file (via tee), so workspace users
# watching `coder_script` output in the UI see progress live and can
# read the same content from the log file after the fact.
run "test_scripts_tee_stdout_and_log_file" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    agent_name          = "test-agent"
    module_directory    = ".test-module"
    pre_install_script  = "echo pre"
    install_script      = "echo install"
    post_install_script = "echo post"
    start_script        = "echo start"
  }

  assert {
    condition     = can(regex("pre_install.sh 2>&1 \\| tee .*pre_install.log", coder_script.pre_install_script[0].script))
    error_message = "pre_install wrapper must tee combined output to the log file and stdout"
  }

  assert {
    condition     = can(regex("install.sh 2>&1 \\| tee .*install.log", coder_script.install_script.script))
    error_message = "install wrapper must tee combined output to the log file and stdout"
  }

  assert {
    condition     = can(regex("post_install.sh 2>&1 \\| tee .*post_install.log", coder_script.post_install_script[0].script))
    error_message = "post_install wrapper must tee combined output to the log file and stdout"
  }

  assert {
    condition     = can(regex("start.sh 2>&1 \\| tee .*start.log", coder_script.start_script[0].script))
    error_message = "start wrapper must tee combined output to the log file and stdout"
  }
}
