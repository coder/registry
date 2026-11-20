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
    boot_script = "echo boot"
    files       = { "/tmp/quote'$(touch injected) 🐈" = "safe text" }
  }
  assert {
    condition     = length(nonsensitive(output.user_data)) < 16384 && startswith(nonsensitive(output.user_data), "#!/usr/bin/env bash")
    error_message = "User-data must remain a runnable, EC2-sized shell script."
  }
}

run "reject_relative_path" {
  command = plan
  variables {
    boot_script = "echo boot"
    files       = { "relative/file" = "bad" }
  }
  expect_failures = [var.files]
}

run "reject_noncanonical_runtime" {
  command = plan
  variables {
    boot_script = "echo boot"
    runtime_dir = "/run//coder"
  }
  expect_failures = [var.runtime_dir]
}
