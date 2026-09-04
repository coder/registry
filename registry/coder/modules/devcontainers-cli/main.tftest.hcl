mock_provider "coder" {}

variables {
  agent_id = "test-agent-id"
}

run "defaults" {
  command = plan

  assert {
    condition     = resource.coder_script.devcontainers-cli.agent_id == var.agent_id
    error_message = "The install script must use the configured agent ID."
  }

  assert {
    condition     = resource.coder_script.devcontainers-cli.run_on_start
    error_message = "The install script must run when the workspace starts."
  }

  assert {
    condition     = !resource.coder_script.devcontainers-cli.start_blocks_login
    error_message = "Workspace login must remain non-blocking by default."
  }

  assert {
    condition     = strcontains(resource.coder_script.devcontainers-cli.script, base64encode("latest"))
    error_message = "The rendered script must contain the encoded default version."
  }
}

run "custom_install_source" {
  command = plan

  variables {
    devcontainers_cli_version = "0.80.0"
    registry_url              = "https://registry.example.com/npm"
    start_blocks_login        = true
  }

  assert {
    condition     = resource.coder_script.devcontainers-cli.start_blocks_login
    error_message = "The install script must preserve the configured login-blocking behavior."
  }

  assert {
    condition     = strcontains(resource.coder_script.devcontainers-cli.script, base64encode(var.devcontainers_cli_version))
    error_message = "The rendered script must contain the encoded custom version."
  }

  assert {
    condition     = strcontains(resource.coder_script.devcontainers-cli.script, base64encode(var.registry_url))
    error_message = "The rendered script must contain the encoded custom registry URL."
  }

  assert {
    condition     = !strcontains(resource.coder_script.devcontainers-cli.script, var.registry_url)
    error_message = "The rendered script must not interpolate the raw registry URL."
  }
}

run "rejects_empty_version" {
  command = plan

  variables {
    devcontainers_cli_version = " "
  }

  expect_failures = [var.devcontainers_cli_version]
}

run "rejects_invalid_registry_url" {
  command = plan

  variables {
    registry_url = "registry.example.com/npm"
  }

  expect_failures = [var.registry_url]
}
