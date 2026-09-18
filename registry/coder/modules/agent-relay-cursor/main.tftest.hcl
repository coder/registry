# Terraform tests for the parameter contract and the rendered install and
# start scripts. Run with `terraform init && terraform test` in this
# directory. The scripts are handed to coder-utils, whose coder_script
# resources a test cannot reach, so assertions read the rendered locals.

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

  # The Cursor CLI owns the worker id name; the token has no CLI env var
  # and must not masquerade as CURSOR_API_KEY.
  assert {
    condition     = coder_env.agent_relay_cursor_token.name == "AGENT_RELAY_CURSOR_TOKEN"
    error_message = "the worker token env var is Agent Relay's, not a Cursor API key"
  }

  assert {
    condition     = coder_env.cursor_agent_worker_id.name == "CURSOR_AGENT_WORKER_ID"
    error_message = "the worker id env var name is the Cursor CLI's contract"
  }

  # coder-utils runs the install step before the start step and keeps
  # both scripts and their logs under this directory.
  assert {
    condition     = module.coder_utils.scripts == ["coder-agent-relay-cursor-install_script", "coder-agent-relay-cursor-start_script"]
    error_message = "coder-utils must run exactly the install and start steps, in that order"
  }

  # Pass-through so a template can serialize its own scripts behind ours.
  assert {
    condition     = output.scripts == module.coder_utils.scripts
    error_message = "the scripts output must re-export coder-utils' sync names"
  }

  # Everything a debugger needs lives under the coder-utils module
  # directory by default: scripts, their logs, worker state, worker log.
  assert {
    condition     = strcontains(local.start_script, "supervisor=\"$scripts_dir/supervise.sh\"") && strcontains(local.start_script, "scripts_dir=\"${local.module_directory}/scripts\"")
    error_message = "the supervisor must be written under module_directory/scripts, independent of state_file"
  }

  assert {
    condition     = startswith(var.state_file, local.module_directory) && startswith(var.log_file, local.module_directory)
    error_message = "worker state and log must default to the coder-utils module directory"
  }

  assert {
    condition     = can(regex("--pool", local.start_script)) && can(regex("--idle-release-timeout", local.start_script))
    error_message = "the worker script must start the pool worker"
  }

  # Pool name and idle timeout are parameter values, so they travel through
  # coder_env and are read from the environment, never interpolated into
  # the script where shell metacharacters would run as code.
  assert {
    condition     = coder_env.agent_relay_cursor_pool_name.name == "AGENT_RELAY_CURSOR_POOL_NAME" && coder_env.agent_relay_cursor_idle_release_timeout.name == "AGENT_RELAY_CURSOR_IDLE_RELEASE_TIMEOUT"
    error_message = "pool name and idle timeout must reach the worker through coder_env"
  }

  assert {
    condition     = strcontains(local.start_script, "--pool \"\\$AGENT_RELAY_CURSOR_POOL_NAME\"") && strcontains(local.start_script, "--idle-release-timeout \"\\$AGENT_RELAY_CURSOR_IDLE_RELEASE_TIMEOUT\"")
    error_message = "the worker must read pool name and idle timeout from the environment at run time"
  }

  # The token reaches the worker as --auth-token from the supervisor's
  # environment; it must not be expanded into the supervisor file the
  # script writes to disk.
  assert {
    condition     = strcontains(local.start_script, "--auth-token \"\\$AGENT_RELAY_CURSOR_TOKEN\"")
    error_message = "the worker must authenticate with --auth-token read from the environment at run time"
  }

  # Reaping reads this file through the agent_relay_status metadata item,
  # so the script and the metadata script must agree on the path.
  assert {
    condition     = strcontains(local.start_script, var.state_file) && strcontains(output.status_metadata_script, var.state_file)
    error_message = "the worker script and the status script must read the same state file"
  }

  # A restart inside the same build must not report the previous run's
  # state as this run's, nor launch a second worker beside a live one.
  assert {
    condition     = strcontains(local.start_script, "write_state \"pending\"") && strcontains(local.start_script, "worker_alive") && strcontains(output.status_metadata_script, "worker_alive")
    error_message = "the start script must reset to pending and both scripts must check worker liveness by cmdline"
  }

  assert {
    condition     = can(regex("failed runner-agent-missing", local.start_script))
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
    condition     = !can(regex("--computer-use", local.start_script))
    error_message = "computer use requires packages the image may not carry, so it must be opt in"
  }
}

run "computer_use_enabled" {
  command = plan

  variables {
    computer_use = true
  }

  assert {
    condition     = can(regex("--computer-use", local.start_script))
    error_message = "computer_use = true must pass the flag to the worker"
  }
}

run "install_cli_enabled_by_default" {
  command = plan

  # A CLI already in the image must short-circuit the download, so a
  # prepared image spends none of the claim-to-ready window on it.
  assert {
    condition     = can(regex("if command -v agent >/dev/null 2>&1; then\n\techo \"Cursor CLI already present", local.install_script))
    error_message = "the installer must be guarded by a presence check"
  }

  assert {
    condition     = can(regex("curl https://cursor.com/install -fsSL \\| bash", local.install_script))
    error_message = "the installer must follow redirects"
  }

  # The start step must not download; that is the install step's job.
  assert {
    condition     = !can(regex("cursor.com/install", local.start_script))
    error_message = "the start script must not install the CLI"
  }
}

run "install_cli_disabled" {
  command = plan

  variables {
    install_cli = false
  }

  assert {
    condition     = !can(regex("cursor.com/install", local.install_script))
    error_message = "install_cli = false must not download the CLI"
  }

  # A bring-your-own CLI at ~/.local/bin, the official installer's
  # location, must still be found by the start step and the supervisor.
  assert {
    condition     = length(regexall("export PATH=\"\\\\?\\$HOME/.local/bin", local.start_script)) == 2
    error_message = "the start script and supervisor must add ~/.local/bin to PATH even when install_cli is false"
  }
}

run "cli_binary_rejects_shell" {
  command = plan

  variables {
    cli_binary = "claude\"; touch /tmp/PWNED; \""
  }

  # cli_binary is rendered as a command word in two scripts, so anything
  # beyond a name or path is refused at plan time.
  expect_failures = [var.cli_binary]
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
    condition     = can(regex("/opt/cursor/agent worker", local.start_script))
    error_message = "cli_binary must select the binary the worker starts"
  }

  assert {
    condition     = strcontains(output.status_metadata_script, base64encode("custom pattern")) && !strcontains(output.status_metadata_script, "custom pattern") && can(regex("/var/log/relay.log", output.status_metadata_script))
    error_message = "the status script must use the configured log file and carry the pattern base64-encoded only"
  }
}

run "serving_log_pattern_is_data" {
  command = plan

  variables {
    serving_log_pattern = "x\"; touch /tmp/PWNED; \""
  }

  # Free-form text never lands in the script as shell; it is decoded into
  # a variable and matched as a fixed string.
  assert {
    condition     = !strcontains(output.status_metadata_script, "PWNED") && strcontains(output.status_metadata_script, "grep -qF -- \"$serving_log_pattern\"")
    error_message = "serving_log_pattern must be base64-encoded and matched with grep -F"
  }
}
