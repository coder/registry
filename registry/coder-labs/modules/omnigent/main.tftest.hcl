run "test_defaults" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.port == 6767
    error_message = "port should default to 6767"
  }

  assert {
    condition     = var.share == "owner"
    error_message = "share should default to owner"
  }

  assert {
    condition     = var.omnigent_version == "latest"
    error_message = "omnigent_version should default to latest"
  }

  assert {
    condition     = coder_app.omnigent.url == "http://localhost:6767"
    error_message = "coder_app url should use default port 6767"
  }

  assert {
    condition     = coder_app.omnigent.share == "owner"
    error_message = "coder_app share should default to owner"
  }
}

run "test_custom_port" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 8080
  }

  assert {
    condition     = var.port == 8080
    error_message = "port should be set to 8080"
  }

  assert {
    condition     = coder_app.omnigent.url == "http://localhost:8080"
    error_message = "coder_app url should use custom port 8080"
  }
}

run "test_custom_share" {
  command = plan

  variables {
    agent_id = "test-agent"
    share    = "authenticated"
  }

  assert {
    condition     = var.share == "authenticated"
    error_message = "share should be set to authenticated"
  }

  assert {
    condition     = coder_app.omnigent.share == "authenticated"
    error_message = "coder_app share should be authenticated"
  }
}

run "test_custom_version" {
  command = plan

  variables {
    agent_id         = "test-agent"
    omnigent_version = "0.1.0"
  }

  assert {
    condition     = var.omnigent_version == "0.1.0"
    error_message = "omnigent_version should be set to 0.1.0"
  }
}

run "test_scripts_output" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = length(output.scripts) > 0
    error_message = "scripts output should be non-empty"
  }
}

run "test_port_output" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 7777
  }

  assert {
    condition     = output.port == 7777
    error_message = "port output should match the configured port"
  }
}

run "test_invalid_port_low" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 80
  }

  expect_failures = [var.port]
}

run "test_invalid_port_high" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 65536
  }

  expect_failures = [var.port]
}

run "test_invalid_share" {
  command = plan

  variables {
    agent_id = "test-agent"
    share    = "invalid"
  }

  expect_failures = [var.share]
}
