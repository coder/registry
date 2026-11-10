mock_provider "coder" {}

variables {
  agent_id             = "test-agent"
  web_app_icon         = "/icon/test.svg"
  web_app_display_name = "Test"
  web_app_slug         = "test"
  cli_app_display_name = "Test CLI"
  cli_app_slug         = "test-cli"
  start_script         = "echo test"
  module_dir_name      = ".test-module"
}

run "default_values" {
  command = plan

  assert {
    condition     = var.enable_state_persistence == false
    error_message = "enable_state_persistence should default to false"
  }

  assert {
    condition     = var.state_file_path == ""
    error_message = "state_file_path should default to empty string"
  }

  assert {
    condition     = var.pid_file_path == ""
    error_message = "pid_file_path should default to empty string"
  }

  # Verify start script contains state persistence ARG_ vars.
  assert {
    condition     = can(regex("ARG_ENABLE_STATE_PERSISTENCE", coder_script.agentapi.script))
    error_message = "start script should contain ARG_ENABLE_STATE_PERSISTENCE"
  }

  assert {
    condition     = can(regex("ARG_STATE_FILE_PATH", coder_script.agentapi.script))
    error_message = "start script should contain ARG_STATE_FILE_PATH"
  }

  assert {
    condition     = can(regex("ARG_PID_FILE_PATH", coder_script.agentapi.script))
    error_message = "start script should contain ARG_PID_FILE_PATH"
  }

  # Verify shutdown script contains PID-related ARG_ vars.
  assert {
    condition     = can(regex("ARG_PID_FILE_PATH", coder_script.agentapi_shutdown.script))
    error_message = "shutdown script should contain ARG_PID_FILE_PATH"
  }

  assert {
    condition     = can(regex("ARG_MODULE_DIR_NAME", coder_script.agentapi_shutdown.script))
    error_message = "shutdown script should contain ARG_MODULE_DIR_NAME"
  }

  assert {
    condition     = can(regex("ARG_ENABLE_STATE_PERSISTENCE", coder_script.agentapi_shutdown.script))
    error_message = "shutdown script should contain ARG_ENABLE_STATE_PERSISTENCE"
  }
}

run "state_persistence_disabled" {
  command = plan

  variables {
    enable_state_persistence = false
  }

  assert {
    condition     = var.enable_state_persistence == false
    error_message = "enable_state_persistence should be false"
  }

  # Even when disabled, the ARG_ vars should still be in the script
  # (the shell script handles the conditional logic).
  assert {
    condition     = can(regex("ARG_ENABLE_STATE_PERSISTENCE='false'", coder_script.agentapi.script))
    error_message = "start script should contain ARG_ENABLE_STATE_PERSISTENCE='false'"
  }
}

run "custom_paths" {
  command = plan

  variables {
    state_file_path = "/custom/state.json"
    pid_file_path   = "/custom/agentapi.pid"
  }

  assert {
    condition     = can(regex("/custom/state.json", coder_script.agentapi.script))
    error_message = "start script should contain custom state_file_path"
  }

  assert {
    condition     = can(regex("/custom/agentapi.pid", coder_script.agentapi.script))
    error_message = "start script should contain custom pid_file_path"
  }

  # Verify custom paths also appear in shutdown script.
  assert {
    condition     = can(regex("/custom/agentapi.pid", coder_script.agentapi_shutdown.script))
    error_message = "shutdown script should contain custom pid_file_path"
  }
}
