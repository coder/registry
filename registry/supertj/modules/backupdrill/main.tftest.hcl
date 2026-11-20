run "defaults_install_latest_2x" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.backupdrill_version == "2"
    error_message = "backupdrill_version should default to the 2.x major"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_BACKUPDRILL_VERSION='2'")
    error_message = "install script should request backupdrill@2 by default"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_NPM_REGISTRY_URL=''")
    error_message = "install script should use npm's configured registry by default"
  }

  assert {
    condition     = local.module_directory == "$HOME/.coder-modules/supertj/backupdrill"
    error_message = "module data should live under the standard per-module directory"
  }
}

run "exact_version" {
  command = plan

  variables {
    agent_id            = "test-agent"
    backupdrill_version = "2.7.1"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_BACKUPDRILL_VERSION='2.7.1'")
    error_message = "install script should request the pinned version"
  }
}

run "latest_version" {
  command = plan

  variables {
    agent_id            = "test-agent"
    backupdrill_version = "latest"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_BACKUPDRILL_VERSION='latest'")
    error_message = "install script should accept latest"
  }
}

run "rejects_version_range" {
  command = plan

  variables {
    agent_id            = "test-agent"
    backupdrill_version = "^2.7.0"
  }

  expect_failures = [var.backupdrill_version]
}

run "rejects_shell_in_version" {
  command = plan

  variables {
    agent_id            = "test-agent"
    backupdrill_version = "2'; echo pwned; '"
  }

  expect_failures = [var.backupdrill_version]
}

run "custom_npm_registry" {
  command = plan

  variables {
    agent_id         = "test-agent"
    npm_registry_url = "https://npm.internal.example.com/repository/npm/"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_NPM_REGISTRY_URL='https://npm.internal.example.com/repository/npm/'")
    error_message = "install script should pass the custom registry"
  }
}

run "rejects_non_http_registry" {
  command = plan

  variables {
    agent_id         = "test-agent"
    npm_registry_url = "ftp://npm.internal.example.com"
  }

  expect_failures = [var.npm_registry_url]
}

run "rejects_quote_in_registry" {
  command = plan

  variables {
    agent_id         = "test-agent"
    npm_registry_url = "https://example.com/'; echo pwned; '"
  }

  expect_failures = [var.npm_registry_url]
}

run "scripts_output" {
  command = apply

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = output.scripts == ["supertj-backupdrill-install_script"]
    error_message = "scripts output should list only the install script"
  }
}
