mock_provider "coder" {}

run "plan_with_required_vars" {
  command = plan

  variables {
    agent_id = "example-agent-id"
    repo_dir = "/home/coder/repo"
  }
}

run "invalid_activate_shell_fails" {
  command = plan

  variables {
    agent_id        = "example-agent-id"
    repo_dir        = "/home/coder/repo"
    activate_shells = ["fish"]
  }

  expect_failures = [var.activate_shells]
}

run "empty_activate_shells_allowed" {
  command = plan

  variables {
    agent_id        = "example-agent-id"
    repo_dir        = "/home/coder/repo"
    activate_shells = []
  }
}

run "negative_wait_seconds_fails" {
  command = plan

  variables {
    agent_id     = "example-agent-id"
    repo_dir     = "/home/coder/repo"
    wait_seconds = -1
  }

  expect_failures = [var.wait_seconds]
}

run "custom_wait_seconds_allowed" {
  command = plan

  variables {
    agent_id     = "example-agent-id"
    repo_dir     = "/home/coder/repo"
    wait_seconds = 900
  }
}

run "custom_install_url_allowed" {
  command = plan

  variables {
    agent_id    = "example-agent-id"
    repo_dir    = "/home/coder/repo"
    install_url = "https://artifacts.internal.example.com/mise/install.sh"
  }
}

run "pinned_mise_version_allowed" {
  command = plan

  variables {
    agent_id     = "example-agent-id"
    repo_dir     = "/home/coder/repo"
    mise_version = "v2024.9.0"
  }
}

run "install_mise_false_plans" {
  command = plan

  variables {
    agent_id     = "example-agent-id"
    repo_dir     = "/home/coder/repo"
    install_mise = false
  }
}

run "bring_your_own_mise_bin_plans" {
  command = plan

  variables {
    agent_id     = "example-agent-id"
    repo_dir     = "/home/coder/repo"
    install_mise = false
    mise_bin     = "/opt/mise/bin/mise"
  }
}

run "apply_emits_scripts_output" {
  command = apply

  variables {
    agent_id = "example-agent-id"
    repo_dir = "/home/coder/repo"
  }

  assert {
    condition     = length(output.scripts) == 2
    error_message = "Expected scripts output to contain install + post_install entries."
  }

  assert {
    condition     = output.repo_dir == "/home/coder/repo"
    error_message = "Expected repo_dir output to echo the input."
  }
}
