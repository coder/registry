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

  # coder-utils runs the cleanup before the install step, and the install
  # step before the start step, keeping scripts and logs under this
  # directory.
  assert {
    condition     = module.coder_utils.scripts == ["coder-agent-relay-cursor-pre_install_script", "coder-agent-relay-cursor-install_script", "coder-agent-relay-cursor-start_script"]
    error_message = "coder-utils must run exactly the pre-install, install, and start steps, in that order"
  }

  # The cleanup stops any previous supervisor and worker before a new
  # start. coder-utils starts the start step even when the pre-install
  # step failed, so the start step checks the marker only a finished
  # cleanup writes.
  assert {
    condition     = module.coder_utils.scripts[0] == "coder-agent-relay-cursor-pre_install_script" && strcontains(local.cleanup_script, "signal_pending TERM")
    error_message = "the cleanup must run as the coder-utils pre-install step"
  }

  assert {
    condition     = strcontains(local.cleanup_script, "cleanup_marker=\"${local.module_directory}/cleanup-complete\"\nrm -f \"$cleanup_marker\"") && strcontains(local.start_script, "cleanup_marker=\"${local.module_directory}/cleanup-complete\"") && strcontains(local.start_script, "not starting another")
    error_message = "the cleanup must remove its marker first, and the start step must refuse without it"
  }

  # The cleanup id travels as an argument, so a late start that runs a
  # newer start's supervisor script still checks its own id.
  assert {
    condition     = strcontains(local.start_script, "setsid nohup \"$supervisor\" \"$cleanup_id\"") && strcontains(local.start_script, "cleanup_id=\"\\$${1:-}\"") && strcontains(local.start_script, "= \"\\$cleanup_id\" ]") && strcontains(local.start_script, "mv \"$supervisor.$$.tmp\" \"$supervisor\"")
    error_message = "the supervisor must take the cleanup id as an argument and be replaced by rename"
  }

  # A supervisor from an older run must not overwrite a newer run's state
  # or delete its token.
  assert {
    condition     = strcontains(local.start_script, "write_state() {\n\tcurrent || return 0") && length(regexall("! current \\|\\| rm -f \"\\$token_file\"", local.start_script)) == 2
    error_message = "every supervisor state write and token removal must check the run is still current"
  }

  assert {
    condition     = strcontains(local.cleanup_script, "${local.module_directory}/supervisors") && strcontains(local.cleanup_script, "${local.module_directory}/workers") && strcontains(local.start_script, "supervisors=\"${local.module_directory}/supervisors\"") && strcontains(local.start_script, "workers=\"${local.module_directory}/workers\"")
    error_message = "the supervisor, worker, and cleanup must agree on the identity record directories"
  }

  # The worker records itself before it execs the CLI, so it stays tracked
  # if its supervisor is SIGKILLed.
  assert {
    condition     = strcontains(local.start_script, "publish \"\\$BASHPID\" \"$workers\" || exit 1\n\texec agent worker")
    error_message = "the worker must publish its own identity before exec'ing the CLI"
  }

  assert {
    condition     = strcontains(local.cleanup_script, "signal_pending TERM") && strcontains(local.cleanup_script, "signal_pending KILL")
    error_message = "the cleanup must escalate to SIGKILL for verified processes that ignore TERM"
  }

  assert {
    condition     = strcontains(local.cleanup_script, "/proc/sys/kernel/random/boot_id") && strcontains(local.start_script, "/proc/sys/kernel/random/boot_id")
    error_message = "supervisor identity must include the boot id so a pid from another boot is never signalled"
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

  # The token reaches the worker through a file, never on its command
  # line, and is not expanded into the supervisor file the script writes
  # to disk.
  assert {
    condition     = strcontains(local.start_script, "--auth-token-file \"$token_file\"") && !strcontains(local.start_script, "--auth-token ")
    error_message = "the worker must authenticate with --auth-token-file, not --auth-token"
  }

  # Reaping reads this file through the agent_relay_status metadata item,
  # so the scripts must agree on the path.
  assert {
    condition     = strcontains(local.start_script, var.state_file) && strcontains(local.cleanup_script, var.state_file) && strcontains(output.status_metadata_script, var.state_file)
    error_message = "the worker, cleanup, and status scripts must use the same state file"
  }

  # A restart inside the same build must not report the previous run's
  # state as this run's.
  assert {
    condition     = strcontains(local.start_script, "write_state \"pending\"") && strcontains(output.status_metadata_script, "worker_alive")
    error_message = "the start script must reset to pending and the status script must check worker liveness by cmdline"
  }

  assert {
    condition     = can(regex("failed runner-agent-missing", local.start_script))
    error_message = "the missing-binary reason is the vocabulary the reaper grades"
  }

  assert {
    condition     = output.dispatched == false
    error_message = "a build with no credential was not dispatched by Agent Relay"
  }

  assert {
    condition     = output.session_id == ""
    error_message = "a manual build has no Cursor cloud session id"
  }

  assert {
    condition     = length(coder_app.cursor_web) == 0 && length(coder_app.cursor_desktop) == 0
    error_message = "a manual build has no cloud agent, so neither Cursor client button is created"
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

  assert {
    condition     = !can(regex("--share-desktop", local.start_script))
    error_message = "desktop sharing must stay opt in"
  }
}

run "share_desktop_enabled" {
  command = plan

  variables {
    computer_use  = true
    share_desktop = true
  }

  assert {
    condition     = can(regex("--share-desktop=view_and_control", local.start_script))
    error_message = "share_desktop must pass an explicit mode, or the optional argument swallows start"
  }
}

run "share_desktop_requires_computer_use" {
  command = plan

  variables {
    share_desktop = true
  }

  expect_failures = [var.share_desktop]
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
    additional_args = ["--verbose\n--pool"]
  }

  expect_failures = [var.additional_args]
}

run "additional_args_rejects_module_flags" {
  command = plan

  variables {
    additional_args = ["--pool=2"]
  }

  expect_failures = [var.additional_args]
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

run "serving_log_pattern_rejects_empty" {
  command = plan

  variables {
    serving_log_pattern = ""
  }

  # An empty fixed-string pattern would match any log line and report
  # serving instead of degrading to working.
  expect_failures = [var.serving_log_pattern]
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
    condition     = strcontains(local.cleanup_script, "state_file=\"/var/run/relay/state\"")
    error_message = "the cleanup must clear the configured state file"
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

run "management_addr_default" {
  command = plan

  # Loopback by default: only the workspace's own scripts read it.
  assert {
    condition     = strcontains(local.start_script, "--management-addr \"127.0.0.1:3287\"") && output.management_url == "http://127.0.0.1:3287"
    error_message = "the worker must serve its management endpoints on 127.0.0.1:3287 by default"
  }

  assert {
    condition     = strcontains(output.session_attached_metadata_script, "management_url=\"http://127.0.0.1:3287\"") && strcontains(output.session_attached_metadata_script, var.state_file)
    error_message = "the attachment script must read the worker's management server and state file"
  }
}

run "management_addr_wildcard" {
  command = plan

  variables {
    management_addr = ":3290"
  }

  # A wildcard bind is still reached over loopback from inside.
  assert {
    condition     = strcontains(local.start_script, "--management-addr \":3290\"") && output.management_url == "http://127.0.0.1:3290"
    error_message = "an empty host must bind every interface and be read over loopback"
  }
}

run "management_addr_ipv6_wildcard" {
  command = plan

  variables {
    management_addr = "[::]:3290"
  }

  assert {
    condition     = output.management_url == "http://[::1]:3290"
    error_message = "an IPv6 wildcard bind must be read over IPv6 loopback"
  }
}

run "management_addr_named_host" {
  command = plan

  variables {
    management_addr = "10.0.0.5:9000"
  }

  assert {
    condition     = output.management_url == "http://10.0.0.5:9000"
    error_message = "a specific host must be read where it binds"
  }
}

run "management_addr_disabled" {
  command = plan

  variables {
    management_addr = ""
  }

  assert {
    condition     = !strcontains(local.start_script, "--management-addr") && output.management_url == "" && strcontains(output.session_attached_metadata_script, "management_url=\"\"")
    error_message = "an empty management_addr must disable the server and the attachment probe"
  }
}

run "management_addr_rejects_shell" {
  command = plan

  variables {
    management_addr = "127.0.0.1:3287\"; touch /tmp/PWNED; \""
  }

  expect_failures = [var.management_addr]
}

run "management_addr_rejects_bad_port" {
  command = plan

  variables {
    management_addr = "127.0.0.1:99999"
  }

  expect_failures = [var.management_addr]
}

run "additional_args_rejects_management_addr" {
  command = plan

  variables {
    additional_args = ["--management-addr", ":9000"]
  }

  expect_failures = [var.additional_args]
}
