mock_provider "coder" {}

variables {
  agent_id             = "test-agent"
  web_app_icon         = "/icon/test.svg"
  web_app_display_name = "Test"
  web_app_slug         = "test"
  cli_app_display_name = "Test CLI"
  cli_app_slug         = "test-cli"
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

  # Verify shutdown script contains PID-related ARG_ vars.
  assert {
    condition     = can(regex("ARG_PID_FILE_PATH", coder_script.agentapi_shutdown.script))
    error_message = "shutdown script should contain ARG_PID_FILE_PATH"
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

  # Verify shutdown script contains the disabled flag.
  assert {
    condition     = can(regex("ARG_ENABLE_STATE_PERSISTENCE='false'", coder_script.agentapi_shutdown.script))
    error_message = "shutdown script should contain ARG_ENABLE_STATE_PERSISTENCE='false'"
  }
}

run "custom_paths" {
  command = plan

  variables {
    state_file_path = "/custom/state.json"
    pid_file_path   = "/custom/agentapi.pid"
  }

  # Verify custom paths appear in shutdown script.
  assert {
    condition     = can(regex("/custom/agentapi.pid", coder_script.agentapi_shutdown.script))
    error_message = "shutdown script should contain custom pid_file_path"
  }
}

run "scripts_output" {
  command = plan

  assert {
    condition     = length(output.scripts) == 1 && output.scripts[0] == "coder-agentapi-install_script"
    error_message = "scripts output should list the install script sync name"
  }
}
