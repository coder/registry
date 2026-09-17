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

  # coder-utils runs the install step before the start step and keeps
  # both scripts and their logs under this directory.
  assert {
    condition     = module.coder_utils.scripts == ["coder-agent-relay-claude-code-install_script", "coder-agent-relay-claude-code-start_script"]
    error_message = "coder-utils must run exactly the install and start steps, in that order"
  }

  assert {
    condition     = can(regex("self-hosted-runner", local.start_script))
    error_message = "the start script must start the self-hosted runner"
  }

  # A dispatched workspace that never receives its session must not sit
  # in working forever; the runner exits on its own and the relay reaps.
  assert {
    condition     = strcontains(local.start_script, "--exit-if-unused-min 10")
    error_message = "the runner must exit when never assigned work, 10 minutes by default"
  }

  # Reaping reads this file through the agent_relay_status metadata item,
  # so the start script and the metadata script must agree on the path.
  assert {
    condition     = strcontains(local.start_script, var.state_file) && strcontains(output.status_metadata_script, var.state_file)
    error_message = "the start script and the status script must read the same state file"
  }

  # Everything a debugger needs lives under the coder-utils module
  # directory by default: scripts, their logs, runner state, runner log.
  assert {
    condition     = startswith(var.state_file, local.module_directory) && startswith(var.log_file, local.module_directory)
    error_message = "runner state and log must default to the coder-utils module directory"
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

run "install_cli_enabled_by_default" {
  command = plan

  # A CLI already in the image must short-circuit the download, so a
  # prepared image spends none of the claim-to-ready window on it.
  assert {
    condition     = can(regex("if command -v claude >/dev/null 2>&1; then\n\techo \"Claude Code CLI already present", local.install_script))
    error_message = "the installer must be guarded by a presence check"
  }

  # Without -L the installer redirects, curl writes nothing, and the pipe
  # to bash silently installs nothing.
  assert {
    condition     = can(regex("curl https://claude.ai/install.sh -fsSL \\| bash", local.install_script))
    error_message = "the installer must follow redirects"
  }

  # The start step must not download; that is the install step's job.
  assert {
    condition     = !can(regex("claude.ai/install.sh", local.start_script))
    error_message = "the start script must not install the CLI"
  }
}

run "install_cli_disabled" {
  command = plan

  variables {
    install_cli = false
  }

  assert {
    condition     = !can(regex("claude.ai/install.sh", local.install_script))
    error_message = "install_cli = false must not download the CLI"
  }

  # A bring-your-own CLI at ~/.local/bin, the official installer's
  # location, must still be found by the start step and the supervisor.
  assert {
    condition     = length(regexall("export PATH=\"\\\\?\\$HOME/.local/bin", local.start_script)) == 2
    error_message = "the start script and supervisor must add ~/.local/bin to PATH even when install_cli is false"
  }
}

run "idle_bound_disabled" {
  command = plan

  variables {
    exit_if_unused_min = 0
  }

  assert {
    condition     = !strcontains(local.start_script, "--exit-if-unused-min")
    error_message = "exit_if_unused_min = 0 must leave the CLI default of never"
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
    cli_binary          = "/opt/claude/claude"
    state_file          = "/var/run/relay/state"
    log_file            = "/var/log/relay.log"
    serving_log_pattern = "custom pattern"
  }

  assert {
    condition     = can(regex("/opt/claude/claude self-hosted-runner", local.start_script))
    error_message = "cli_binary must select the binary the runner starts"
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
