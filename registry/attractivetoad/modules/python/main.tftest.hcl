mock_provider "coder" {}

run "plan_with_defaults" {
  command = plan

  variables {
    agent_id = "example-agent-id"
  }

  assert {
    condition     = var.python_version == "3.13.5"
    error_message = "Expected default Python version."
  }

  assert {
    condition     = var.pyenv_git_ref == "master"
    error_message = "Expected pyenv to install from its master branch by default."
  }

  assert {
    condition     = var.update_packages == true
    error_message = "Expected package index updates to be enabled by default."
  }

  assert {
    condition     = var.icon == "/icon/python.svg"
    error_message = "Expected default icon."
  }

  assert {
    condition     = output.scripts == ["attractivetoad-python-install_script"]
    error_message = "Expected scripts output to expose only the install script by default."
  }

  assert {
    condition     = strcontains(local.install_script, "run_apt_get update")
    error_message = "Expected apt-get update to retry package-manager lock conflicts."
  }

  assert {
    condition     = strcontains(local.install_script, "pyenv install --skip-existing")
    error_message = "Expected Python to be installed with pyenv."
  }
}
