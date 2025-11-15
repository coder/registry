run "required_vars" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }
}

run "with_version" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    aws_cli_version  = "2.15.0"
  }

  assert {
    condition     = resource.coder_script.aws-cli.script != ""
    error_message = "coder_script must have a valid script"
  }
}

run "custom_install_directory" {
  command = plan

  variables {
    agent_id          = "test-agent-id"
    install_directory = "/home/coder/.local"
  }

  assert {
    condition     = resource.coder_script.aws-cli.script != ""
    error_message = "coder_script must have a valid script"
  }
}

run "architecture_validation_x86_64" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    architecture = "x86_64"
  }

  assert {
    condition     = resource.coder_script.aws-cli.script != ""
    error_message = "coder_script must have a valid script"
  }
}

run "architecture_validation_aarch64" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    architecture = "aarch64"
  }

  assert {
    condition     = resource.coder_script.aws-cli.script != ""
    error_message = "coder_script must have a valid script"
  }
}

run "architecture_validation_invalid" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    architecture = "invalid"
  }

  expect_failures = [
    var.architecture
  ]
}

run "verify_signature" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    verify_signature = true
  }

  assert {
    condition     = resource.coder_script.aws-cli.script != ""
    error_message = "coder_script must have a valid script"
  }
}

run "output_version_default" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = output.aws_cli_version == "latest"
    error_message = "output version should be 'latest' when no version is specified"
  }
}

run "output_version_specified" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    aws_cli_version  = "2.15.0"
  }

  assert {
    condition     = output.aws_cli_version == "2.15.0"
    error_message = "output version should match the specified version"
  }
}
