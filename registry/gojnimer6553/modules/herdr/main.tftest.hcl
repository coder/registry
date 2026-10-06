run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.install == true
    error_message = "Herdr installation should be enabled by default"
  }

  assert {
    condition     = var.use_cached == false
    error_message = "use_cached should be disabled by default"
  }

  assert {
    condition     = length(var.plugins) == 0
    error_message = "plugins should be empty (opt-in) by default"
  }

  assert {
    condition     = var.session_name == null
    error_message = "session_name should be unset by default (use Herdr's default session)"
  }

  assert {
    condition     = local.session_env == ""
    error_message = "session_env should be empty when session_name is unset"
  }

  assert {
    condition     = var.tmux_session == "herdr"
    error_message = "Default tmux_session should be 'herdr'"
  }

  assert {
    condition     = var.app_port == null
    error_message = "app_port should be unset (no app tile) by default"
  }

  assert {
    condition     = length(resource.coder_app.herdr) == 0
    error_message = "No coder_app should be created when app_port is unset"
  }

  assert {
    condition     = var.share == "owner"
    error_message = "Default share should be 'owner'"
  }

  assert {
    condition     = var.subdomain == true
    error_message = "subdomain should be enabled by default"
  }

  assert {
    condition     = var.open_in == "slim-window"
    error_message = "Default open_in should be 'slim-window'"
  }

  assert {
    condition     = local.module_dir_name == ".coder-modules/gojnimer6553/herdr"
    error_message = "Module dir name should be '.coder-modules/gojnimer6553/herdr'"
  }

  assert {
    condition     = local.workdir_override == ""
    error_message = "workdir_override should be empty by default (the script defaults to $HOME itself)"
  }
}

run "custom_plugins_configuration" {
  command = plan

  variables {
    agent_id = "test-agent"
    plugins  = ["0cv/herdr-mobile-relay", "some-owner/some-other-plugin"]
  }

  assert {
    condition     = length(var.plugins) == 2
    error_message = "plugins should accept multiple entries"
  }

  assert {
    condition     = var.plugins[0] == "0cv/herdr-mobile-relay"
    error_message = "plugins should preserve order"
  }
}

run "custom_session_name_configuration" {
  command = plan

  variables {
    agent_id     = "test-agent"
    session_name = "isolated"
  }

  assert {
    condition     = local.session_env == "isolated"
    error_message = "Custom session_name should be forwarded as session_env"
  }
}

run "custom_workdir_configuration" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project"
  }

  assert {
    condition     = local.workdir_override == "/home/coder/project"
    error_message = "Custom workdir should be forwarded as the override"
  }
}

run "app_port_creates_app_tile" {
  command = plan

  variables {
    agent_id = "test-agent"
    app_port = 8375
  }

  assert {
    condition     = length(resource.coder_app.herdr) == 1
    error_message = "Setting app_port should create exactly one coder_app"
  }

  assert {
    condition     = resource.coder_app.herdr[0].url == "http://localhost:8375"
    error_message = "App URL should point at localhost on the configured app_port"
  }

  assert {
    condition     = resource.coder_app.herdr[0].slug == "herdr"
    error_message = "Default app_slug should be 'herdr'"
  }

  assert {
    condition     = [for h in resource.coder_app.herdr[0].healthcheck : h.url][0] == "http://localhost:8375/healthz"
    error_message = "Healthcheck URL should use the configured app_port and default app_healthcheck_path"
  }
}

run "custom_app_configuration" {
  command = plan

  variables {
    agent_id             = "test-agent"
    app_port             = 9000
    app_slug             = "herdr-relay"
    app_display_name     = "Herdr Mobile Relay"
    app_healthcheck_path = "/health"
    order                = 5
    group                = "AI Tools"
  }

  assert {
    condition     = resource.coder_app.herdr[0].slug == "herdr-relay"
    error_message = "Custom app_slug should be set"
  }

  assert {
    condition     = resource.coder_app.herdr[0].display_name == "Herdr Mobile Relay"
    error_message = "Custom app_display_name should be set"
  }

  assert {
    condition     = [for h in resource.coder_app.herdr[0].healthcheck : h.url][0] == "http://localhost:9000/health"
    error_message = "Custom app_healthcheck_path should be used"
  }

  assert {
    condition     = resource.coder_app.herdr[0].order == 5
    error_message = "Custom order should be set"
  }

  assert {
    condition     = resource.coder_app.herdr[0].group == "AI Tools"
    error_message = "Custom group should be set"
  }
}

run "invalid_share_rejected" {
  command = plan

  variables {
    agent_id = "test-agent"
    share    = "invalid"
  }

  expect_failures = [
    var.share,
  ]
}

run "invalid_open_in_rejected" {
  command = plan

  variables {
    agent_id = "test-agent"
    open_in  = "invalid"
  }

  expect_failures = [
    var.open_in,
  ]
}

run "install_disabled_configuration" {
  command = plan

  variables {
    agent_id = "test-agent"
    install  = false
  }

  assert {
    condition     = var.install == false
    error_message = "install should be disabled when specified"
  }
}

run "custom_tmux_session_configuration" {
  command = plan

  variables {
    agent_id     = "test-agent"
    tmux_session = "herdr-custom"
  }

  assert {
    condition     = var.tmux_session == "herdr-custom"
    error_message = "tmux_session should be set correctly"
  }
}

run "custom_scripts_configuration" {
  command = plan

  variables {
    agent_id            = "test-agent"
    pre_install_script  = "#!/bin/bash\necho 'pre-install'"
    post_install_script = "#!/bin/bash\necho 'post-install'"
  }

  assert {
    condition     = can(regex("pre-install", var.pre_install_script))
    error_message = "Pre-install script should contain expected content"
  }

  assert {
    condition     = can(regex("post-install", var.post_install_script))
    error_message = "Post-install script should contain expected content"
  }
}

run "post_start_script_defaults_to_unset" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.post_start_script == null
    error_message = "post_start_script should be unset by default"
  }
}

run "custom_post_start_script_configuration" {
  command = plan

  variables {
    agent_id          = "test-agent"
    post_start_script = "#!/bin/bash\necho 'post-start'"
  }

  assert {
    condition     = can(regex("post-start", var.post_start_script))
    error_message = "post_start_script should contain expected content"
  }
}

run "scripts_output_is_populated" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = length(output.scripts) > 0
    error_message = "scripts output should list at least the install and start scripts"
  }
}
