run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.port == 4020
    error_message = "Default port should be 4020"
  }

  assert {
    condition     = var.install == true
    error_message = "Happy installation should be enabled by default"
  }

  assert {
    condition     = var.install_version == "latest"
    error_message = "Default install_version should be 'latest'"
  }

  assert {
    condition     = var.package_manager == "npm"
    error_message = "Default package_manager should be 'npm'"
  }

  assert {
    condition     = var.use_cached == false
    error_message = "use_cached should be disabled by default"
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
    condition     = var.tmux_session == "happy"
    error_message = "Default tmux_session should be 'happy'"
  }

  assert {
    condition     = local.module_dir_name == ".coder-modules/gojnimer6553/happy"
    error_message = "Module dir name should be '.coder-modules/gojnimer6553/happy'"
  }

  assert {
    condition     = local.install_prefix_override == ""
    error_message = "install_prefix_override should be empty by default (the script computes the $HOME-based default itself)"
  }

  assert {
    condition     = local.workdir_override == ""
    error_message = "workdir_override should be empty by default (the script defaults to $HOME itself)"
  }

  assert {
    condition     = resource.coder_app.happy.url == "http://localhost:4020"
    error_message = "App URL should point at localhost on the configured port"
  }

  assert {
    condition     = resource.coder_app.happy.slug == "happy"
    error_message = "Default slug should be 'happy'"
  }

  assert {
    condition     = resource.coder_app.happy.share == "owner"
    error_message = "Default share should be 'owner'"
  }
}

run "custom_port_configuration" {
  command = apply

  variables {
    agent_id = "test-agent"
    port     = 4021
  }

  assert {
    condition     = resource.coder_app.happy.url == "http://localhost:4021"
    error_message = "App URL should use the configured port"
  }

  assert {
    condition     = [for h in resource.coder_app.happy.healthcheck : h.url][0] == "http://localhost:4021/healthz"
    error_message = "Healthcheck URL should use the configured port"
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

run "custom_install_prefix_overrides_default" {
  command = plan

  variables {
    agent_id       = "test-agent"
    install_prefix = "/opt/happy"
  }

  assert {
    condition     = local.install_prefix_override == "/opt/happy"
    error_message = "Explicit install_prefix should be forwarded as the override"
  }
}

run "install_version_configuration" {
  command = plan

  variables {
    agent_id        = "test-agent"
    install_version = "1.2.0"
  }

  assert {
    condition     = var.install_version == "1.2.0"
    error_message = "install_version should be set correctly"
  }
}

run "invalid_package_manager_rejected" {
  command = plan

  variables {
    agent_id        = "test-agent"
    package_manager = "yarn"
  }

  expect_failures = [
    var.package_manager,
  ]
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

run "custom_share_configuration" {
  command = plan

  variables {
    agent_id = "test-agent"
    share    = "public"
  }

  assert {
    condition     = resource.coder_app.happy.share == "public"
    error_message = "Custom share should override the default 'owner'"
  }
}

run "subdomain_disabled_configuration" {
  command = plan

  variables {
    agent_id  = "test-agent"
    subdomain = false
  }

  assert {
    condition     = resource.coder_app.happy.subdomain == false
    error_message = "subdomain should be disabled when specified"
  }
}

run "custom_display_and_slug" {
  command = plan

  variables {
    agent_id     = "test-agent"
    slug         = "happy-cli"
    display_name = "Happy"
    icon         = "/custom/icon.svg"
    order        = 5
    group        = "AI Tools"
  }

  assert {
    condition     = resource.coder_app.happy.slug == "happy-cli"
    error_message = "Custom slug should be set"
  }

  assert {
    condition     = resource.coder_app.happy.display_name == "Happy"
    error_message = "Custom display_name should be set"
  }

  assert {
    condition     = resource.coder_app.happy.icon == "/custom/icon.svg"
    error_message = "Custom icon should be set"
  }

  assert {
    condition     = resource.coder_app.happy.order == 5
    error_message = "Custom order should be set"
  }

  assert {
    condition     = resource.coder_app.happy.group == "AI Tools"
    error_message = "Custom group should be set"
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
    condition     = var.pre_install_script != null
    error_message = "Pre-install script should be set"
  }

  assert {
    condition     = var.post_install_script != null
    error_message = "Post-install script should be set"
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
    tmux_session = "happy-custom"
  }

  assert {
    condition     = var.tmux_session == "happy-custom"
    error_message = "tmux_session should be set correctly"
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
