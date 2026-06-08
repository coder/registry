run "required_vars" {
  command = plan

  variables {
    agent_id = "foo"
  }
}

run "install_false_and_use_cached_conflict" {
  command = plan

  variables {
    agent_id   = "foo"
    use_cached = true
    install    = false
  }

  expect_failures = [
    resource.coder_script.mux
  ]
}

# Needs command = apply because the URL contains random_password.result,
# which is unknown during plan.
run "custom_port" {
  command = apply

  variables {
    agent_id = "foo"
    port     = 8080
  }

  assert {
    condition     = startswith(resource.coder_app.mux.url, "http://localhost:8080?token=")
    error_message = "coder_app URL must use the configured port and include auth token"
  }

  assert {
    condition     = trimprefix(resource.coder_app.mux.url, "http://localhost:8080?token=") == random_password.mux_auth_token.result
    error_message = "URL token must match the generated auth token"
  }
}

# Needs command = apply because random_password.result is unknown during plan.
run "auth_token_in_server_script" {
  command = apply

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "MUX_SERVER_AUTH_TOKEN=")
    error_message = "mux launch script must set MUX_SERVER_AUTH_TOKEN"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, random_password.mux_auth_token.result)
    error_message = "mux launch script must use the generated auth token"
  }
}

# Needs command = apply because random_password.result is unknown during plan.
run "auth_token_in_url" {
  command = apply

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = startswith(resource.coder_app.mux.url, "http://localhost:4000?token=")
    error_message = "coder_app URL must include auth token query parameter"
  }

  assert {
    condition     = trimprefix(resource.coder_app.mux.url, "http://localhost:4000?token=") == random_password.mux_auth_token.result
    error_message = "URL token must match the generated auth token"
  }
}

run "custom_additional_arguments" {
  command = plan

  variables {
    agent_id             = "foo"
    additional_arguments = "--open-mode pinned --add-project '/workspaces/my repo'"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "--open-mode pinned --add-project '/workspaces/my repo'")
    error_message = "mux launch script must include the configured additional arguments"
  }
}

run "launcher_logs_external_kills" {
  command = plan

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "shell exit code $exit_code")
    error_message = "mux launcher must log the shell exit code when the server dies unexpectedly"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "SIGKILL usually means the process was killed externally or by the OOM killer.")
    error_message = "mux launcher must explain SIGKILL exits in the log"
  }
}

run "restart_on_kill_enabled" {
  command = plan

  variables {
    agent_id              = "foo"
    restart_on_kill       = true
    restart_delay_seconds = 7
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "restart_on_kill_value=\"true\"")
    error_message = "mux launcher must receive the restart_on_kill setting"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "restart_delay_seconds_value=\"7\"")
    error_message = "mux launcher must receive the configured restart delay"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "Waiting $${RESTART_DELAY_SECONDS_VALUE} seconds before restarting mux after it exited.")
    error_message = "mux launcher must log the restart delay before relaunching"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "Removing $HOME/.mux/server.lock before restarting mux.")
    error_message = "mux launcher must clean up the server lock before relaunching"
  }

  assert {
    condition     = !strcontains(resource.coder_script.mux.script, "\"$exit_code\" -le 128")
    error_message = "mux launcher must no longer exclude non-signal exits from restart handling"
  }

  assert {
    condition     = !strcontains(resource.coder_script.mux.script, "1|2|15)")
    error_message = "mux launcher must no longer exclude intentional signals from restart handling"
  }
}

run "restart_on_kill_with_restart_cap" {
  command = plan

  variables {
    agent_id              = "foo"
    restart_on_kill       = true
    restart_delay_seconds = 7
    max_restart_attempts  = 2
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "max_restart_attempts_value=\"2\"")
    error_message = "mux launcher must receive the configured restart cap"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "Mux will stop restarting after $${max_restart_attempts_value} restart attempts.")
    error_message = "mux launcher must describe the configured restart cap"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "Reached the max restart attempts limit ($MAX_RESTART_ATTEMPTS_VALUE); not restarting mux again.")
    error_message = "mux launcher must log when it hits the restart cap"
  }
}

run "invalid_max_restart_attempts" {
  command = plan

  variables {
    agent_id             = "foo"
    max_restart_attempts = -1
  }

  expect_failures = [
    var.max_restart_attempts
  ]
}

run "fractional_max_restart_attempts" {
  command = plan

  variables {
    agent_id             = "foo"
    max_restart_attempts = 0.5
  }

  expect_failures = [
    var.max_restart_attempts
  ]
}

run "invalid_restart_delay_seconds" {
  command = plan

  variables {
    agent_id              = "foo"
    restart_delay_seconds = -1
  }

  expect_failures = [
    var.restart_delay_seconds
  ]
}

run "custom_version" {
  command = plan

  variables {
    agent_id        = "foo"
    install_version = "0.3.0"
  }
}

# install=false should succeed
run "install_false_only_success" {
  command = plan

  variables {
    agent_id = "foo"
    install  = false
  }
}

# use_cached-only should succeed
run "use_cached_only_success" {
  command = plan

  variables {
    agent_id   = "foo"
    use_cached = true
  }
}

# Custom package_manager should appear in generated script
run "custom_package_manager_npm" {
  command = plan

  variables {
    agent_id        = "foo"
    package_manager = "npm"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "PM_CMD=\"npm\"")
    error_message = "mux script must set PM_CMD to the configured package manager"
  }
}

run "custom_package_manager_pnpm" {
  command = plan

  variables {
    agent_id        = "foo"
    package_manager = "pnpm"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "PM_CMD=\"pnpm\"")
    error_message = "mux script must set PM_CMD to the configured package manager"
  }
}

run "custom_package_manager_bun" {
  command = plan

  variables {
    agent_id        = "foo"
    package_manager = "bun"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "PM_CMD=\"bun\"")
    error_message = "mux script must set PM_CMD to the configured package manager"
  }
}

# Invalid package_manager should fail validation
run "invalid_package_manager" {
  command = plan

  variables {
    agent_id        = "foo"
    package_manager = "yarn"
  }

  expect_failures = [
    var.package_manager
  ]
}

# Custom registry_url should appear in generated script
run "custom_registry_url" {
  command = plan

  variables {
    agent_id     = "foo"
    registry_url = "https://npm.example.com"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "https://npm.example.com")
    error_message = "mux script must use the configured registry URL"
  }

  assert {
    condition     = !strcontains(resource.coder_script.mux.script, "registry.npmjs.org")
    error_message = "mux script must not contain hardcoded registry.npmjs.org when custom registry is set"
  }
}

# registry_url trailing slash should be stripped
run "registry_url_trailing_slash" {
  command = plan

  variables {
    agent_id     = "foo"
    registry_url = "https://npm.example.com/"
  }

  assert {
    condition     = strcontains(resource.coder_script.mux.script, "https://npm.example.com/mux/")
    error_message = "registry URL trailing slash must be stripped to avoid double slashes"
  }
}

