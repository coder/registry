# Terraform tests for the parameter contract and rendered lifecycle scripts.
# Run with `terraform init && terraform test` in this directory. The scripts
# are handed to coder-utils, whose coder_script resources a test cannot
# reach, so assertions read the rendered locals. The standalone stop script
# is asserted directly.

variables {
  agent_id = "00000000-0000-0000-0000-000000000000"
}

run "parameter_contract" {
  command = plan

  assert {
    condition = [
      data.coder_parameter.agent_relay_session_id.name,
      data.coder_parameter.agent_relay_delivery_id.name,
      data.coder_parameter.agent_relay_pool.name,
      data.coder_parameter.agent_relay_devin_outpost_id.name,
      data.coder_parameter.agent_relay_devin_gateway_url.name,
      data.coder_parameter.agent_relay_devin_remote_binary_sha.name,
      data.coder_parameter.agent_relay_devin_session_kind.name,
      data.coder_parameter.agent_relay_devin_image.name,
      data.coder_parameter.agent_relay_devin_network_policy.name,
      data.coder_parameter.agent_relay_client_platform.name,
      data.coder_parameter.agent_relay_devin_session_url.name,
      ] == [
      "agent_relay_session_id",
      "agent_relay_delivery_id",
      "agent_relay_pool",
      "agent_relay_devin_outpost_id",
      "agent_relay_devin_gateway_url",
      "agent_relay_devin_remote_binary_sha",
      "agent_relay_devin_session_kind",
      "agent_relay_devin_image",
      "agent_relay_devin_network_policy",
      "agent_relay_client_platform",
      "agent_relay_devin_session_url",
    ]
    error_message = "parameter names are part of the Agent Relay contract"
  }

  # The shared names keep the orders the sibling modules use.
  assert {
    condition = alltrue([
      data.coder_parameter.agent_relay_session_id.order == 1000,
      data.coder_parameter.agent_relay_delivery_id.order == 1001,
      data.coder_parameter.agent_relay_pool.order == 1002,
    ])
    error_message = "the shared relay parameters must keep orders 1000 to 1002"
  }

  # None are ephemeral: they are queried back off the workspace with
  # `param:` filters, which only sees declared values. All are mutable
  # strings that default to empty, so a hand-created workspace builds.
  assert {
    condition = alltrue([
      for p in [
        data.coder_parameter.agent_relay_session_id,
        data.coder_parameter.agent_relay_delivery_id,
        data.coder_parameter.agent_relay_pool,
        data.coder_parameter.agent_relay_devin_outpost_id,
        data.coder_parameter.agent_relay_devin_gateway_url,
        data.coder_parameter.agent_relay_devin_remote_binary_sha,
        data.coder_parameter.agent_relay_devin_session_kind,
        data.coder_parameter.agent_relay_devin_image,
        data.coder_parameter.agent_relay_devin_network_policy,
        data.coder_parameter.agent_relay_client_platform,
        data.coder_parameter.agent_relay_devin_session_url,
      ] : p.ephemeral == false && p.mutable == true && p.type == "string" && (p.default == null || p.default == "")
    ])
    error_message = "parameter persistence and types do not match the Agent Relay contract"
  }

  # Cosmetic, but the point of it is that a human opening the create form
  # cannot type into a machine-set field.
  assert {
    condition = alltrue([
      for p in [
        data.coder_parameter.agent_relay_session_id.styling,
        data.coder_parameter.agent_relay_delivery_id.styling,
        data.coder_parameter.agent_relay_pool.styling,
        data.coder_parameter.agent_relay_devin_outpost_id.styling,
        data.coder_parameter.agent_relay_devin_gateway_url.styling,
        data.coder_parameter.agent_relay_devin_remote_binary_sha.styling,
        data.coder_parameter.agent_relay_devin_session_kind.styling,
        data.coder_parameter.agent_relay_devin_image.styling,
        data.coder_parameter.agent_relay_devin_network_policy.styling,
        data.coder_parameter.agent_relay_client_platform.styling,
        data.coder_parameter.agent_relay_devin_session_url.styling,
      ] : can(regex("\"disabled\":true", p))
    ])
    error_message = "every relay parameter must render disabled"
  }
}

run "remote_wiring" {
  command = plan

  # coder-utils runs the cleanup before the install step, and the install
  # step before the start step, keeping scripts and logs under this
  # directory.
  assert {
    condition     = module.coder_utils.scripts == ["coder-agent-relay-devin-pre_install_script", "coder-agent-relay-devin-install_script", "coder-agent-relay-devin-start_script"]
    error_message = "coder-utils must run exactly the pre-install, install, and start steps, in that order"
  }

  # The cleanup stops verified previous supervisors and remotes before a
  # new start. Stop renders the same template but cannot publish a marker.
  assert {
    condition     = module.coder_utils.scripts[0] == "coder-agent-relay-devin-pre_install_script" && strcontains(local.cleanup_script, "signal_pending TERM")
    error_message = "the cleanup must run as the coder-utils pre-install step"
  }

  assert {
    condition     = strcontains(local.cleanup_script, "cleanup_marker=\"${local.module_directory}/cleanup-complete\"\nrm -f \"$cleanup_marker\"") && strcontains(local.start_script, "cleanup_marker=\"${local.module_directory}/cleanup-complete\"") && strcontains(local.start_script, "starting a remote anyway") && strcontains(local.start_script, "mv \"$cleanup_marker.tmp\" \"$cleanup_marker\"")
    error_message = "cleanup must invalidate the old generation first, and start must publish a fallback generation if needed"
  }

  assert {
    condition     = coder_script.stop_remote.run_on_stop == true && coder_script.stop_remote.timeout == 20 && coder_script.stop_remote.script == local.stop_script && strcontains(local.stop_script, "signal_pending TERM") && !strcontains(local.stop_script, "cat /proc/sys/kernel/random/uuid >") && strcontains(local.cleanup_script, "cat /proc/sys/kernel/random/uuid >")
    error_message = "stop must have a 20-second timeout and use the shared cleanup template without publishing a launch marker"
  }

  assert {
    condition     = strcontains(local.stop_script, "rm -f \"$cleanup_marker\"") && strcontains(local.stop_script, "rm -f \"$state_file\"") && strcontains(local.cleanup_script, "rm -f \"$state_file\"")
    error_message = "stop and startup must remove the marker and previous state"
  }

  assert {
    condition     = strcontains(local.start_script, "elif [ -d \"${local.module_directory}/started/$cleanup_id\" ]") && strcontains(local.start_script, "new_generation") && strcontains(local.start_script, "rm -f \"$token_file\" \"$token_file.tmp\"")
    error_message = "start must rotate a claimed generation and remove a stale token when idling"
  }

  # The cleanup id travels as an argument, so a late start that runs a
  # newer start's supervisor script still checks its own id. The binary
  # path, which carries the session's SHA, is an argument too.
  assert {
    condition     = strcontains(local.start_script, "setsid nohup \"$supervisor\" \"$cleanup_id\" \"$binary\"") && strcontains(local.start_script, "cleanup_id=\"\\$${1:-}\"") && strcontains(local.start_script, "binary=\"\\$${2:-}\"") && strcontains(local.start_script, "= \"\\$cleanup_id\" ]") && strcontains(local.start_script, "mv \"$supervisor.$$.tmp\" \"$supervisor\"")
    error_message = "the supervisor must take the cleanup id and binary as arguments and be replaced by rename"
  }

  # A supervisor from an older run must not overwrite a newer run's state
  # or delete its token.
  assert {
    condition     = strcontains(local.start_script, "write_state() {\n\tcurrent || return 0") && length(regexall("! current \\|\\| rm -f \"\\$token_file\"", local.start_script)) == 2
    error_message = "every supervisor state write and token removal must check the run is still current"
  }

  assert {
    condition     = strcontains(local.cleanup_script, "${local.module_directory}/supervisors") && strcontains(local.cleanup_script, "${local.module_directory}/remotes") && strcontains(local.start_script, "supervisors=\"${local.module_directory}/supervisors\"") && strcontains(local.start_script, "remotes=\"${local.module_directory}/remotes\"")
    error_message = "the supervisor, remote, and cleanup must agree on the identity record directories"
  }

  # The remote records itself before it execs devin-remote, so it stays
  # tracked if its supervisor is SIGKILLed.
  assert {
    condition     = strcontains(local.start_script, "publish \"\\$BASHPID\" \"$remotes\" || exit 1\n\tcd \"$workdir\" || exit 1") && strcontains(local.start_script, "exec \"\\$binary\" serve\n) >\"$log_file\" 2>&1 &")
    error_message = "the remote must publish its own identity, then exec devin-remote serve from the workdir"
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

  assert {
    condition     = strcontains(local.start_script, "supervisor=\"$scripts_dir/supervise.sh\"") && strcontains(local.start_script, "scripts_dir=\"${local.module_directory}/scripts\"")
    error_message = "the supervisor must be written under module_directory/scripts, independent of state_file"
  }

  assert {
    condition     = startswith(var.state_file, local.module_directory) && startswith(var.log_file, local.module_directory)
    error_message = "remote state and log must default to the coder-utils module directory"
  }

  # Reaping reads this file through the agent_relay_status metadata item,
  # so the scripts must agree on the path.
  assert {
    condition     = strcontains(local.start_script, var.state_file) && strcontains(local.cleanup_script, var.state_file) && strcontains(output.status_metadata_script, var.state_file) && strcontains(output.session_attached_metadata_script, var.state_file)
    error_message = "the start, cleanup, and status scripts must use the same state file"
  }

  assert {
    condition     = strcontains(local.start_script, "write_state \"pending\"") && strcontains(output.status_metadata_script, "remote_alive") && strcontains(output.session_attached_metadata_script, "remote_alive")
    error_message = "the start script must reset to pending and the status scripts must check remote liveness by cmdline"
  }

  assert {
    condition = alltrue([
      for reason in ["invalid-session", "remote-binary-missing", "connect-timeout"] : strcontains(local.start_script, "failed ${reason}")
      ]) && alltrue([
      for reason in ["download", "checksum", "unsupported-arch"] : strcontains(local.install_script, "record \"failed ${reason}\"")
    ]) && strcontains(local.start_script, "write_state \"failed $${binary:-download}\"")
    error_message = "the failure reasons are the vocabulary the reaper grades"
  }

  assert {
    condition     = output.dispatched == false
    error_message = "a build with no delivery was not dispatched by Agent Relay"
  }

  assert {
    condition     = output.session_id == ""
    error_message = "a manual build has no Devin session id"
  }

  assert {
    condition     = length(coder_app.devin_session) == 0
    error_message = "a build without a session URL has no Open in Devin button"
  }
}

run "parameters_reach_scripts_through_env" {
  command = plan

  # Parameter values travel through coder_env and are read from the
  # environment at run time, never interpolated into a script.
  assert {
    condition = alltrue([
      coder_env.agent_relay_session_id.name == "AGENT_RELAY_SESSION_ID",
      coder_env.agent_relay_devin_outpost_id.name == "AGENT_RELAY_DEVIN_OUTPOST_ID",
      coder_env.agent_relay_devin_gateway_url.name == "AGENT_RELAY_DEVIN_GATEWAY_URL",
      coder_env.agent_relay_devin_remote_binary_sha.name == "AGENT_RELAY_DEVIN_REMOTE_BINARY_SHA",
      coder_env.agent_relay_devin_session_kind.name == "AGENT_RELAY_DEVIN_SESSION_KIND",
      coder_env.agent_relay_devin_image.name == "AGENT_RELAY_DEVIN_IMAGE",
      coder_env.agent_relay_devin_network_policy.name == "AGENT_RELAY_DEVIN_NETWORK_POLICY",
      coder_env.agent_relay_client_platform.name == "AGENT_RELAY_CLIENT_PLATFORM",
    ])
    error_message = "parameter values must reach the scripts through coder_env"
  }

  assert {
    condition     = strcontains(local.start_script, "session_id=\"\\$AGENT_RELAY_SESSION_ID\"") && strcontains(local.start_script, "gateway_url=\"\\$AGENT_RELAY_DEVIN_GATEWAY_URL\"") && strcontains(local.install_script, "sha=\"$${AGENT_RELAY_DEVIN_REMOTE_BINARY_SHA:-}\"") && strcontains(local.start_script, "\"$${AGENT_RELAY_DEVIN_SESSION_KIND:-}\" = \"resume\"")
    error_message = "the scripts must read the session id, gateway URL, SHA, and kind from the environment at run time"
  }

  # The agent injects the connect token from the workspace secret. A
  # coder_env of that name would put the token in Terraform state.
  assert {
    condition = !anytrue([
      for name in [
        coder_env.agent_relay_session_id.name,
        coder_env.agent_relay_devin_outpost_id.name,
        coder_env.agent_relay_devin_gateway_url.name,
        coder_env.agent_relay_devin_remote_binary_sha.name,
        coder_env.agent_relay_devin_session_kind.name,
        coder_env.agent_relay_devin_image.name,
        coder_env.agent_relay_devin_network_policy.name,
        coder_env.agent_relay_client_platform.name,
      ] : name == "AGENT_RELAY_DEVIN_TOKEN"
    ])
    error_message = "the module must not set a coder_env for the connect token"
  }
}

run "clean_remote_environment" {
  command = plan

  # Only the allowlist and Devin's own variables reach the remote. Nothing
  # the agent exports, its token included, is passed on.
  assert {
    condition     = strcontains(local.start_script, "remote_env_names=\"PATH HOME USER LOGNAME TMPDIR LANG TZ DISPLAY WAYLAND_DISPLAY XAUTHORITY\"") && strcontains(local.start_script, "for name in \\$(compgen -e); do\n\t\tunset \"\\$name\" 2>/dev/null")
    error_message = "the remote must start from a cleared environment with only the documented allowlist"
  }

  assert {
    condition = alltrue([
      for v in ["DEVIN_OUTPOST_GATEWAY_URL", "DEVIN_OUTPOST_CONNECT_TOKEN", "DEVIN_OUTPOST_SESSION_ID", "DEVIN_REMOTE_STATE_DIR"] : strcontains(local.start_script, "export ${v}=")
    ]) && strcontains(local.start_script, "export DEVIN_REMOTE_STATE_DIR=\"$state_dir/\\$session_id\"")
    error_message = "the remote must get Devin's spawn contract variables"
  }

  assert {
    condition     = !strcontains(local.start_script, "CODER_AGENT_TOKEN=") && strcontains(local.start_script, "unset AGENT_RELAY_DEVIN_TOKEN") && !strcontains(local.start_script, "export DEVIN_CHROME_PATH") && !strcontains(local.start_script, "DEVIN_OUTPOST_DESKTOP=true")
    error_message = "the agent token must never be passed, and Chrome and desktop must be opt in"
  }

  # The token is read from the owner-only file inside the remote's own
  # process and never appears on a command line.
  assert {
    condition     = strcontains(local.start_script, "token=\"\\$(cat \"$token_file\")\"") && strcontains(local.start_script, "umask 077") && !can(regex("env -i", local.start_script))
    error_message = "the connect token must reach the remote from its 0600 file, never through a command line"
  }

  # A rejected token makes devin-remote retry forever, so the watchdog is
  # what turns a connection that never comes into a failure.
  assert {
    condition     = strcontains(local.start_script, "deadline=\\$((SECONDS + 300))") && strcontains(local.start_script, "if [ \"\\$timed_out\" -eq 0 ]; then\n\twrite_state \"done \\$code\"")
    error_message = "the connect watchdog must default to 300 seconds and its failure must not be overwritten by done"
  }

  assert {
    condition     = strcontains(local.install_script, "static_base_url=\"https://static.devin.ai/devin-rs/remote\"") && strcontains(local.install_script, "cache_dir=\"$HOME/.devin/worker/cache\"")
    error_message = "the remote must download from Devin's static host and cache under $HOME/.devin/worker/cache by default"
  }
}

run "chrome_and_desktop" {
  command = plan

  variables {
    chrome_path     = "/usr/bin/chromium"
    desktop         = true
    connect_timeout = 42
    workdir         = "/srv/devin"
    state_dir       = "$HOME/devin-state"
  }

  assert {
    condition     = strcontains(local.start_script, "export DEVIN_CHROME_PATH=\"/usr/bin/chromium\"") && strcontains(local.start_script, "export DEVIN_OUTPOST_DESKTOP=true") && strcontains(local.start_script, "deadline=\\$((SECONDS + 42))")
    error_message = "chrome_path, desktop, and connect_timeout must reach the supervisor"
  }

  assert {
    condition     = strcontains(local.start_script, "workdir=\"/srv/devin\"") && strcontains(local.start_script, "state_dir=\"$HOME/devin-state\"")
    error_message = "workdir and state_dir must reach the start script"
  }
}

run "dispatched_true_when_delivery_stamped" {
  command = plan

  override_data {
    target = data.coder_parameter.agent_relay_delivery_id
    values = {
      value = "0d6c3b1e-delivery"
    }
  }

  override_data {
    target = data.coder_parameter.agent_relay_session_id
    values = {
      value = "devin-0123456789abcdef"
    }
  }

  assert {
    condition     = output.dispatched == true && output.session_id == "devin-0123456789abcdef"
    error_message = "a build carrying a delivery id belongs to a workspace Agent Relay created"
  }
}

run "session_url_https_adds_app" {
  command = plan

  override_data {
    target = data.coder_parameter.agent_relay_devin_session_url
    values = {
      value = "https://app.devin.ai/sessions/0123456789abcdef"
    }
  }

  assert {
    condition     = length(coder_app.devin_session) == 1 && coder_app.devin_session[0].url == "https://app.devin.ai/sessions/0123456789abcdef" && coder_app.devin_session[0].external == true && coder_app.devin_session[0].display_name == "Open in Devin" && coder_app.devin_session[0].icon == "/icon/devin.svg"
    error_message = "an https session URL must add an external Open in Devin button"
  }
}

run "session_url_not_https_adds_no_app" {
  command = plan

  override_data {
    target = data.coder_parameter.agent_relay_devin_session_url
    values = {
      value = "javascript:alert(1)"
    }
  }

  assert {
    condition     = length(coder_app.devin_session) == 0
    error_message = "a session URL that is not https must not become a button"
  }
}

run "session_url_http_adds_no_app" {
  command = plan

  override_data {
    target = data.coder_parameter.agent_relay_devin_session_url
    values = {
      value = "http://app.devin.ai/sessions/0123456789abcdef"
    }
  }

  assert {
    condition     = length(coder_app.devin_session) == 0
    error_message = "a plain http session URL must not become a button"
  }
}

run "remote_binary_override" {
  command = plan

  variables {
    install_remote = false
    remote_binary  = "/opt/devin/devin-remote"
  }

  assert {
    condition     = strcontains(local.start_script, "command -v /opt/devin/devin-remote") && !strcontains(local.install_script, "static.devin.ai") && strcontains(output.status_metadata_script, "grep -qF -- \"devin-remote\"")
    error_message = "remote_binary must select the binary the remote runs and skip the download"
  }
}

run "remote_binary_name_drives_liveness" {
  command = plan

  variables {
    install_remote = false
    remote_binary  = "/opt/devin/outpost"
  }

  assert {
    condition     = strcontains(output.status_metadata_script, "grep -qF -- \"outpost\"") && strcontains(output.session_attached_metadata_script, "grep -qF -- \"outpost\"")
    error_message = "the status scripts must recognize the remote by remote_binary's basename"
  }
}

run "remote_binary_rejects_shell" {
  command = plan

  variables {
    remote_binary = "devin\"; touch /tmp/PWNED; \""
  }

  expect_failures = [var.remote_binary]
}

run "remote_binary_required_without_install" {
  command = plan

  variables {
    install_remote = false
  }

  expect_failures = [var.remote_binary]
}

run "static_base_url_rejects_plain_http" {
  command = plan

  variables {
    static_base_url = "http://static.devin.ai/devin-rs/remote"
  }

  expect_failures = [var.static_base_url]
}

run "static_base_url_rejects_lookalike_host" {
  command = plan

  variables {
    static_base_url = "http://localhost.example.com/remote"
  }

  expect_failures = [var.static_base_url]
}

run "static_base_url_rejects_shell" {
  command = plan

  variables {
    static_base_url = "https://static.devin.ai/$(touch /tmp/PWNED)"
  }

  expect_failures = [var.static_base_url]
}

run "static_base_url_allows_loopback" {
  command = plan

  variables {
    static_base_url = "http://127.0.0.1:8080/remote/"
  }

  assert {
    condition     = strcontains(local.install_script, "static_base_url=\"http://127.0.0.1:8080/remote\"")
    error_message = "a loopback mirror must be accepted, without its trailing slash"
  }
}

run "workdir_rejects_shell" {
  command = plan

  variables {
    workdir = "$HOME/$(touch /tmp/PWNED)"
  }

  expect_failures = [var.workdir]
}

run "serving_log_pattern_rejects_empty" {
  command = plan

  variables {
    serving_log_pattern = ""
  }

  expect_failures = [var.serving_log_pattern]
}

run "connect_timeout_rejects_zero" {
  command = plan

  variables {
    connect_timeout = 0
  }

  expect_failures = [var.connect_timeout]
}

run "connect_timeout_rejects_fraction" {
  command = plan

  variables {
    connect_timeout = 1.5
  }

  expect_failures = [var.connect_timeout]
}

run "overridden_paths" {
  command = plan

  variables {
    state_file          = "/var/run/relay/state"
    log_file            = "/var/log/relay.log"
    serving_log_pattern = "custom pattern"
  }

  assert {
    condition     = strcontains(local.cleanup_script, "state_file=\"/var/run/relay/state\"")
    error_message = "the cleanup must clear the configured state file"
  }

  assert {
    condition     = strcontains(output.status_metadata_script, base64encode("custom pattern")) && !strcontains(output.status_metadata_script, "custom pattern") && can(regex("/var/log/relay.log", output.status_metadata_script)) && strcontains(local.start_script, base64encode("custom pattern")) && !strcontains(local.start_script, "custom pattern")
    error_message = "the status and start scripts must use the configured log file and carry the pattern base64-encoded only"
  }
}

run "serving_log_pattern_is_data" {
  command = plan

  variables {
    serving_log_pattern = "x\"; touch /tmp/PWNED; \""
  }

  # Free-form text never lands in the script as shell; it is decoded into
  # a variable, stripped of ANSI escapes, and matched as a fixed string.
  assert {
    condition     = !strcontains(output.status_metadata_script, "PWNED") && !strcontains(local.start_script, "PWNED") && strcontains(output.status_metadata_script, "grep -qF -- \"$serving_log_pattern\"") && strcontains(output.status_metadata_script, "sed \"s/$esc\\[[0-9;]*[A-Za-z]//g\"")
    error_message = "serving_log_pattern must be base64-encoded and matched with grep -F after stripping ANSI escapes"
  }
}
