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
    agent_token       = "token"
    agent_init_script = "echo init"
    files             = { "/tmp/quote'$(touch injected) 🐈" = "safe text" }
    log_display_name  = "quoted \" name 🐈"
  }
  assert {
    condition     = length(nonsensitive(output.user_data)) < 16384 && startswith(nonsensitive(output.user_data), "#!/usr/bin/env bash")
    error_message = "User-data must remain a runnable, EC2-sized shell script."
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
