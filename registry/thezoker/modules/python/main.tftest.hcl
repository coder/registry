mock_provider "coder" {}

run "plan_with_defaults" {
  command = plan

  variables {
    agent_id = "example-agent-id"
  }

  assert {
    condition     = join(",", var.python_packages) == "python3,python3-pip,python3-venv,python-is-python3"
    error_message = "Expected default Python package list."
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
    condition     = output.scripts == ["thezoker-python-install_script"]
    error_message = "Expected scripts output to expose only the install script by default."
  }
}
