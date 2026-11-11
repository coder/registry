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

run "safe_render" {
  command = apply
  variables {
    agent_token         = "token"
    agent_init_script   = "echo init"
    builder_token       = "builder-token"
    builder_init_script = "echo builder"
    files               = { "/tmp/quote'$(touch injected) 🐈" = "safe text" }
  }
  assert {
    condition     = length(nonsensitive(output.user_data)) < 16384 && startswith(nonsensitive(output.user_data), "#!/usr/bin/env bash")
    error_message = "User-data must remain a runnable, EC2-sized shell script."
  }
}

run "reject_relative_path" {
  command = plan
  variables {
    agent_token         = "token"
    agent_init_script   = "echo init"
    builder_token       = "builder-token"
    builder_init_script = "echo builder"
    files               = { "relative/file" = "bad" }
  }
  expect_failures = [var.files]
}

run "reject_noncanonical_runtime" {
  command = plan
  variables {
    agent_token         = "token"
    agent_init_script   = "echo init"
    builder_token       = "builder-token"
    builder_init_script = "echo builder"
    runtime_dir         = "/run//coder"
  }
  expect_failures = [var.runtime_dir]
}
