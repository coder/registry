mock_provider "coder" {
  mock_data "coder_workspace" {
    defaults = {
      name       = "test"
      access_url = "https://coder.example"
    }
  }
  mock_data "coder_workspace_owner" {
    defaults = {
      name      = "owner"
      full_name = "Owner"
      email     = "owner@example.org"
    }
  }
}

mock_provider "random" {
  mock_resource "random_uuid" {
    defaults = {
      result = "11111111-1111-4111-8111-111111111111"
    }
  }
}

run "safe_render" {
  command = apply
  variables {
    agent_token       = "secret-token"
    agent_init_script = "echo init"
    files             = { "/tmp/quote'$(touch injected) 🐈" = "safe text" }
    log_display_name  = "quoted \" name 🐈"
  }
  assert {
    condition     = output.command[0] == "/run/current-system/sw/bin/bash" && !strcontains(join(" ", output.command), "secret-token")
    error_message = "The launcher must be a bash command that does not carry the token."
  }
  assert {
    condition     = length(nonsensitive(output.environment.CODER_INCUS_INIT_PAYLOAD)) < 131072
    error_message = "The payload must fit in one environment variable."
  }
}

run "reject_relative_path" {
  command = plan
  variables {
    agent_token       = "token"
    agent_init_script = "echo init"
    files             = { "relative/file" = "bad" }
  }
  expect_failures = [var.files]
}

run "reject_noncanonical_runtime" {
  command = plan
  variables {
    agent_token       = "token"
    agent_init_script = "echo init"
    runtime_dir       = "/run//coder"
  }
  expect_failures = [var.runtime_dir]
}

run "reject_unit_suffix" {
  command = plan
  variables {
    agent_token       = "token"
    agent_init_script = "echo init"
    unit_name         = "coder init.service;"
  }
  expect_failures = [var.unit_name]
}
