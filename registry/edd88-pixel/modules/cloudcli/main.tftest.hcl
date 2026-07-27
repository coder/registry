mock_provider "coder" {}

run "defaults_are_secure" {
  command = apply

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = coder_app.cloudcli.url == "http://localhost:3001"
    error_message = "The default app URL must use port 3001."
  }

  assert {
    condition     = coder_app.cloudcli.subdomain
    error_message = "CloudCLI must use a Coder subdomain."
  }

  assert {
    condition     = coder_app.cloudcli.share == "owner"
    error_message = "CloudCLI must be restricted to the workspace owner."
  }

  assert {
    condition     = coder_app.cloudcli.icon == "https://avatars.githubusercontent.com/u/252026187?s=200&v=4"
    error_message = "The app must use the CloudCLI project icon."
  }

  assert {
    condition     = one(coder_app.cloudcli.healthcheck).url == "http://localhost:3001/health"
    error_message = "The health check must use CloudCLI's /health endpoint."
  }

  assert {
    condition     = strcontains(local.start_script, "export HOST=\"127.0.0.1\"")
    error_message = "The startup script must bind CloudCLI to IPv4 loopback."
  }

  assert {
    condition     = !strcontains(local.start_script, "0.0.0.0")
    error_message = "The default startup script must not contain an all-interface listener."
  }

  assert {
    condition     = strcontains(local.start_script, "DATABASE_PATH=\"$DATA_DIR/auth.db\"")
    error_message = "CloudCLI's database must be stored in the module data directory."
  }

  assert {
    condition     = local.module_directory == "$HOME/.coder-modules/edd88-pixel/cloudcli"
    error_message = "The module must use the standard per-module data root."
  }

  assert {
    condition     = length(output.scripts) == 2
    error_message = "The coder-utils pipeline must expose install and start scripts."
  }

  assert {
    condition     = strcontains(coder_script.start_script.script, "coder exp sync start --timeout 30m edd88-pixel-cloudcli-start_script")
    error_message = "The start script must allow slow first-time CloudCLI installations to finish."
  }

  assert {
    condition = (
      strcontains(local.start_script, "Waiting for CloudCLI to come online...") &&
      !strcontains(local.start_script, "--show-error")
    )
    error_message = "Readiness polling must log a calm status message without transient curl warnings."
  }
}

run "custom_configuration" {
  command = apply

  variables {
    agent_id        = "test-agent"
    port            = 43123
    workspaces_root = "/home/coder/project"
    order           = 7
    group           = "AI Tools"
  }

  assert {
    condition     = coder_app.cloudcli.url == "http://localhost:43123"
    error_message = "The app URL must use the configured port."
  }

  assert {
    condition     = one(coder_app.cloudcli.healthcheck).url == "http://localhost:43123/health"
    error_message = "The health check must use the configured port."
  }

  assert {
    condition     = coder_app.cloudcli.order == 7 && coder_app.cloudcli.group == "AI Tools"
    error_message = "The app must preserve its configured order and group."
  }

  assert {
    condition     = strcontains(local.start_script, base64encode("/home/coder/project"))
    error_message = "The configured workspace root must be encoded into the startup script."
  }
}

run "rejects_low_port" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 1023
  }

  expect_failures = [var.port]
}

run "rejects_high_port" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 65536
  }

  expect_failures = [var.port]
}

run "rejects_relative_workspace_root" {
  command = plan

  variables {
    agent_id        = "test-agent"
    workspaces_root = "project"
  }

  expect_failures = [var.workspaces_root]
}

run "rejects_dangerous_workspace_root" {
  command = plan

  variables {
    agent_id        = "test-agent"
    workspaces_root = "/home/coder/project;touch-pwned"
  }

  expect_failures = [var.workspaces_root]
}

run "rejects_parent_workspace_root" {
  command = plan

  variables {
    agent_id        = "test-agent"
    workspaces_root = "/home/coder/../root"
  }

  expect_failures = [var.workspaces_root]
}

run "rejects_unpinned_version" {
  command = plan

  variables {
    agent_id         = "test-agent"
    cloudcli_version = "latest"
  }

  expect_failures = [var.cloudcli_version]
}

run "accepts_exact_version" {
  command = plan

  variables {
    agent_id         = "test-agent"
    cloudcli_version = "2.4.6"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_CLOUDCLI_VERSION='2.4.6'")
    error_message = "The exact CloudCLI version must be rendered into the install script."
  }
}
