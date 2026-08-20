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
    var.use_cached
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
    condition     = startswith(resource.coder_app.shux.url, "http://localhost:8080?token=")
    error_message = "coder_app URL must use the configured port and include auth token"
  }

  assert {
    condition     = trimprefix(resource.coder_app.shux.url, "http://localhost:8080?token=") == random_password.shux_auth_token.result
    error_message = "URL token must match the generated auth token"
  }
}

# The start script embeds random_password.result, which is unknown during
# plan, so every assertion on local.start_script needs command = apply.
run "auth_token_in_start_script" {
  command = apply

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = strcontains(local.start_script, "SHUX_SERVER_AUTH_TOKEN=")
    error_message = "shux launch script must set SHUX_SERVER_AUTH_TOKEN"
  }

  assert {
    condition     = strcontains(local.start_script, "MUX_SERVER_AUTH_TOKEN=")
    error_message = "shux launch script must set the legacy MUX_SERVER_AUTH_TOKEN alias"
  }

  assert {
    condition     = strcontains(local.start_script, random_password.shux_auth_token.result)
    error_message = "shux launch script must use the generated auth token"
  }
}

# Needs command = apply because random_password.result is unknown during plan.
run "auth_token_in_url" {
  command = apply

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = startswith(resource.coder_app.shux.url, "http://localhost:4000?token=")
    error_message = "coder_app URL must include auth token query parameter"
  }

  assert {
    condition     = trimprefix(resource.coder_app.shux.url, "http://localhost:4000?token=") == random_password.shux_auth_token.result
    error_message = "URL token must match the generated auth token"
  }
}

run "custom_additional_arguments" {
  command = apply

  variables {
    agent_id             = "foo"
    additional_arguments = "--open-mode pinned --add-project '/workspaces/my repo'"
  }

  assert {
    condition     = strcontains(local.start_script, "--open-mode pinned --add-project '/workspaces/my repo'")
    error_message = "shux launch script must include the configured additional arguments"
  }
}

run "launcher_logs_external_kills" {
  command = apply

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = strcontains(local.start_script, "shell exit code $exit_code")
    error_message = "shux launcher must log the shell exit code when the server dies unexpectedly"
  }

  assert {
    condition     = strcontains(local.start_script, "SIGKILL usually means the process was killed externally or by the OOM killer.")
    error_message = "shux launcher must explain SIGKILL exits in the log"
  }
}

run "restart_on_kill_enabled" {
  command = apply

  variables {
    agent_id              = "foo"
    restart_on_kill       = true
    restart_delay_seconds = 7
  }

  assert {
    condition     = strcontains(local.start_script, "restart_on_kill_value=\"true\"")
    error_message = "shux launcher must receive the restart_on_kill setting"
  }

  assert {
    condition     = strcontains(local.start_script, "restart_delay_seconds_value=\"7\"")
    error_message = "shux launcher must receive the configured restart delay"
  }

  assert {
    condition     = strcontains(local.start_script, "Waiting $${RESTART_DELAY_SECONDS_VALUE} seconds before restarting shux after it exited.")
    error_message = "shux launcher must log the restart delay before relaunching"
  }

  assert {
    condition     = strcontains(local.start_script, "Removing $HOME/.shux/server.lock and $HOME/.mux/server.lock before restarting shux.")
    error_message = "shux launcher must clean up the server locks before relaunching"
  }

  assert {
    condition     = !strcontains(local.start_script, "\"$exit_code\" -le 128")
    error_message = "shux launcher must not exclude non-signal exits from restart handling"
  }

  assert {
    condition     = !strcontains(local.start_script, "1|2|15)")
    error_message = "shux launcher must not exclude intentional signals from restart handling"
  }
}

run "restart_on_kill_with_restart_cap" {
  command = apply

  variables {
    agent_id              = "foo"
    restart_on_kill       = true
    restart_delay_seconds = 7
    max_restart_attempts  = 2
  }

  assert {
    condition     = strcontains(local.start_script, "max_restart_attempts_value=\"2\"")
    error_message = "shux launcher must receive the configured restart cap"
  }

  assert {
    condition     = strcontains(local.start_script, "Shux will stop restarting after $${max_restart_attempts_value} restart attempts.")
    error_message = "shux launcher must describe the configured restart cap"
  }

  assert {
    condition     = strcontains(local.start_script, "Reached the max restart attempts limit ($MAX_RESTART_ATTEMPTS_VALUE); not restarting shux again.")
    error_message = "shux launcher must log when it hits the restart cap"
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

  assert {
    condition     = strcontains(local.install_script, "$PKG@0.3.0")
    error_message = "shux install script must pin the configured package version"
  }
}

# The module data layout and package identity are load-bearing for
# troubleshooting docs; guard the defaults.
run "module_data_layout_defaults" {
  command = plan

  variables {
    agent_id = "foo"
  }

  assert {
    condition     = var.install_prefix == "$HOME/.coder-modules/coder/shux/install"
    error_message = "install_prefix default must live under the module data root"
  }

  assert {
    condition     = var.log_path == "$HOME/.coder-modules/coder/shux/logs/shux.log"
    error_message = "log_path default must live under the module data root"
  }

  assert {
    condition     = strcontains(local.install_script, "PKG=\"@coder/shux\"")
    error_message = "shux install script must install the @coder/shux package"
  }

  assert {
    condition     = strcontains(local.install_script, "/@coder/shux/-/shux-")
    error_message = "shux install script must construct scoped tarball URLs"
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
    condition     = strcontains(local.install_script, "PM_CMD=\"npm\"")
    error_message = "shux install script must set PM_CMD to the configured package manager"
  }
}

run "custom_package_manager_pnpm" {
  command = plan

  variables {
    agent_id        = "foo"
    package_manager = "pnpm"
  }

  assert {
    condition     = strcontains(local.install_script, "PM_CMD=\"pnpm\"")
    error_message = "shux install script must set PM_CMD to the configured package manager"
  }
}

run "custom_package_manager_bun" {
  command = plan

  variables {
    agent_id        = "foo"
    package_manager = "bun"
  }

  assert {
    condition     = strcontains(local.install_script, "PM_CMD=\"bun\"")
    error_message = "shux install script must set PM_CMD to the configured package manager"
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
    condition     = strcontains(local.install_script, "https://npm.example.com")
    error_message = "shux install script must use the configured registry URL"
  }

  assert {
    condition     = !strcontains(local.install_script, "registry.npmjs.org")
    error_message = "shux install script must not contain hardcoded registry.npmjs.org when custom registry is set"
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
    condition     = strcontains(local.install_script, "https://npm.example.com/@coder%2fshux/")
    error_message = "registry URL trailing slash must be stripped to avoid double slashes"
  }
}
