# Terraform tests for the parameter contract and the rendered worker
# script. Run with `terraform init && terraform test` in this directory.

variables {
  agent_id = "00000000-0000-0000-0000-000000000000"
}

run "parameter_contract" {
  command = plan

  assert {
    condition     = data.coder_parameter.agent_relay_session_id.name == "agent_relay_session_id"
    error_message = "session id parameter name is part of the Agent Relay contract"
  }

  assert {
    condition     = data.coder_parameter.agent_relay_delivery_id.name == "agent_relay_delivery_id"
    error_message = "delivery id parameter name is part of the Agent Relay contract"
  }

  assert {
    condition     = data.coder_parameter.agent_relay_pool.name == "agent_relay_pool"
    error_message = "pool parameter name is part of the Agent Relay contract"
  }

  assert {
    condition     = data.coder_parameter.agent_relay_credential.name == "agent_relay_credential"
    error_message = "credential parameter name is part of the Agent Relay contract"
  }

  assert {
    condition     = data.coder_parameter.agent_relay_cursor_pool_name.name == "agent_relay_cursor_pool_name"
    error_message = "Cursor pool parameter name is part of the Agent Relay contract"
  }

  assert {
    condition     = data.coder_parameter.agent_relay_cursor_repo_url.name == "agent_relay_cursor_repo_url"
    error_message = "Cursor repository parameter name is part of the Agent Relay contract"
  }

  assert {
    condition     = data.coder_parameter.agent_relay_cursor_idle_release_timeout.name == "agent_relay_cursor_idle_release_timeout"
    error_message = "Cursor idle release timeout parameter name is part of the Agent Relay contract"
  }

  # Only the credential is ephemeral: the rest are queried back off the
  # workspace with `param:` filters, which only sees declared values.
  assert {
    condition = alltrue([
      data.coder_parameter.agent_relay_session_id.ephemeral == false,
      data.coder_parameter.agent_relay_delivery_id.ephemeral == false,
      data.coder_parameter.agent_relay_pool.ephemeral == false,
      data.coder_parameter.agent_relay_cursor_pool_name.ephemeral == false,
      data.coder_parameter.agent_relay_cursor_repo_url.ephemeral == false,
      data.coder_parameter.agent_relay_cursor_idle_release_timeout.ephemeral == false,
      data.coder_parameter.agent_relay_credential.ephemeral == true,
    ])
    error_message = "parameter persistence does not match the Agent Relay contract"
  }

  # Cosmetic, but the point of it is that a human opening the create form
  # cannot type into a machine-set field.
  assert {
    condition = alltrue([
      for p in [
        data.coder_parameter.agent_relay_session_id.styling,
        data.coder_parameter.agent_relay_delivery_id.styling,
        data.coder_parameter.agent_relay_pool.styling,
        data.coder_parameter.agent_relay_cursor_pool_name.styling,
        data.coder_parameter.agent_relay_cursor_repo_url.styling,
        data.coder_parameter.agent_relay_cursor_idle_release_timeout.styling,
        data.coder_parameter.agent_relay_credential.styling,
      ] : can(regex("\"disabled\":true", p))
    ])
    error_message = "every relay parameter must render disabled"
  }

  assert {
    condition     = can(regex("\"mask_input\":true", data.coder_parameter.agent_relay_credential.styling))
    error_message = "the credential must be masked"
  }
}

run "worker_wiring" {
  command = plan

  # The Cursor CLI owns these names; the module only supplies values.
  assert {
    condition     = coder_env.cursor_api_key.name == "CURSOR_API_KEY"
    error_message = "the API key env var name is the Cursor CLI's contract"
  }

  assert {
    condition     = coder_env.cursor_agent_worker_id.name == "CURSOR_AGENT_WORKER_ID"
    error_message = "the worker id env var name is the Cursor CLI's contract"
  }

  assert {
    condition     = coder_script.worker.run_on_start
    error_message = "the worker script must run when the agent starts"
  }

  assert {
    condition     = can(regex("--pool", coder_script.worker.script)) && can(regex("--idle-release-timeout", coder_script.worker.script))
    error_message = "the worker script must start the pool worker"
  }

  # Reaping reads this file through the agent_relay_status metadata item,
  # so the script and the metadata script must agree on the path.
  assert {
    condition     = can(regex(var.state_file, coder_script.worker.script)) && can(regex(var.state_file, output.status_metadata_script))
    error_message = "the worker script and the status script must read the same state file"
  }

  assert {
    condition     = can(regex("failed runner-agent-missing", coder_script.worker.script))
    error_message = "the missing-binary reason is the vocabulary the reaper grades"
  }

  assert {
    condition     = output.dispatched == false
    error_message = "a build with no credential was not dispatched by Agent Relay"
  }
}

run "computer_use_off_by_default" {
  command = plan

  assert {
    condition     = !can(regex("--computer-use", coder_script.worker.script))
    error_message = "computer use requires packages the image may not carry, so it must be opt in"
  }
}

run "computer_use_enabled" {
  command = plan

  variables {
    computer_use = true
  }

  assert {
    condition     = can(regex("--computer-use", coder_script.worker.script))
    error_message = "computer_use = true must pass the flag to the worker"
  }
}

run "install_cli_enabled_by_default" {
  command = plan

  # A CLI already in the image must short-circuit the download, so a
  # prepared image spends none of the claim-to-ready window on it.
  assert {
    condition     = can(regex("if command -v agent >/dev/null 2>&1; then\n\techo \"Cursor CLI already present", coder_script.worker.script))
    error_message = "the installer must be guarded by a presence check"
  }

  assert {
    condition     = can(regex("curl https://cursor.com/install -fsSL \\| bash", coder_script.worker.script))
    error_message = "the installer must follow redirects"
  }
}

run "install_cli_disabled" {
  command = plan

  variables {
    install_cli = false
  }

  assert {
    condition     = !can(regex("cursor.com/install", coder_script.worker.script))
    error_message = "install_cli = false must not download the CLI"
  }
}

run "overridden_paths" {
  command = plan

  variables {
    cli_binary          = "/opt/cursor/agent"
    state_file          = "/var/run/relay/state"
    log_file            = "/var/log/relay.log"
    serving_log_pattern = "custom pattern"
  }

  assert {
    condition     = can(regex("/opt/cursor/agent worker", coder_script.worker.script))
    error_message = "cli_binary must select the binary the worker starts"
  }

  assert {
    condition     = can(regex("custom pattern", output.status_metadata_script)) && can(regex("/var/log/relay.log", output.status_metadata_script))
    error_message = "the status script must use the configured pattern and log file"
  }
}
