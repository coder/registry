mock_provider "coder" {}

variables {
  agent_id = "test-agent-id"
}

run "defaults" {
  command = plan

  assert {
    condition     = length(coder_script.wait_for_install) == 0
    error_message = "Workspace login must remain non-blocking by default."
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("latest"))
    error_message = "The rendered install script must use latest by default."
  }

  assert {
    condition     = output.scripts == ["coder-devcontainers-cli-install_script"]
    error_message = "Expose the coder-utils installation dependency for downstream scripts."
  }
}

run "pinned_version" {
  command = plan

  variables {
    devcontainers_cli_version = "0.80.0"
    start_blocks_login        = true
  }

  assert {
    condition     = coder_script.wait_for_install[0].start_blocks_login && coder_script.wait_for_install[0].run_on_start
    error_message = "The optional waiter must block login on workspace start."
  }

  assert {
    condition     = coder_script.wait_for_install[0].agent_id == var.agent_id
    error_message = "The waiter must run on the installation agent."
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("0.80.0"))
    error_message = "The installation must use the exact requested version."
  }
}

run "prefixed_version" {
  command = plan

  variables {
    devcontainers_cli_version = "v0.80.0"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("0.80.0"))
    error_message = "Strip the optional v prefix before passing the version to the package manager."
  }
}

run "rejects_empty_version" {
  command = plan

  variables {
    devcontainers_cli_version = ""
  }

  expect_failures = [var.devcontainers_cli_version]
}

run "rejects_whitespace_version" {
  command = plan

  variables {
    devcontainers_cli_version = " "
  }

  expect_failures = [var.devcontainers_cli_version]
}

run "rejects_partial_version" {
  command = plan

  variables {
    devcontainers_cli_version = "0.80"
  }

  expect_failures = [var.devcontainers_cli_version]
}

run "rejects_range_version" {
  command = plan

  variables {
    devcontainers_cli_version = "^0.80.0"
  }

  expect_failures = [var.devcontainers_cli_version]
}

run "rejects_tag_version" {
  command = plan

  variables {
    devcontainers_cli_version = "next"
  }

  expect_failures = [var.devcontainers_cli_version]
}

run "rejects_prerelease_version" {
  command = plan

  variables {
    devcontainers_cli_version = "0.80.0-beta.1"
  }

  expect_failures = [var.devcontainers_cli_version]
}

run "rejects_leading_zero_version" {
  command = plan

  variables {
    devcontainers_cli_version = "01.80.0"
  }

  expect_failures = [var.devcontainers_cli_version]
}

run "rejects_surrounding_whitespace_version" {
  command = plan

  variables {
    devcontainers_cli_version = " 0.80.0 "
  }

  expect_failures = [var.devcontainers_cli_version]
}

run "rejects_package_url_version" {
  command = plan

  variables {
    devcontainers_cli_version = "https://example.com/cli.tgz"
  }

  expect_failures = [var.devcontainers_cli_version]
}
