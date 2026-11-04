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
    condition     = data.coder_parameter.agent_relay_claude_code_lock_to_account.name == "agent_relay_claude_code_lock_to_account"
    error_message = "account lock parameter name is part of the Agent Relay contract"
  }

  assert {
    condition     = data.coder_parameter.agent_relay_attempt.name == "agent_relay_attempt"
    error_message = "attempt parameter name is part of the Agent Relay contract"
  }

  assert {
    condition     = data.coder_parameter.agent_relay_client_platform.name == "agent_relay_client_platform"
    error_message = "client platform parameter name is what Agent Relay stamps"
  }

  assert {
    condition     = data.coder_parameter.agent_relay_claude_code_release_idle_session_min.name == "agent_relay_claude_code_release_idle_session_min"
    error_message = "idle session release parameter name is what Agent Relay stamps"
  }

  # The relay reads these back off a build long after dispatch, so they
  # must not be ephemeral; the rest must be, so a manual build never
  # inherits a stale account lock or attempt.
  assert {
    condition = alltrue([
      data.coder_parameter.agent_relay_session_id.ephemeral == false,
      data.coder_parameter.agent_relay_delivery_id.ephemeral == false,
      data.coder_parameter.agent_relay_pool.ephemeral == false,
      data.coder_parameter.agent_relay_client_platform.ephemeral == false,
      data.coder_parameter.agent_relay_claude_code_release_idle_session_min.ephemeral == false,
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
        data.coder_parameter.agent_relay_client_platform.styling,
        data.coder_parameter.agent_relay_claude_code_release_idle_session_min.styling,
        data.coder_parameter.agent_relay_claude_code_lock_to_account.styling,
        data.coder_parameter.agent_relay_attempt.styling,
      ] : can(regex("\"disabled\":true", p))
    ])
    error_message = "every relay parameter must render disabled"
  }
}

run "runner_wiring" {
  command = plan

  # The claude CLI owns these names; the module only supplies values.
  assert {
    condition     = coder_env.agent_relay_claude_code_lock_to_account.name == "SELF_HOSTED_RUNNER_LOCK_TO_ACCOUNT"
    error_message = "the account lock env var name is the claude CLI's contract"
  }

  # coder-utils runs cleanup before install, then start, and keeps
  # scripts and their logs under the module directory.
  assert {
    condition     = module.coder_utils.scripts == ["coder-agent-relay-claude-code-pre_install_script", "coder-agent-relay-claude-code-install_script", "coder-agent-relay-claude-code-start_script"]
    error_message = "coder-utils must clean up before install and start"
  }

  assert {
    condition     = strcontains(local.cleanup_script, var.state_file) && strcontains(local.shutdown_script, var.state_file)
    error_message = "startup, shutdown, and status must use the configured state file"
  }

  assert {
    condition     = coder_script.shutdown.run_on_stop && !coder_script.shutdown.run_on_start && coder_script.shutdown.script == local.shutdown_script
    error_message = "shutdown must run only on stop and use the shared cleanup source"
  }

  # Pass-through so a template can serialize its own scripts behind ours.
  assert {
    condition     = output.scripts == module.coder_utils.scripts
    error_message = "the scripts output must re-export coder-utils' sync names"
  }

  assert {
    condition     = can(regex("self-hosted-runner", local.start_script))
    error_message = "the start script must start the self-hosted runner"
  }

  # A dispatched workspace that never receives its session must not sit
  # in working forever; the runner exits on its own and the relay reaps.
  # ~/.claude is snapshotted into every session's config dir, so the
  # wrapper must live beside the supervisor instead.
  assert {
    condition     = !strcontains(local.start_script, ".claude/wrapper.sh") && strcontains(local.start_script, "--exec-path \"$wrapper\"")
    error_message = "the wrapper must not be written under ~/.claude"
  }

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
    error_message = "a build with no delivery was not dispatched by Agent Relay"
  }
}

run "dispatched_true_when_delivery_stamped" {
  command = plan

  # The delivery id is not ephemeral, so a person's restart carries it into
  # the next build and this output stays true for the life of a relay-created
  # workspace. The start script, not this output, says whether the current
  # build has a work order.
  override_data {
    target = data.coder_parameter.agent_relay_delivery_id
    values = {
      value = "0d6c3b1e-delivery"
    }
  }

  assert {
    condition     = output.dispatched == true
    error_message = "a build carrying a delivery id belongs to a workspace Agent Relay created"
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

run "additional_args_default_empty" {
  command = plan

  assert {
    condition     = strcontains(local.start_script, "done < <(echo -n '' | base64 -d)")
    error_message = "additional_args must default to empty"
  }
}

run "additional_args_encoded" {
  command = plan

  variables {
    additional_args = ["--header", "it's here", "--header", "b", "--verbose"]
  }

  # Base64 keeps quotes in an argument from breaking the rendered script.
  assert {
    condition     = strcontains(local.start_script, base64encode("--header\nit's here\n--header\nb\n--verbose")) && !strcontains(local.start_script, "it's here")
    error_message = "additional_args must be base64-encoded into the start script, one argument per line, in order"
  }
}

run "additional_args_rejects_newline" {
  command = plan

  variables {
    additional_args = ["--verbose\n--capacity"]
  }

  expect_failures = [var.additional_args]
}

run "additional_args_rejects_module_flags" {
  command = plan

  variables {
    additional_args = ["--capacity=2"]
  }

  expect_failures = [var.additional_args]
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
    base_dir            = "/srv/sessions"
    serving_log_pattern = "custom pattern"
  }

  assert {
    condition     = can(regex("/opt/claude/claude self-hosted-runner", local.start_script))
    error_message = "cli_binary must select the binary the runner starts"
  }

  # The CLI defaults to /workspace, which a plain image lacks and the
  # agent user cannot create, so the module always passes and creates
  # its own.
  assert {
    condition     = strcontains(local.start_script, "base_dir=\"/srv/sessions\"") && strcontains(local.start_script, "--base-dir \"$base_dir\"")
    error_message = "the runner must be started with the configured base_dir"
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

run "health_port_default" {
  command = plan

  # Not the CLI's 8080, which a template image is likely to use already.
  # Passed explicitly so the URL the attachment script reads always matches
  # the port the runner binds.
  assert {
    condition     = strcontains(local.start_script, "--health-port 3286") && output.health_url == "http://127.0.0.1:3286"
    error_message = "the runner must serve /healthz on 3286 by default, not the CLI's 8080"
  }

  assert {
    condition     = strcontains(output.session_attached_metadata_script, "health_url=\"http://127.0.0.1:3286\"") && strcontains(output.session_attached_metadata_script, var.state_file)
    error_message = "the attachment script must read the runner's listener and state file"
  }
}

run "health_port_overridden" {
  command = plan

  variables {
    health_port = 3290
  }

  assert {
    condition     = strcontains(local.start_script, "--health-port 3290") && output.health_url == "http://127.0.0.1:3290" && strcontains(output.session_attached_metadata_script, "http://127.0.0.1:3290")
    error_message = "health_port must select the port the runner binds and the attachment script reads"
  }
}

run "health_port_disabled" {
  command = plan

  variables {
    health_port = 0
  }

  # The CLI listens on 8080 unless told 0, so disabling must pass 0, and
  # the attachment script must say why it cannot observe a session.
  assert {
    condition     = strcontains(local.start_script, "--health-port 0") && output.health_url == "" && strcontains(output.session_attached_metadata_script, "health_url=\"\"")
    error_message = "health_port = 0 must disable the listener and the attachment probe"
  }
}

run "health_port_rejects_out_of_range" {
  command = plan

  variables {
    health_port = 70000
  }

  expect_failures = [var.health_port]
}

run "additional_args_rejects_health_port" {
  command = plan

  variables {
    additional_args = ["--health-port=9000"]
  }

  expect_failures = [var.additional_args]
}

run "release_idle_session_min_default" {
  command = plan

  # A relay that predates the parameter never stamps it, so its default is
  # what such a workspace runs with.
  assert {
    condition     = data.coder_parameter.agent_relay_claude_code_release_idle_session_min.default == "60" && data.coder_parameter.agent_relay_claude_code_release_idle_session_min.value == "60"
    error_message = "the idle session release parameter must default to 60 minutes"
  }

  assert {
    condition     = data.coder_parameter.agent_relay_claude_code_release_idle_session_min.type == "number" && data.coder_parameter.agent_relay_claude_code_release_idle_session_min.validation[0].min == 0 && data.coder_parameter.agent_relay_claude_code_release_idle_session_min.validation[0].max == 10080
    error_message = "the idle session release parameter must accept 0 to 10080, the CLI's bound"
  }

  assert {
    condition     = coder_env.agent_relay_claude_code_release_idle_session_min.name == "AGENT_RELAY_CLAUDE_CODE_RELEASE_IDLE_SESSION_MIN" && coder_env.agent_relay_claude_code_release_idle_session_min.value == "60"
    error_message = "the idle session release value must reach the start script through the environment"
  }

  # The supervisor reads the value at run time; it is never rendered as a
  # flag value into the script.
  assert {
    condition     = strcontains(local.start_script, "set -- --release-idle-session-min \"\\$AGENT_RELAY_CLAUDE_CODE_RELEASE_IDLE_SESSION_MIN\"") && !strcontains(local.start_script, "--release-idle-session-min 60")
    error_message = "the supervisor must pass --release-idle-session-min from the environment"
  }

  assert {
    condition     = strcontains(local.start_script, "AGENT_RELAY_CLAUDE_CODE_RELEASE_IDLE_SESSION_MIN:-60}") && strcontains(local.start_script, "failed invalid-release-idle-session-min")
    error_message = "the start script must fall back to the module default and refuse an invalid value"
  }
}

run "release_idle_session_min_overridden" {
  command = plan

  variables {
    release_idle_session_min = 15
  }

  assert {
    condition     = data.coder_parameter.agent_relay_claude_code_release_idle_session_min.default == "15" && coder_env.agent_relay_claude_code_release_idle_session_min.value == "15"
    error_message = "release_idle_session_min must set the parameter's default"
  }
}

run "release_idle_session_min_disabled" {
  command = plan

  variables {
    release_idle_session_min = 0
  }

  assert {
    condition     = data.coder_parameter.agent_relay_claude_code_release_idle_session_min.default == "0" && coder_env.agent_relay_claude_code_release_idle_session_min.value == "0"
    error_message = "release_idle_session_min = 0 must be a valid default"
  }
}

run "release_idle_session_min_stamped" {
  command = plan

  # What a relay stamp looks like: the parameter's value differs from the
  # module default, and the value is what the runner gets.
  override_data {
    target = data.coder_parameter.agent_relay_claude_code_release_idle_session_min
    values = {
      value = "30"
    }
  }

  assert {
    condition     = coder_env.agent_relay_claude_code_release_idle_session_min.value == "30"
    error_message = "a stamped parameter value must override the module default"
  }
}

run "release_idle_session_min_rejects_out_of_range" {
  command = plan

  variables {
    release_idle_session_min = 10081
  }

  expect_failures = [var.release_idle_session_min]
}

run "release_idle_session_min_rejects_fraction" {
  command = plan

  variables {
    release_idle_session_min = 1.5
  }

  expect_failures = [var.release_idle_session_min]
}

run "additional_args_rejects_release_idle_session_min" {
  command = plan

  variables {
    additional_args = ["--release-idle-session-min=5"]
  }

  expect_failures = [var.additional_args]
}
