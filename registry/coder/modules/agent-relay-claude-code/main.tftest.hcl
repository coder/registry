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
    condition     = coder_env.runner_environment_secret.name == "SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET"
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

  # The stop script reads the pid out of the same file the supervisor
  # writes it to, so an override must reach both.
  assert {
    condition     = strcontains(local.stop_script, "/var/run/relay/state")
    error_message = "the stop script must read the configured state file"
  }
}

run "untrusted_text_is_data" {
  command = plan

  variables {
    serving_log_pattern = "x\"; touch /tmp/PWNED; \""
    client_label        = "y\"; touch /tmp/PWNED; \""
  }

  # Free-form text never lands in a script as shell; it is decoded into
  # a variable and matched as a fixed string.
  assert {
    condition     = !strcontains(output.status_metadata_script, "PWNED") && strcontains(output.status_metadata_script, "grep -qF -- \"$serving_log_pattern\"")
    error_message = "serving_log_pattern must be base64-encoded and matched with grep -F"
  }

  assert {
    condition     = !strcontains(local.start_script, "PWNED") && strcontains(local.start_script, base64encode("y\"; touch /tmp/PWNED; \""))
    error_message = "client_label must cross into the supervisor base64-encoded"
  }
}

run "graceful_shutdown_defaults" {
  command = plan

  # The supervisor runs under setsid, so the agent's own SIGTERM never
  # reaches the runner. The stop script is the only thing that relays it.
  assert {
    condition     = coder_script.stop.run_on_stop == true && coder_script.stop.run_on_start == false
    error_message = "the stop script must run on stop and never on start"
  }

  assert {
    condition     = coder_script.stop.start_blocks_login == false
    error_message = "the stop script must never block login"
  }

  # SIGTERM starts the runner's own drain. Escalating would defeat it,
  # and the platform SIGKILLs soon enough on its own.
  assert {
    condition     = strcontains(local.stop_script, "kill -TERM") && !strcontains(local.stop_script, "kill -9") && !strcontains(local.stop_script, "-KILL")
    error_message = "the stop script must send SIGTERM only and never escalate"
  }

  # supervise.sh is the sole writer of terminal state; a second writer
  # would race the "done <code>" line the reaper grades.
  assert {
    condition     = !strcontains(local.stop_script, "state_file.tmp")
    error_message = "the stop script must not write the state file"
  }

  # 105 baseline + 30 for the outcome push, which is on by default.
  assert {
    condition     = output.shutdown_grace_seconds == 105
    error_message = "the default shutdown budget is the runner's 100s plus the agent's own shutdown"
  }

  # One number: the script's own wait must never outlive the grace the
  # template was asked to grant.
  assert {
    condition     = strcontains(local.stop_script, "budget=100")
    error_message = "the stop script must wait the runner budget, which is shutdown_grace_seconds minus the agent's own shutdown"
  }

  assert {
    condition     = !strcontains(local.start_script, "--push-outcome-on-release") && !strcontains(local.start_script, "--drain-wait-sec")
    error_message = "both optional runner behaviours are off by default"
  }

  # It rewrites the account's HOME git config before every session, so it
  # is never on unless the template asked for it.
  assert {
    condition     = !strcontains(local.start_script, "--use-anthropic-git-proxy") && !strcontains(local.start_script, "--configure-git")
    error_message = "Anthropic-managed git and the Claude git identity must both be opt-in"
  }
}

run "drain_wait_enabled" {
  command = plan

  variables {
    drain_wait_sec = 60
  }

  assert {
    condition     = strcontains(local.start_script, "--drain-wait-sec 60")
    error_message = "drain_wait_sec must reach the runner as a flag"
  }

  # Every second the runner may spend draining is a second the platform
  # must grant on top of the baseline.
  assert {
    condition     = output.shutdown_grace_seconds == 165 && strcontains(local.stop_script, "budget=160")
    error_message = "the drain wait must extend both the advertised budget and the script's own"
  }
}

run "push_outcome_enabled" {
  command = plan

  variables {
    push_outcome_on_release = true
  }

  assert {
    condition     = strcontains(local.start_script, "--push-outcome-on-release")
    error_message = "push_outcome_on_release must reach the runner as a flag"
  }

  # Pushing the outcome branch is 30s of extra shutdown work.
  assert {
    condition     = output.shutdown_grace_seconds == 135 && strcontains(local.stop_script, "budget=130")
    error_message = "the outcome push adds its 30s to both the budget and the script's wait"
  }
}

run "drain_wait_rejects_fraction" {
  command = plan

  variables {
    drain_wait_sec = 2.5
  }

  expect_failures = [var.drain_wait_sec]
}

run "client_label_defaults_to_owner_and_workspace" {
  command = plan

  # Display only: the console shows it beside the runner, and it never
  # steers which sessions this runner is assigned.
  assert {
    condition     = strcontains(local.start_script, "--client-label \"\\$client_label\"")
    error_message = "the runner must register with a client label"
  }

  assert {
    condition     = strcontains(local.start_script, base64encode("${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}"))
    error_message = "the default label identifies the workspace without the template setting a hostname"
  }
}

run "stop_script_guards_against_a_recycled_pid" {
  command = plan

  # This is the one caller that sends a signal, so a pid the supervisor
  # recorded and the OS has since handed to something else must not be
  # SIGTERMed.
  assert {
    condition     = strcontains(local.stop_script, "runner_alive") && strcontains(local.stop_script, "cmdline")
    error_message = "the stop script must confirm the pid is still our runner before signalling it"
  }

  assert {
    condition     = !strcontains(local.stop_script, "kill -0 \"$pid\"")
    error_message = "a bare kill -0 would trust a recycled pid"
  }

  # A bare basename matches any command line containing it, which is the
  # case the guard exists for.
  assert {
    condition     = strcontains(local.stop_script, "self-hosted-runner\"")
    error_message = "the pid guard must match the runner's argv, not just the binary name"
  }
}

run "stop_script_waits_for_the_recorded_exit" {
  command = plan

  # The supervisor is a separate process, so the runner's pid can vanish
  # before "done <code>" is written. Returning in that gap leaves the
  # state saying working with a dead pid, which reads as orphaned.
  assert {
    condition     = strcontains(local.stop_script, "recorded") && strcontains(local.stop_script, "while ! recorded")
    error_message = "the stop script must wait for the supervisor to record the exit, not just for the runner to go"
  }
}

run "anthropic_git_proxy_enabled" {
  command = plan

  variables {
    use_anthropic_git_proxy = true
  }

  assert {
    condition     = strcontains(local.start_script, "--use-anthropic-git-proxy")
    error_message = "use_anthropic_git_proxy must reach the runner as a flag"
  }

  # The proxy leaves no identity behind, so the two travel together
  # unless a template says otherwise.
  assert {
    condition     = strcontains(local.start_script, "--configure-git")
    error_message = "the Claude git identity must follow the proxy by default"
  }

  # It authenticates clones server-side; it does not change what the
  # runner has to do on the way out.
  assert {
    condition     = output.shutdown_grace_seconds == 105
    error_message = "Anthropic-managed git must not change the shutdown budget"
  }
}

run "git_identity_overrides_the_proxy_default" {
  command = plan

  variables {
    use_anthropic_git_proxy = true
    configure_git           = false
  }

  # For an image that supplies its identity in /etc/gitconfig, which the
  # proxy does not delete.
  assert {
    condition     = strcontains(local.start_script, "--use-anthropic-git-proxy") && !strcontains(local.start_script, "--configure-git")
    error_message = "configure_git = false must win over the proxy default"
  }
}

run "git_identity_without_the_proxy" {
  command = plan

  variables {
    configure_git = true
  }

  assert {
    condition     = strcontains(local.start_script, "--configure-git") && !strcontains(local.start_script, "--use-anthropic-git-proxy")
    error_message = "signing commits must not require Anthropic-managed git"
  }
}
