# Terraform tests for the parameter contract and the rendered runner
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
    condition     = data.coder_parameter.agent_relay_claude_code_lock_to_account.name == "agent_relay_claude_code_lock_to_account"
    error_message = "account lock parameter name is part of the Agent Relay contract"
  }

  assert {
    condition     = data.coder_parameter.agent_relay_attempt.name == "agent_relay_attempt"
    error_message = "attempt parameter name is part of the Agent Relay contract"
  }

  # The relay reads these back off a build long after dispatch, so they
  # must not be ephemeral; the rest must be, so a manual build never
  # inherits a stale credential, account lock, or attempt.
  assert {
    condition = alltrue([
      data.coder_parameter.agent_relay_session_id.ephemeral == false,
      data.coder_parameter.agent_relay_delivery_id.ephemeral == false,
      data.coder_parameter.agent_relay_pool.ephemeral == false,
      data.coder_parameter.agent_relay_credential.ephemeral == true,
      data.coder_parameter.agent_relay_claude_code_lock_to_account.ephemeral == true,
      data.coder_parameter.agent_relay_attempt.ephemeral == true,
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
        data.coder_parameter.agent_relay_credential.styling,
        data.coder_parameter.agent_relay_claude_code_lock_to_account.styling,
        data.coder_parameter.agent_relay_attempt.styling,
      ] : can(regex("\"disabled\":true", p))
    ])
    error_message = "every relay parameter must render disabled"
  }

  assert {
    condition     = can(regex("\"mask_input\":true", data.coder_parameter.agent_relay_credential.styling))
    error_message = "the credential must be masked"
  }
}

run "runner_wiring" {
  command = plan

  # The claude CLI owns these names; the module only supplies values.
  assert {
    condition     = coder_env.runner_pool_secret.name == "SELF_HOSTED_RUNNER_POOL_SECRET"
    error_message = "the pool secret env var name is the claude CLI's contract"
  }

  assert {
    condition     = coder_env.agent_relay_claude_code_lock_to_account.name == "SELF_HOSTED_RUNNER_LOCK_TO_ACCOUNT"
    error_message = "the account lock env var name is the claude CLI's contract"
  }

  assert {
    condition     = coder_script.runner.run_on_start
    error_message = "the runner script must run when the agent starts"
  }

  assert {
    condition     = can(regex("self-hosted-runner", coder_script.runner.script))
    error_message = "the runner script must start the self-hosted runner"
  }

  # Reaping reads this file through the agent_relay_status metadata item,
  # so the script and the metadata script must agree on the path.
  assert {
    condition     = can(regex(var.state_file, coder_script.runner.script)) && can(regex(var.state_file, output.status_metadata_script))
    error_message = "the runner script and the status script must read the same state file"
  }

  assert {
    condition     = can(regex("failed runner-agent-missing", coder_script.runner.script))
    error_message = "the missing-binary reason is the vocabulary the reaper grades"
  }

  assert {
    condition     = output.dispatched == false
    error_message = "a build with no credential was not dispatched by Agent Relay"
  }
}

run "install_cli_enabled_by_default" {
  command = plan

  # A CLI already in the image must short-circuit the download, so a
  # prepared image spends none of the claim-to-ready window on it.
  assert {
    condition     = can(regex("if command -v claude >/dev/null 2>&1; then\n\techo \"Claude Code CLI already present", coder_script.runner.script))
    error_message = "the installer must be guarded by a presence check"
  }

  # Without -L the installer redirects, curl writes nothing, and the pipe
  # to bash silently installs nothing.
  assert {
    condition     = can(regex("curl https://claude.ai/install.sh -fsSL \\| bash", coder_script.runner.script))
    error_message = "the installer must follow redirects"
  }
}

run "install_cli_disabled" {
  command = plan

  variables {
    install_cli = false
  }

  assert {
    condition     = !can(regex("claude.ai/install.sh", coder_script.runner.script))
    error_message = "install_cli = false must not download the CLI"
  }
}

run "overridden_paths" {
  command = plan

  variables {
    cli_binary          = "/opt/claude/claude"
    state_file          = "/var/run/relay/state"
    log_file            = "/var/log/relay.log"
    serving_log_pattern = "custom pattern"
  }

  assert {
    condition     = can(regex("/opt/claude/claude self-hosted-runner", coder_script.runner.script))
    error_message = "cli_binary must select the binary the runner starts"
  }

  assert {
    condition     = can(regex("custom pattern", output.status_metadata_script)) && can(regex("/var/log/relay.log", output.status_metadata_script))
    error_message = "the status script must use the configured pattern and log file"
  }
}
