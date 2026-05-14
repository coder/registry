run "plan_with_required_vars" {
  command = plan

  variables {
    agent_id         = "test-agent"
    workspace_id     = "test-workspace"
    pool_secret      = "test-pool-secret"
    self_evict_token = "test-self-token"
  }

  assert {
    condition     = length(resource.coder_env.pool_secret.value) > 0
    error_message = "pool_secret env should be set"
  }

  assert {
    condition     = resource.coder_env.capacity.value == "4"
    error_message = "default capacity should be 4"
  }

  assert {
    condition     = resource.coder_script.claude_runner.display_name == "Claude self-hosted runner"
    error_message = "expected the runner coder_script display_name"
  }
}

run "custom_capacity_and_binary_paths" {
  command = plan

  variables {
    agent_id           = "test-agent"
    workspace_id       = "test-workspace"
    pool_secret        = "test-pool-secret"
    self_evict_token   = "test-self-token"
    capacity           = 8
    claude_binary_path = "/custom/claude"
    runner_binary_path = "/custom/runner"
  }

  assert {
    condition     = resource.coder_env.capacity.value == "8"
    error_message = "capacity input should flow into CLAUDE_CAPACITY env"
  }

  assert {
    condition     = strcontains(resource.coder_script.claude_runner.script, "/custom/claude")
    error_message = "claude_binary_path should appear in the rendered script"
  }

  assert {
    condition     = strcontains(resource.coder_script.claude_runner.script, "/custom/runner")
    error_message = "runner_binary_path should appear in the rendered script"
  }
}

run "git_bot_token_optional" {
  command = plan

  variables {
    agent_id         = "test-agent"
    workspace_id     = "test-workspace"
    pool_secret      = "test-pool-secret"
    self_evict_token = "test-self-token"
  }

  assert {
    condition     = resource.coder_env.git_bot_token.value == ""
    error_message = "git_bot_token should default to empty string"
  }
}

run "capacity_validation_rejects_zero" {
  command = plan

  variables {
    agent_id         = "test-agent"
    workspace_id     = "test-workspace"
    pool_secret      = "test-pool-secret"
    self_evict_token = "test-self-token"
    capacity         = 0
  }

  expect_failures = [
    var.capacity,
  ]
}

run "capacity_validation_rejects_high" {
  command = plan

  variables {
    agent_id         = "test-agent"
    workspace_id     = "test-workspace"
    pool_secret      = "test-pool-secret"
    self_evict_token = "test-self-token"
    capacity         = 17
  }

  expect_failures = [
    var.capacity,
  ]
}

run "agent_metadata_output_has_four_items" {
  command = apply

  variables {
    agent_id         = "test-agent"
    workspace_id     = "test-workspace"
    pool_secret      = "test-pool-secret"
    self_evict_token = "test-self-token"
  }

  assert {
    condition     = length(output.agent_metadata) == 4
    error_message = "agent_metadata should expose four scraping items"
  }

  assert {
    condition     = output.agent_metadata[0].key == "0_lock_status"
    error_message = "first metadata item should be lock_status"
  }
}
