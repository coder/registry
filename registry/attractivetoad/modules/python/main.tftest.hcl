mock_provider "coder" {}

run "plan_with_defaults" {
  command = plan

  variables {
    agent_id = "example-agent-id"
  }

  assert {
    condition     = join(",", var.python_packages) == "python3,python3-pip,python3-venv"
    error_message = "Expected default Python package list."
  }

  assert {
    condition     = var.create_python_alias == true
    error_message = "Expected python alias creation to be enabled by default."
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
    condition     = output.scripts == ["attractivetoad-python-install"]
    error_message = "Expected scripts output to expose only the install script by default."
  }

  assert {
    condition     = strcontains(coder_script.install.script, "sudo apt-get -o DPkg::Lock::Timeout=300 update")
    error_message = "Expected apt-get update to wait for dpkg locks."
  }
}
